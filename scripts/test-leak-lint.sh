#!/usr/bin/env bash
# Prove the leak lint passes clean content and fails each kind of leak.
# Run: scripts/test-leak-lint.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
fixtures="$here/leak-lint-fixtures"
failures=0

# Run the lint on one fixture copied to its own root and compare the exit code.
expect() {
  local fixture="$1" want="$2" tmp got
  tmp=$(mktemp -d)
  cp "$fixtures/$fixture" "$tmp/page.mdx"
  "$here/leak-lint.sh" "$tmp" "$fixtures/config" >/dev/null
  got=$?
  rm -rf "$tmp"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $fixture: exit $got, wanted $want"
    failures=$((failures + 1))
  else
    echo "ok   $fixture: exit $got"
  fi
}

expect clean.mdx 0
for leak in host email token table customer; do
  expect "$leak.mdx" 1
done

exit "$failures"
