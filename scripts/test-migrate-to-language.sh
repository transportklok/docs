#!/usr/bin/env bash
# Prove the language migration moves pages, rewrites links, moves the navigation and generates the redirects.
# Run: scripts/test-migrate-to-language.sh
set -u

here="$(cd "$(dirname "$0")" && pwd)"
tmp=$(mktemp -d)
failures=0
mkdir -p "$tmp/beheerders/urenbeheer/tijdregistratie" "$tmp/medewerkers/start-dir" "$tmp/api"
printf -- '---\ntitle: "Home"\n---\n\nZie [uren](/beheerders/urenbeheer/tijdregistratie/overzicht#top).\n' > "$tmp/index.mdx"
printf -- '---\ntitle: "Overzicht"\n---\n\nTerug naar [home](/).\n' > "$tmp/beheerders/urenbeheer/tijdregistratie/overzicht.mdx"
printf -- '---\ntitle: "Intro"\n---\n' > "$tmp/api/introduction.mdx"
cat > "$tmp/docs.json" <<'JSON'
{"navigation":{"tabs":[{"tab":"B","groups":[{"group":"G","pages":["index","beheerders/urenbeheer/tijdregistratie/overzicht","api/introduction"]}]}]},
 "redirects":[{"source":"/api/introductie","destination":"/api/introduction"}]}
JSON

python3 -I "$here/migrate-to-language.py" "$tmp" nl > /dev/null || failures=$((failures + 1))

check() {
  if python3 -I -c "$1" "$tmp"; then echo "ok   $2"; else echo "FAIL $2"; failures=$((failures + 1)); fi
}

check 'import os,sys; r=sys.argv[1]; assert os.path.isfile(r+"/nl/management/hour-management/time-registrations/overview.mdx") and not os.path.exists(r+"/beheerders")' "page moved to its English path under nl/"
check 'import sys; t=open(sys.argv[1]+"/nl/index.mdx").read(); assert "(/nl/management/hour-management/time-registrations/overview#top)" in t' "link rewritten and anchor kept"
check 'import sys; t=open(sys.argv[1]+"/nl/management/hour-management/time-registrations/overview.mdx").read(); assert "(/nl/index)" in t' "link to the root points at the language home"
check 'import json,sys; d=json.load(open(sys.argv[1]+"/docs.json")); l=d["navigation"]["languages"][0]; assert l["language"]=="nl" and l["default"] and "nl/index" in json.dumps(l["tabs"])' "navigation declared under the nl language"
check 'import json,sys; r={x["source"]:x["destination"] for x in json.load(open(sys.argv[1]+"/docs.json"))["redirects"]}; assert r["/beheerders/urenbeheer/tijdregistratie/overzicht"]=="/nl/management/hour-management/time-registrations/overview" and r["/api/introductie"]=="/nl/api/introduction" and r["/"]=="/nl/index"' "redirects generated and old redirects retargeted"
"$here/nav-check.sh" "$tmp" > /dev/null && echo "ok   nav-check passes on the migrated site" || { echo "FAIL nav-check on the migrated site"; failures=$((failures + 1)); }

rm -rf "$tmp"
exit "$failures"
