#!/usr/bin/env python3
"""Builds .translations/glossary.json: every UI label of the app in nl, en, de, pl and ro, keyed by its label file and key."""

import argparse
import json
import sys
from pathlib import Path

LANGUAGES = ("nl", "en", "de", "pl", "ro")
# The app's label files, relative to the workspace; {lang} is the language code.
SOURCES = (
    "mytimeflow/resources/js/i18n/languages/{lang}.json",
    "mytimeflow/resources/js/i18n/languages/*/{lang}.json",
    "mytimeflow/lang/{lang}/*.json",
    "platform/resources/js/i18n/languages/{lang}.json",
    "platform/lang/{lang}.json",
    "platform/lang/{lang}/*.json",
    "shared.js/src/i18n/languages/{lang}.json",
)


def flatten(value, prefix=""):
    """Yield each string label of a label file as a dotted key and its text."""
    if isinstance(value, dict):
        for key, child in value.items():
            yield from flatten(child, f"{prefix}.{key}" if prefix else key)
    elif isinstance(value, str):
        yield prefix, value


def label_files(workspace, source):
    """Yield each label file of a source as its {lang} path and its file per language."""
    for base in sorted(workspace.glob(source.format(lang=LANGUAGES[0]))):
        path = base.relative_to(workspace).as_posix()
        template = path.replace(f"/{LANGUAGES[0]}/", "/{lang}/").replace(f"/{LANGUAGES[0]}.json", "/{lang}.json")
        yield template, {lang: workspace / template.format(lang=lang) for lang in LANGUAGES}


def build(workspace):
    """Return the glossary: each label id with its text in every language that has it."""
    labels = {}
    for source in SOURCES:
        for template, files in label_files(workspace, source):
            for lang, path in files.items():
                if not path.is_file():
                    continue
                for key, text in flatten(json.loads(path.read_text(encoding="utf-8"))):
                    labels.setdefault(f"{template}#{key}", {})[lang] = text
    return {"languages": list(LANGUAGES), "labels": dict(sorted(labels.items()))}


def render(glossary):
    """Return the glossary as JSON with one label a line, so a changed label is a one-line diff."""
    lines = [f" {json.dumps(key, ensure_ascii=False)}: {json.dumps(texts, ensure_ascii=False)}" for key, texts in glossary["labels"].items()]
    return f'{{"languages": {json.dumps(glossary["languages"])}, "labels": {{\n' + ",\n".join(lines) + "\n}}\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=Path(__file__).resolve().parents[2], help="the folder holding mytimeflow, platform and shared.js")
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / ".translations" / "glossary.json")
    args = parser.parse_args()
    glossary = build(args.workspace)
    if not glossary["labels"]:
        sys.exit(f"no label files found under {args.workspace}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(glossary), encoding="utf-8")
    missing = {lang: sum(lang not in texts for texts in glossary["labels"].values()) for lang in LANGUAGES}
    print(f"{len(glossary['labels'])} labels written to {args.out}; missing per language: {missing}")


if __name__ == "__main__":
    main()
