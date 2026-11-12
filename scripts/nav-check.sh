#!/usr/bin/env bash
# Fail when the navigation and the pages disagree: a navigation entry without a page,
# a page outside the navigation, a redirect to nowhere or from a live page, or an
# internal link to a page or image that does not exist or only redirects.
# Usage: scripts/nav-check.sh [root]
set -u

root="${1:-.}"

python3 -I - "$root" <<'PY'
import json, os, re, sys

root = sys.argv[1]
config = json.load(open(os.path.join(root, "docs.json")))


def nav_pages(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from nav_pages(item)
    elif isinstance(node, dict):
        for key in ("languages", "tabs", "groups", "pages"):
            yield from nav_pages(node.get(key, []))


def page_exists(path):
    return os.path.isfile(os.path.join(root, path + ".mdx"))


pages = list(nav_pages(config.get("navigation", {})))
problems = []

for page in pages:
    if not page_exists(page):
        problems.append(f"navigation: {page} has no page")

files = []
for folder, dirs, names in os.walk(root):
    rel = os.path.relpath(folder, root)
    dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("scripts", "snippets", "node_modules", "fixtures", "tests")]
    for name in names:
        if name.endswith(".mdx"):
            files.append(os.path.normpath(os.path.join(rel, name[:-4])))
for page in sorted(set(files) - set(pages)):
    problems.append(f"page: {page} is not in the navigation")

redirected = set()
for redirect in config.get("redirects", []):
    source = redirect["source"].strip("/")
    target = redirect["destination"].strip("/")
    redirected.add(source)
    if page_exists(source):
        problems.append(f"redirect: {source} still has a page")
    if target and not page_exists(target):
        problems.append(f"redirect: {source} points to {target}, which has no page")

link = re.compile(r"\]\((/[^)\s#]*)|href=\"(/[^\"#]*)\"")
for page in files:
    text = open(os.path.join(root, page + ".mdx"), encoding="utf-8").read()
    for match in link.finditer(text):
        target = (match.group(1) or match.group(2)).strip("/")
        if not target or page_exists(target):
            continue
        if os.path.isfile(os.path.join(root, target)):
            continue
        reason = "only redirects" if target in redirected else "does not exist"
        problems.append(f"link: {page} links to /{target}, which {reason}")

for problem in problems:
    print(problem)
sys.exit(1 if problems else 0)
PY
