#!/usr/bin/env bash
# Prove the leak lint passes clean content, fails each kind of leak and scans only what Mintlify publishes.
# Run: scripts/test-leak-lint.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
fixtures="$here/leak-lint-fixtures"
failures=0

# Fill a fresh git root with the command after the name and wanted exit code, lint it and compare.
expect_root() {
  local name="$1" want="$2" tmp got
  shift 2
  tmp=$(mktemp -d)
  git init -q "$tmp"
  (cd "$tmp" && "$@")
  "$here/leak-lint.sh" "$tmp" "$fixtures/config" >/dev/null
  got=$?
  rm -rf "$tmp"
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, wanted $want"
    failures=$((failures + 1))
  else
    echo "ok   $name: exit $got"
  fi
}

# Lint one fixture as the only page of a root.
expect() {
  expect_root "$1" "$2" cp "$fixtures/$1" page.mdx
}

# A leak in a path .mintignore excludes, beside a clean page.
leak_in_ignored_path() {
  cp "$fixtures/clean.mdx" page.mdx
  printf 'notes/\nimages/captures/*.json\n' >.mintignore
  mkdir -p notes images/captures
  cp "$fixtures/host.mdx" notes/plan.md
  printf '[{"finalUrl": "http://localhost:8000/management"}]\n' >images/captures/index.json
}

# A leak in a file Mintlify ignores by default, beside a clean page.
leak_in_default_ignored_file() {
  cp "$fixtures/clean.mdx" page.mdx
  cp "$fixtures/host.mdx" README.md
}

# A leak in a published data file that is not a page.
leak_in_published_json() {
  cp "$fixtures/clean.mdx" page.mdx
  mkdir -p images/captures
  printf '[{"finalUrl": "http://localhost:8000/management"}]\n' >images/captures/index.json
}

# A leak in a page outside the navigation, which Mintlify still publishes.
leak_in_unlisted_page() {
  cp "$fixtures/clean.mdx" page.mdx
  cp "$fixtures/checked.mdx" concept.md
}

expect clean.mdx 0
for leak in host email token table customer environment checked branch ticket internal; do
  expect "$leak.mdx" 1
done
expect_root "leak in a .mintignore path" 0 leak_in_ignored_path
expect_root "leak in a default-ignored file" 0 leak_in_default_ignored_file
expect_root "leak in a published json file" 1 leak_in_published_json
expect_root "leak in a page outside the navigation" 1 leak_in_unlisted_page

exit "$failures"
