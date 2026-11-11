#!/usr/bin/env bash
# Fail when a file Mintlify publishes leaks internal hostnames, environments, check methods,
# branch or ticket numbers, internal tool names, email addresses, tokens, table or customer names.
# Mintlify publishes every file outside its default ignores and .mintignore, so that is what is scanned.
# Usage: scripts/leak-lint.sh [root] [config-dir]   (root must be a git work tree)
set -u

root="${1:-.}"
config="${2:-$root/.github/leak-lint}"
status=0

# Print the files Mintlify publishes, relative to the root.
served() {
  local ignores all ignored
  ignores=$(mktemp)
  all=$(mktemp)
  ignored=$(mktemp)
  printf '%s\n' .git/ .github/ .claude/ .agents/ .idea/ .vscode/ .cursor/ .mintlify/ node_modules/ \
    README.md LICENSE.md CHANGELOG.md CONTRIBUTING.md >"$ignores"
  if [ -f "$root/.mintignore" ]; then
    cat "$root/.mintignore" >>"$ignores"
  fi
  (cd "$root" && find . -type f -not -path './.git/*' | sed 's|^\./||' | LC_ALL=C sort) >"$all"
  (cd "$root" && git -c core.excludesFile="$ignores" check-ignore --no-index --stdin <"$all" >"$ignored")
  if [ $? -gt 1 ]; then
    echo "leak-lint: $root is not a git work tree" >&2
    rm -f "$ignores" "$all" "$ignored"
    exit 2
  fi
  LC_ALL=C sort "$ignored" | LC_ALL=C comm -23 "$all" -
  rm -f "$ignores" "$all" "$ignored"
}

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(served)

if [ "${#files[@]}" -eq 0 ]; then
  echo "leak-lint: no published files found under $root" >&2
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
  hits=$(cd "$root" && grep -InE ${flag:+"$flag"} -e "$pattern" "${files[@]}" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "leak-lint: $label"
    echo "$hits" | sed 's/^/  /'
    status=1
  fi
}

scan "internal hostname" \
  '(localhost|\b[a-z0-9-]+(\.[a-z0-9-]+)*\.(internal|local|lan|corp|intranet)\b|\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b|[a-z0-9.-]+\.rds\.amazonaws\.com)' -i

scan "internal environment or demo data" \
  '(staging|\.stage\.|testomgeving|demo-?werkruimte|docs-demo)' -i

scan "how the page was checked" \
  '(laatst (gecontroleerd|geverifieerd)|(gecontroleerd|geverifieerd) (in|tegen|op) (de )?(demo|versie|tag|release|platform|[0-9]))' -i

scan "branch or release line" \
  '\b(release|hotfix)/[0-9]+\.[0-9]+' -i

scan "task, plan or pull request number" \
  '(\b(task|taak|plan|pr|pull request|issue|ticket)[ -]?#?[0-9]+\b|\b[a-z0-9_.-]+/[a-z0-9_.-]+#[0-9]+\b)' -i

emails=$(cd "$root" && grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "${files[@]}" 2>/dev/null || true)
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

for kind in table customer internal; do
  while IFS= read -r name; do
    scan "$kind name '$name'" "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)" -i
  done < <(entries "$config/$kind-names.txt")
done

if [ "$status" -eq 0 ]; then
  echo "leak-lint: clean (${#files[@]} files)"
fi
exit "$status"
