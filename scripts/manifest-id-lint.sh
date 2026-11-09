#!/usr/bin/env bash
# Fail when the capture manifest links an id other than the fixed ids of the docs-demo seed.
# Usage: scripts/manifest-id-lint.sh [manifest]
set -u

manifest="${1:-$(cd "$(dirname "$0")/.." && pwd)/images/captures/manifest.json}"
allowed='^019f0000-0000-7000-8000-00000000000[1-4]$'
status=0

if [ ! -f "$manifest" ]; then
  echo "manifest-id-lint: $manifest not found" >&2
  exit 2
fi

while IFS= read -r id; do
  if ! printf '%s' "$id" | grep -Eq "$allowed"; then
    echo "manifest-id-lint: $id is not a fixed docs-demo seed id" >&2
    status=1
  fi
done < <(grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$manifest" | sort -u)

exit "$status"
