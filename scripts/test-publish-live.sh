#!/usr/bin/env bash
# Prove publish-live.sh merges only the live docs line into main, against a throwaway docs remote and a fake gh.
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
git clone --quiet "$tmp/origin.git" "$tmp/github" 2>/dev/null

# A fake gh that keeps one open pull request per head in $tmp/prs and merges it into the remote's main.
mkdir -p "$tmp/bin" "$tmp/prs"
cat > "$tmp/bin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "\$*" >> "$tmp/gh.log"
value() { local key="\$1"; shift; while [ \$# -gt 0 ]; do [ "\$1" = "\$key" ] && { echo "\$2"; return; }; shift; done; }
head="\$(value --head "\$@")"
case "\$1 \$2" in
  "pr list") [ -f "$tmp/prs/\${head//\//_}" ] && cat "$tmp/prs/\${head//\//_}" || echo "" ;;
  "pr create")
    url="https://github.com/transportklok/docs/pull/\$RANDOM"
    echo "\$head" > "$tmp/prs/\$(basename "\$url")"
    echo "\$url" > "$tmp/prs/\${head//\//_}"
    echo "Creating pull request"; echo "\$url" ;;
  "pr merge")
    [ "\$4" = "--repo" ] && [ "\$6" = "--merge" ] || { echo "unexpected merge: \$*" >&2; exit 1; }
    number="\$(basename "\$3")"; head="\$(cat "$tmp/prs/\$number")"
    cd "$tmp/github" && git fetch --quiet origin && git checkout --quiet -B main origin/main &&
      git merge --quiet --no-ff --no-edit "origin/\$head" && git push --quiet origin main
    rm -f "$tmp/prs/\$number" "$tmp/prs/\${head//\//_}" ;;
  *) echo "unexpected gh call: \$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

# Commit on a docs branch of the remote, creating it from $2 when given, and print the commit.
commit_on() {
  local branch="$1" from="${2:-}"
  (
    cd "$tmp/author"
    git fetch --quiet origin
    if [ -n "$from" ]; then git checkout --quiet -B "$branch" "$from"; else git checkout --quiet -B "$branch" "origin/$branch"; fi
    echo "$branch $RANDOM" > "${branch//\//_}.mdx"
    git add "${branch//\//_}.mdx"
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

# Succeed when the remote main holds commit $2.
expect_on_main() {
  local name="$1" commit="$2"
  if git --git-dir="$tmp/origin.git" merge-base --is-ancestor "$commit" refs/heads/main; then
    echo "ok   $name: main holds $commit"
  else
    echo "FAIL $name: main lacks $commit"
    failures=$((failures + 1))
  fi
}

# Succeed when the remote main lacks commit $2.
expect_off_main() {
  local name="$1" commit="$2"
  if git --git-dir="$tmp/origin.git" merge-base --is-ancestor "$commit" refs/heads/main; then
    echo "FAIL $name: main holds $commit"
    failures=$((failures + 1))
  else
    echo "ok   $name: main lacks $commit"
  fi
}

# Compare a remote ref with the commit it should hold.
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

# Count the gh calls of one kind.
gh_calls() {
  grep -c "^$1" "$tmp/gh.log" 2>/dev/null || true
}

(cd "$tmp/author" && git checkout --quiet -b main && echo base > page.mdx && git add page.mdx &&
  git commit --quiet -m base && git push --quiet origin main)
line_04="$(commit_on release/0.4 main)"

expect "bad release tag" 1 release 0.4
expect "correction mode is gone" 1 correction 0.4
expect "missing docs line" 1 release 0.9.0
expect_off_main "unreleased line stays off main" "$line_04"

expect "first release merges its line into main" 0 release 0.4.0
expect_on_main "first release" "$line_04"
expect_ref "release records its live line" refs/tags/0.4.0 "$line_04"
[ "$(gh_calls "pr merge")" = 1 ] && echo "ok   merged by one pull request" ||
  { echo "FAIL merged by one pull request"; failures=$((failures + 1)); }

line_05_cut="$(commit_on release/0.5 release/0.4)"
expect_off_main "next line stays off main before its release" "$line_05_cut"

line_04="$(commit_on release/0.4)"
expect_off_main "a live-line correction waits for its hotfix tag" "$line_04"
expect "hotfix release on the live line" 0 release 0.4.1
expect_on_main "hotfix merges the live line" "$line_04"
expect_ref "hotfix records its tag" refs/tags/0.4.1 "$line_04"

expect "repeated release is idempotent" 0 release 0.4.1
[ "$(gh_calls "pr merge")" = 2 ] && echo "ok   repeated release opens no pull request" ||
  { echo "FAIL repeated release opens no pull request"; failures=$((failures + 1)); }

expect "next line release" 0 release 0.5.0
expect_on_main "next line goes live" "$line_05_cut"

line_04_late="$(commit_on release/0.4)"
expect "release from an older line" 0 release 0.4.2
expect_off_main "older line publishes nothing" "$line_04_late"
expect_ref "older line records no tag" refs/tags/0.4.2 ""

line_05="$(commit_on release/0.5)"
echo "https://github.com/transportklok/docs/pull/77" > "$tmp/prs/release_0.5"
echo "release/0.5" > "$tmp/prs/77"
expect "release reuses the open pull request" 0 release 0.5.1
expect_on_main "reused pull request merges the line" "$line_05"
grep -q "pr merge https://github.com/transportklok/docs/pull/77 " "$tmp/gh.log" && echo "ok   merged the open pull request" ||
  { echo "FAIL merged the open pull request"; failures=$((failures + 1)); }

if [ "$failures" -ne 0 ]; then
  echo "$failures publisher check(s) failed"
  exit 1
fi
echo "publish-live: all checks passed"
