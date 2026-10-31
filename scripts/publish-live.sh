#!/usr/bin/env bash
# Move the Mintlify deploy branch docs-live forward to the head of a docs release line.
# Usage: scripts/publish-live.sh release X.Y.Z   (after Platform X.Y.Z deployed to production)
#        scripts/publish-live.sh correction X.Y  (after a push to docs release/X.Y)
# Run it inside a clone of the docs repository whose remote may be pushed to.
# A plain X.Y.Z tag on a docs line records that Platform X.Y.Z went live with it;
# the highest such tag names the live line.
set -euo pipefail

mode="${1:-}"
version="${2:-}"
remote="${PUBLISH_REMOTE:-origin}"
publish_branch=docs-live

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

case "$mode" in
  release)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release needs a X.Y.Z Platform tag, got '$version'"
    line="${version%.*}"
    ;;
  correction)
    [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || fail "correction needs a X.Y docs line, got '$version'"
    line="$version"
    ;;
  *)
    fail "usage: publish-live.sh release X.Y.Z | correction X.Y"
    ;;
esac

git fetch --quiet --prune --prune-tags --tags "$remote" "+refs/heads/*:refs/remotes/$remote/*"

target="$(git rev-parse --verify --quiet "refs/remotes/$remote/release/$line^{commit}")" ||
  fail "the docs repository has no release/$line"
published="$(git rev-parse --verify --quiet "refs/remotes/$remote/$publish_branch^{commit}" || true)"
current_line="$(live_line)"

if [ "$mode" = correction ] && [ "$line" != "$current_line" ]; then
  echo "publish-live: release/$line is not the live line (${current_line:-none yet}); nothing published."
  exit 0
fi
if [ -n "$current_line" ] && line_before "$line" "$current_line"; then
  echo "publish-live: release/$line is older than the live line $current_line; nothing published."
  exit 0
fi

push_arguments=()
if [ -z "$published" ]; then
  echo "publish-live: creating $publish_branch at release/$line ($target)."
  push_arguments+=("$target:refs/heads/$publish_branch")
elif git merge-base --is-ancestor "$target" "$published"; then
  echo "publish-live: $publish_branch already holds release/$line ($target); nothing to move."
elif git merge-base --is-ancestor "$published" "$target"; then
  echo "publish-live: moving $publish_branch forward to release/$line ($target)."
  push_arguments+=("$target:refs/heads/$publish_branch")
elif [ "$mode" = release ] && [ "$line" != "$current_line" ]; then
  echo "publish-live: moving $publish_branch to the new line release/$line ($target)."
  push_arguments+=("--force-with-lease=refs/heads/$publish_branch:$published" "$target:refs/heads/$publish_branch")
else
  fail "$publish_branch ($published) has diverged from release/$line ($target); it was moved outside this publisher"
fi

if [ "$mode" = release ] && ! git rev-parse --verify --quiet "refs/tags/$version" >/dev/null; then
  git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    tag -a "$version" -m "Docs live with Platform $version" "$target"
  push_arguments+=("refs/tags/$version")
fi

if [ "${#push_arguments[@]}" -gt 0 ]; then
  git push --quiet --atomic "$remote" "${push_arguments[@]}"
fi
