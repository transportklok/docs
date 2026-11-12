#!/usr/bin/env python3
"""Translates every new or changed Dutch page under nl/ into en, de, pl and ro, naming UI labels as the glossary does, or checks they are in step."""

import argparse
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1]
BASE = "nl"
LANGUAGES = {"en": "English", "de": "German", "pl": "Polish", "ro": "Romanian"}
MODEL = "claude-opus-5-5"
TRANSLATABLE_KEYS = ("title", "description")
TRANSLATABLE_ATTRIBUTES = ("title", "description", "alt")
MARKER = re.compile(r"^\{/\* translated-from: (\S+) sha256:([0-9a-f]{64}) \*/\}\n", re.MULTILINE)
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.DOTALL)
FENCE = re.compile(r"^```.*?^```", re.DOTALL | re.MULTILINE)
INLINE_CODE = re.compile(r"`[^`\n]+`")
LINK = re.compile(r"\]\(([^)\s]+)")
TAG = re.compile(r"<(/?)([A-Z][\w.]*)((?:\s+[\w-]+(?:=(?:\"[^\"]*\"|\{[^}]*\}))?)*)\s*(/?)>")
ATTRIBUTE = re.compile(r"([\w-]+)(?:=(\"[^\"]*\"|\{[^}]*\}))?")
REFERENCE = re.compile(r"(?:\]\(|(?:href|src)=\{?\")([^)\"\s]+)")
BOLD = re.compile(r"\*\*([^*\n]+)\*\*")
HEADING = re.compile(r"^#{1,6} ", re.MULTILINE)
SYSTEM = """You translate one page of the Transportklok user documentation, a Mintlify MDX file, from Dutch.
Return only the translated file, with no code fence around it and no comment of your own.
Keep the frontmatter keys and every value except title and description exactly as they are; translate those two.
Keep code blocks, inline code, import lines, URLs, link targets, image paths and component tags with their attribute names exactly as they are; translate only the text between tags and the title, description and alt attributes.
Keep every heading, list item and paragraph, in the same order; translate headings.
Write UI labels in bold exactly as the glossary of this page gives them, never a translation of your own.
Address the reader formally where the language has a formal form (Sie in German, Pan/Pani in Polish, dumneavoastră in Romanian)."""


class PageRefused(Exception):
    """A translation that does not keep the base page's structure."""

    @classmethod
    def because(cls, page, errors):
        """Name the page and every way its translation differs from the base."""
        return cls(f"{page}: " + "; ".join(errors))


def page_hash(text):
    """Return the sha256 of a page's text."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def target_path(base_page, lang):
    """Return the path of a base page's translation, the same path under the language's folder."""
    return Path(lang, *base_page.parts[1:])


def recorded_hash(text):
    """Return the base hash a translation records, or an empty string when it records none."""
    match = MARKER.search(text)
    return match.group(2) if match else ""


def localise_links(text, lang):
    """Point every link and screenshot of the base language at the same page or screenshot of the target language."""
    return re.sub(rf"(\]\(|(?:href|src)=\{{?\")(/images)?/{BASE}/", rf"\1\2/{lang}/", text)


def frontmatter(text):
    """Return the frontmatter's keys and values in order, and the body after it."""
    match = FRONTMATTER.match(text)
    if not match:
        return [], text
    pairs = [tuple(part.strip() for part in line.split(":", 1)) for line in match.group(1).splitlines() if ":" in line and not line.startswith(" ")]
    return pairs, text[match.end():]


def tags(body):
    """Return each component tag as its name and the attributes that must not change."""
    found = []
    for closing, name, attributes, _ in TAG.findall(body):
        kept = tuple((key, value) for key, value in ATTRIBUTE.findall(attributes) if key not in TRANSLATABLE_ATTRIBUTES)
        found.append((closing, name, kept))
    return found


class Glossary:
    """The app's UI labels in every language, looked up by their Dutch text."""

    def __init__(self, path):
        self.by_dutch, self.texts = {}, {}
        for texts in json.loads(path.read_text(encoding="utf-8"))["labels"].values():
            if BASE in texts:
                self.by_dutch.setdefault(texts[BASE], []).append(texts)
            for lang, text in texts.items():
                self.texts.setdefault(lang, set()).add(text)

    def has(self, label, lang):
        """Tell whether the app shows a label with this text in a language."""
        return label in self.texts.get(lang, set())

    def labels(self, page, lang):
        """Return each bold label of a page with the target texts the app uses for it."""
        return {label: sorted({texts[lang] for texts in self.by_dutch.get(label, []) if lang in texts}) for label in dict.fromkeys(BOLD.findall(page))}


def differences(source, translation, labels):
    """Return every way a translation breaks the structure of its (link-localised) source page."""
    errors = []
    source_pairs, source_body = frontmatter(source)
    target_pairs, target_body = frontmatter(translation)
    if [key for key, _ in source_pairs] != [key for key, _ in target_pairs]:
        errors.append("frontmatter keys differ")
    kept = [(key, value) for key, value in source_pairs if key not in TRANSLATABLE_KEYS]
    if kept != [(key, value) for key, value in target_pairs if key not in TRANSLATABLE_KEYS]:
        errors.append("frontmatter values other than title and description changed")
    if FENCE.findall(source_body) != FENCE.findall(target_body):
        errors.append("code blocks changed")
    if Counter(INLINE_CODE.findall(FENCE.sub("", source_body))) != Counter(INLINE_CODE.findall(FENCE.sub("", target_body))):
        errors.append("inline code changed")
    if LINK.findall(source_body) != LINK.findall(target_body):
        errors.append("link targets changed")
    if tags(source_body) != tags(target_body):
        errors.append("component tags or their attributes changed")
    if len(HEADING.findall(source_body)) != len(HEADING.findall(target_body)):
        errors.append("number of headings changed")
    if len(BOLD.findall(source_body)) != len(BOLD.findall(target_body)):
        errors.append("number of bold labels changed")
    bold = set(BOLD.findall(translation))
    for label, options in labels.items():
        if options and not bold.intersection(options):
            errors.append(f"bold label {label!r} is not written as {' or '.join(repr(option) for option in options)}")
    return errors


def prompt(page, lang, labels):
    """Return the request text for one page: the target language, its glossary and the page."""
    glossary = "\n".join(f"- {label} → {' or '.join(options)}" for label, options in labels.items() if options) or "- (none)"
    return f"Translate into {LANGUAGES[lang]}.\n\nGlossary of this page (Dutch → {LANGUAGES[lang]}):\n{glossary}\n\nPage:\n{page}"


class ClaudeTranslator:
    """Translates through the Claude API with a pinned model and effort."""

    def __init__(self):
        import anthropic

        self.client = anthropic.Anthropic()

    def __call__(self, request):
        with self.client.beta.messages.stream(
            model=MODEL,
            max_tokens=64000,
            output_config={"effort": "high"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
            system=SYSTEM,
            messages=[{"role": "user", "content": request}],
        ) as stream:
            message = stream.get_final_message()
        if message.stop_reason != "end_turn":
            raise RuntimeError(f"the model stopped with {message.stop_reason}")
        return "".join(block.text for block in message.content if block.type == "text")


def unfence(reply):
    """Return a reply without the code fence a model may wrap a whole page in."""
    return re.sub(r"\A```\w*\n(.*)\n```\Z", r"\1", reply, flags=re.DOTALL) if reply.startswith("```") else reply


def translate_page(base_page, text, lang, glossary, translator):
    """Return the translation of a base page with its base hash recorded, retrying once with the errors."""
    source = localise_links(text, lang)
    labels = glossary.labels(source, lang)
    request = prompt(source, lang, labels)
    for _ in range(2):
        translation = unfence(translator(request).strip()) + "\n"
        errors = differences(source, translation, labels)
        if not errors:
            break
        request = f"{prompt(source, lang, labels)}\n\nYour previous translation was refused: {'; '.join(errors)}. Translate again."
    else:
        raise PageRefused.because(f"{target_path(base_page, lang)}", errors)
    marker = f"{{/* translated-from: {base_page.as_posix()} sha256:{page_hash(text)} */}}\n"
    match = FRONTMATTER.match(translation)
    head, body = (translation[:match.end()], translation[match.end():]) if match else ("", translation)
    return head + marker + body


def stale_pages(docs, languages):
    """Yield each base page and language whose translation is missing or records another base hash."""
    for base_page in sorted(path.relative_to(docs) for path in (docs / BASE).rglob("*.mdx")):
        current = page_hash((docs / base_page).read_text(encoding="utf-8"))
        for lang in languages:
            target = docs / target_path(base_page, lang)
            if not target.is_file() or recorded_hash(target.read_text(encoding="utf-8")) != current:
                yield base_page, lang


def unresolved(docs, page, reference):
    """Return why a link or image of a page does not resolve inside its own language, or an empty string; a Dutch screenshot stands in until the language has its own."""
    if re.match(r"[a-z][a-z0-9+.-]*:|#|//", reference):
        return ""
    path = reference.split("#", 1)[0].split("?", 1)[0]
    target = ((docs / path.lstrip("/")) if path.startswith("/") else (docs / page).parent / path).resolve()
    if not target.is_relative_to(docs.resolve()):
        return f"{reference} points outside the docs"
    relative = target.relative_to(docs.resolve())
    if relative.suffix:
        if relative.parts[:1] == ("images",) and relative.parts[1:2] != page.parts[:1] and relative.parts[1] != BASE and relative.parts[1] in LANGUAGES:
            return f"{reference} is a {relative.parts[1]} screenshot"
        return "" if (docs / relative).is_file() else f"{reference} does not exist"
    if relative.parts[:1] != page.parts[:1]:
        return f"{reference} leaves the {page.parts[0]} pages"
    exists = (docs / relative).with_suffix(".mdx").is_file() or (docs / relative / "index.mdx").is_file()
    return "" if exists else f"{reference} is not a page"


def problems(docs, languages, glossary):
    """Yield every missing or stale translation, unresolved link or image, and bold label the app does not have."""
    for base_page, lang in stale_pages(docs, languages):
        target = target_path(base_page, lang)
        yield f"{target}: {'records another version of' if (docs / target).is_file() else 'missing, the translation of'} {base_page}"
    for lang in (BASE, *languages):
        for page in sorted(path.relative_to(docs) for path in (docs / lang).rglob("*.mdx")):
            text = (docs / page).read_text(encoding="utf-8")
            body = FENCE.sub("", text)
            yield from (f"{page}: {reason}" for reason in (unresolved(docs, page, reference) for reference in REFERENCE.findall(body)) if reason)
            yield from (f"{page}: **{label}** is not a UI label of the app in {lang}" for label in dict.fromkeys(BOLD.findall(body)) if not glossary.has(label, lang))


def run(docs, languages, translator, glossary):
    """Translate every stale page and return the pages that were refused."""
    refused = []
    for base_page, lang in stale_pages(docs, languages):
        try:
            translation = translate_page(base_page, (docs / base_page).read_text(encoding="utf-8"), lang, glossary, translator)
        except PageRefused as error:
            refused.append(str(error))
            continue
        target = docs / target_path(base_page, lang)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(translation, encoding="utf-8")
        print(f"translated {base_page} -> {target.relative_to(docs)}")
    return refused


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("languages", nargs="*", metavar="LANG", help=f"the languages to bring up to date, of {', '.join(LANGUAGES)}; all by default")
    parser.add_argument("--check", action="store_true", help="translate nothing; list missing and stale translations, unresolved links and images, and unknown UI labels, and fail on any")
    parser.add_argument("--docs", type=Path, default=DOCS)
    args = parser.parse_args()
    unknown = sorted(set(args.languages) - set(LANGUAGES))
    if unknown:
        parser.error(f"unknown language {', '.join(unknown)}; choose from {', '.join(LANGUAGES)}")
    languages = args.languages or list(LANGUAGES)
    glossary = Glossary(args.docs / ".translations" / "glossary.json")
    if args.check:
        found = list(problems(args.docs, languages, glossary))
        print("\n".join(found) or "every translation is current and every link, image and UI label resolves")
        sys.exit(1 if found else 0)
    refused = run(args.docs, languages, ClaudeTranslator(), glossary)
    if refused:
        sys.exit("refused, not written:\n" + "\n".join(refused))


if __name__ == "__main__":
    main()
