#!/usr/bin/env bash
# Fail when published docs content leaks internal hostnames, email addresses,
# tokens, table names or customer names.
# Usage: scripts/leak-lint.sh [root] [config-dir]
set -u

root="${1:-.}"
config="${2:-$root/.github/leak-lint}"
status=0

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(cd "$root" && find . -type f \( -name '*.md' -o -name '*.mdx' -o -name 'docs.json' \) \
  -not -path './.git/*' -not -path './.github/*' -not -path './scripts/*' \
  -not -path './node_modules/*' -not -path './images/*' \
  -not -name 'README.md' -not -name 'AGENTS.md' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "leak-lint: no content files found under $root" >&2
  exit 2
fi

# Print the entries of a list file, comments and blanks removed.
entries() {
  if [ -f "$1" ]; then
    grep -vE '^[[:space:]]*(#|$)' "$1" || true
  fi
}

# Report every line matching an extended regex; $3 is an optional grep flag.
scan() {
  local label="$1" pattern="$2" flag="${3:-}" hits
  hits=$(cd "$root" && grep -nE ${flag:+"$flag"} -e "$pattern" "${files[@]}" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "leak-lint: $label"
    echo "$hits" | sed 's/^/  /'
    status=1
  fi
}

scan "internal hostname" \
  '(localhost|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(internal|local|lan|corp|intranet)\b|\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b|[a-z0-9.-]+\.rds\.amazonaws\.com)' -i

emails=$(cd "$root" && grep -noE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${files[@]}" 2>/dev/null || true)
while IFS= read -r allowed; do
  emails=$(echo "$emails" | grep -viF -e "$allowed" || true)
done < <(entries "$config/allowed-emails.txt")
if [ -n "$emails" ]; then
  echo "leak-lint: email address"
  echo "$emails" | sed 's/^/  /'
  status=1
fi

scan "token or secret" \
  '(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[ousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[Bb]earer [A-Za-z0-9._~+/=-]{24,})'

scan "SQL statement on a table" \
  '\b(FROM|JOIN|INSERT INTO|UPDATE)[[:space:]]+[a-z_]+[[:space:]]+(WHERE|SET|VALUES|ON|LIMIT)\b' -i

for kind in table customer; do
  while IFS= read -r name; do
    scan "$kind name '$name'" "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)" -i
  done < <(entries "$config/$kind-names.txt")
done

if [ "$status" -eq 0 ]; then
  echo "leak-lint: clean (${#files[@]} files)"
fi
exit "$status"
