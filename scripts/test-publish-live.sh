#!/usr/bin/env bash
# Prove publish-live.sh moves docs-live only forward, against a throwaway docs remote.
# Run: scripts/test-publish-live.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
publisher="$here/publish-live.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

git init --quiet --bare "$tmp/origin.git"
git clone --quiet "$tmp/origin.git" "$tmp/author" 2>/dev/null
git clone --quiet "$tmp/origin.git" "$tmp/runner" 2>/dev/null

# Commit on a docs branch of the remote, creating it from $2 when given, and print the commit.
commit_on() {
  local branch="$1" from="${2:-}"
  (
    cd "$tmp/author"
    if [ -n "$from" ]; then git checkout --quiet -B "$branch" "$from"; else git checkout --quiet "$branch"; fi
    echo "$branch $RANDOM" >> page.mdx
    git add page.mdx
    git commit --quiet -m "change on $branch"
    git push --quiet origin "$branch"
    git rev-parse HEAD
  )
}

# Print the remote commit of a ref, or nothing when it does not exist.
remote_ref() {
  git --git-dir="$tmp/origin.git" rev-parse --verify --quiet "$1^{commit}" || true
}

# Run the publisher in the runner clone and compare its exit code.
expect() {
  local name="$1" want="$2" got
  shift 2
  (cd "$tmp/runner" && "$publisher" "$@") >/dev/null 2>&1
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, wanted $want"
    failures=$((failures + 1))
  else
    echo "ok   $name: exit $got"
  fi
}

# Compare docs-live, or another remote ref, with the commit it should hold.
expect_ref() {
  local name="$1" ref="$2" want="$3" got
  got="$(remote_ref "$ref")"
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: $ref is '${got:-missing}', wanted '${want:-missing}'"
    failures=$((failures + 1))
  else
    echo "ok   $name: $ref is ${got:-missing}"
  fi
}

(cd "$tmp/author" && git checkout --quiet -b main && echo base > page.mdx && git add page.mdx &&
  git commit --quiet -m base && git push --quiet origin main)
line_04="$(commit_on release/0.4 main)"

expect "bad release tag" 1 release 0.4
expect "bad correction line" 1 correction 0.4.0
expect "missing docs line" 1 release 0.9.0
expect_ref "missing line publishes nothing" refs/heads/docs-live ""

expect "first release creates docs-live" 0 release 0.4.0
expect_ref "first release" refs/heads/docs-live "$line_04"
expect_ref "release records its live line" refs/tags/0.4.0 "$line_04"

line_05_cut="$(commit_on release/0.5 main)"
expect "correction on a line not yet live" 0 correction 0.5
expect_ref "not-live line publishes nothing" refs/heads/docs-live "$line_04"

line_04="$(commit_on release/0.4)"
expect "correction on the live line" 0 correction 0.4
expect_ref "live-line correction moves docs-live" refs/heads/docs-live "$line_04"

line_04="$(commit_on release/0.4)"
expect "hotfix release on the live line" 0 release 0.4.1
expect_ref "hotfix moves docs-live forward" refs/heads/docs-live "$line_04"
expect_ref "hotfix records its tag" refs/tags/0.4.1 "$line_04"

expect "next line release" 0 release 0.5.0
expect_ref "next line moves docs-live past the diverged old line" refs/heads/docs-live "$line_05_cut"

line_04_late="$(commit_on release/0.4)"
expect "release from an older line" 0 release 0.4.2
expect "correction on an older line" 0 correction 0.4
expect_ref "older line publishes nothing" refs/heads/docs-live "$line_05_cut"
expect_ref "older line records no tag" refs/tags/0.4.2 ""

line_05="$(commit_on release/0.5)"
git --git-dir="$tmp/origin.git" update-ref refs/heads/docs-live "$line_05"
git --git-dir="$tmp/origin.git" update-ref refs/heads/release/0.5 "$line_05_cut"
expect "release whose line head is older than docs-live" 0 release 0.5.1
expect_ref "older commit publishes nothing" refs/heads/docs-live "$line_05"

git --git-dir="$tmp/origin.git" update-ref refs/heads/docs-live "$line_04_late"
expect "correction on a live line that docs-live diverged from" 1 correction 0.5
expect_ref "diverged live line publishes nothing" refs/heads/docs-live "$line_04_late"

if [ "$failures" -ne 0 ]; then
  echo "$failures publisher check(s) failed"
  exit 1
fi
echo "publish-live: all checks passed"
