#!/usr/bin/env bash
# Prove the navigation check passes a consistent site and fails each kind of mismatch.
# Run: scripts/test-nav-check.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
failures=0

# Build a small site whose docs.json is the first argument, with pages a and b.
site() {
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/sub" "$tmp/images"
  printf '%s\n' "$1" > "$tmp/docs.json"
  printf -- '---\ntitle: "A"\n---\n\nZie [B](/sub/b) en ![x](/images/x.png).\n' > "$tmp/a.mdx"
  printf -- '---\ntitle: "B"\n---\n\nTerug naar [A](/a).\n' > "$tmp/sub/b.mdx"
  : > "$tmp/images/x.png"
  echo "$tmp"
}

# Run the check on a site and compare the exit code.
expect() {
  local name="$1" want="$2" tmp="$3" got
  "$here/nav-check.sh" "$tmp" >/dev/null
  got=$?
  rm -rf "$tmp"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, wanted $want"
    failures=$((failures + 1))
  else
    echo "ok   $name: exit $got"
  fi
}

nav='"navigation":{"tabs":[{"tab":"T","groups":[{"group":"G","pages":["a",{"group":"S","pages":["sub/b"]}]}]}]}'

expect consistent 0 "$(site "{$nav,\"redirects\":[{\"source\":\"/old\",\"destination\":\"/a\"}]}")"

tmp=$(site "{$nav}"); rm "$tmp/sub/b.mdx"; printf -- '---\ntitle: "A"\n---\n' > "$tmp/a.mdx"
expect missing-page 1 "$tmp"

tmp=$(site "{$nav}"); printf -- '---\ntitle: "C"\n---\n' > "$tmp/c.mdx"
expect orphan-page 1 "$tmp"

expect redirect-to-nowhere 1 "$(site "{$nav,\"redirects\":[{\"source\":\"/old\",\"destination\":\"/gone\"}]}")"

expect redirect-from-live-page 1 "$(site "{$nav,\"redirects\":[{\"source\":\"/a\",\"destination\":\"/sub/b\"}]}")"

tmp=$(site "{$nav,\"redirects\":[{\"source\":\"/old\",\"destination\":\"/a\"}]}"); printf -- '---\ntitle: "B"\n---\n\nZie [oud](/old).\n' > "$tmp/sub/b.mdx"
expect link-to-redirect 1 "$tmp"

tmp=$(site "{$nav}"); printf -- '---\ntitle: "B"\n---\n\nZie <Card href="/nergens">x</Card>.\n' > "$tmp/sub/b.mdx"
expect link-to-nowhere 1 "$tmp"

tmp=$(site "{$nav}"); rm "$tmp/images/x.png"
expect missing-image 1 "$tmp"

exit "$failures"
