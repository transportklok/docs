#!/usr/bin/env bash
# Merge a docs release line into main by pull request once its Platform tag runs in production.
# Usage: scripts/publish-live.sh release X.Y.Z   (after Platform X.Y.Z deployed to production)
# Run it inside a clone of the docs repository whose remote may be pushed to, with GH_TOKEN
# allowed to open and merge pull requests in PUBLISH_REPOSITORY (transportklok/docs by default).
# Mintlify deploys main, so main only ever holds the docs of what runs in production.
# A plain X.Y.Z tag on a docs line records that Platform X.Y.Z went live with it;
# the highest such tag names the live line.
set -euo pipefail

mode="${1:-}"
version="${2:-}"
remote="${PUBLISH_REMOTE:-origin}"
repository="${PUBLISH_REPOSITORY:-transportklok/docs}"

fail() {
  echo "publish-live: $*" >&2
  exit 1
}

# Succeed when line $1 sorts before line $2.
line_before() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]
}

# Print the X.Y of the highest X.Y.Z tag, or nothing before the first release publish.
live_line() {
  git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 | cut -d. -f1,2 || true
}

[ "$mode" = release ] || fail "usage: publish-live.sh release X.Y.Z"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release needs a X.Y.Z Platform tag, got '$version'"
line="${version%.*}"
branch="release/$line"

git fetch --quiet --prune --prune-tags --tags "$remote" "+refs/heads/*:refs/remotes/$remote/*"

target="$(git rev-parse --verify --quiet "refs/remotes/$remote/$branch^{commit}")" ||
  fail "the docs repository has no $branch"
main="$(git rev-parse --verify --quiet "refs/remotes/$remote/main^{commit}")" ||
  fail "the docs repository has no main"
current_line="$(live_line)"

if [ -n "$current_line" ] && line_before "$line" "$current_line"; then
  echo "publish-live: $branch is older than the live line $current_line; nothing published."
  exit 0
fi

if git merge-base --is-ancestor "$target" "$main"; then
  echo "publish-live: main already holds $branch ($target); nothing to merge."
else
  url="$(gh pr list --repo "$repository" --head "$branch" --base main --state open --json url --jq '.[0].url // ""')"
  if [ -z "$url" ]; then
    url="$(gh pr create --repo "$repository" --head "$branch" --base main \
      --title "Publish docs $branch with Platform $version" \
      --body "Platform $version runs in production, so its docs line \`$branch\` goes live on main. Opened and merged by the Platform production workflow." |
      tail -n 1)"
  fi
  echo "publish-live: merging $branch ($target) into main through $url."
  gh pr merge "$url" --repo "$repository" --merge
  git fetch --quiet "$remote" "+refs/heads/main:refs/remotes/$remote/main"
  git merge-base --is-ancestor "$target" "refs/remotes/$remote/main" ||
    fail "main does not hold $branch ($target) after merging $url"
fi

if ! git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    tag -a "$version" -m "Docs live with Platform $version" "$target"
  git push --quiet "$remote" "refs/tags/$version"
fi
