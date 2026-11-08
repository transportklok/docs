"""Proves scripts/translate_docs.py translates new and changed Dutch pages and keeps their structure, with a fake model."""

import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "translate_docs.py"
spec = importlib.util.spec_from_file_location("translate_docs", SCRIPT)
translate_docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(translate_docs)

PAGE = """---
title: "Voertuigen"
description: "Zo beheert u uw voertuigen."
icon: "truck"
---

## Waar deze pagina voor is

U beheert hier uw voertuigen. Lees eerst [Aan de slag](/nl/getting-started).

![Overzicht](/images/captures/management-vehicles.png)

<Card title="Tijdregistraties" icon="arrow-right" href="/nl/management/time-registrations">
  Bekijk de tijdregistraties.
</Card>

## Zo gebruikt u deze pagina

1. Klik op **Opslaan**.
2. Vul `kenteken` in.

```bash
curl https://app.transportklok.nl
```
"""
GLOSSARY = {"languages": ["nl", "en", "de", "pl", "ro"], "labels": {
    "mytimeflow/resources/js/i18n/languages/{lang}.json#actions.save": {"nl": "Opslaan", "en": "Save", "de": "Speichern", "pl": "Zapisz", "ro": "Salvează"},
}}


class FakeModel:
    """Translates by writing the glossary's labels and marking the prose, and can break the page on purpose."""

    def __init__(self, breaks=0, uses_glossary=True):
        self.calls, self.breaks, self.uses_glossary = 0, breaks, uses_glossary

    def __call__(self, request):
        self.calls += 1
        page = request.split("\nPage:\n", 1)[1].split("\n\nYour previous translation was refused", 1)[0]
        if self.uses_glossary:
            for dutch, target in re.findall(r"^- (.+) → (.+)$", request, re.MULTILINE):
                page = page.replace(f"**{dutch}**", f"**{target.split(' or ')[0]}**")
        page = page.replace("U beheert", "[translated] U beheert").replace('title: "Voertuigen"', 'title: "[translated] Voertuigen"')
        if self.calls <= self.breaks:
            page = page.replace("](/", "](/broken/")
        return f"```mdx\n{page}```"


def docs_with_base_page(test):
    """Return a temporary docs folder holding one Dutch page and the glossary."""
    folder = tempfile.TemporaryDirectory()
    test.addCleanup(folder.cleanup)
    docs = Path(folder.name)
    (docs / "nl" / "management").mkdir(parents=True)
    (docs / "nl" / "management" / "vehicles.mdx").write_text(PAGE)
    (docs / ".translations").mkdir()
    (docs / ".translations" / "glossary.json").write_text(json.dumps(GLOSSARY, ensure_ascii=False))
    return docs


class TranslateDocsTest(unittest.TestCase):
    """Translations of the Dutch base pages."""

    def setUp(self):
        self.docs = docs_with_base_page(self)
        self.glossary = translate_docs.Glossary(self.docs / ".translations" / "glossary.json")

    def translate(self, model):
        """Bring every language up to date with a model and return what was refused."""
        return translate_docs.run(self.docs, list(translate_docs.LANGUAGES), model, self.glossary)

    def test_a_new_page_is_translated_into_every_language_with_its_structure_kept(self):
        self.assertEqual(self.translate(FakeModel()), [])
        base_hash = translate_docs.page_hash(PAGE)
        for lang, save in (("en", "Save"), ("de", "Speichern"), ("pl", "Zapisz"), ("ro", "Salvează")):
            with self.subTest(lang=lang):
                text = (self.docs / lang / "management" / "vehicles.mdx").read_text()
                self.assertTrue(text.startswith('---\ntitle: "[translated] Voertuigen"\n'))
                self.assertIn('icon: "truck"\n---\n{/* translated-from: nl/management/vehicles.mdx sha256:' + base_hash + " */}\n", text)
                self.assertIn(f"[Aan de slag](/{lang}/getting-started)", text)
                self.assertIn(f'href="/{lang}/management/time-registrations"', text)
                self.assertIn("](/images/captures/management-vehicles.png)", text)
                self.assertIn("```bash\ncurl https://app.transportklok.nl\n```", text)
                self.assertIn("`kenteken`", text)
                self.assertIn(f"**{save}**", text)
                self.assertNotIn("```mdx", text)

    def test_an_unchanged_page_is_not_translated_again_and_a_changed_one_is(self):
        self.translate(FakeModel())
        before = (self.docs / "de" / "management" / "vehicles.mdx").read_text()
        model = FakeModel()
        self.translate(model)
        self.assertEqual(model.calls, 0)
        self.assertEqual((self.docs / "de" / "management" / "vehicles.mdx").read_text(), before)
        (self.docs / "nl" / "management" / "vehicles.mdx").write_text(PAGE.replace("uw voertuigen.", "al uw voertuigen."))
        self.assertEqual(list(translate_docs.stale_pages(self.docs, ["de"])), [(Path("nl/management/vehicles.mdx"), "de")])
        self.translate(model)
        self.assertEqual(model.calls, 4)
        self.assertIn("al uw voertuigen", (self.docs / "de" / "management" / "vehicles.mdx").read_text())

    def test_a_translation_that_breaks_the_page_is_retried_once(self):
        model = FakeModel(breaks=1)
        self.assertEqual(translate_docs.run(self.docs, ["en"], model, self.glossary), [])
        self.assertEqual(model.calls, 2)
        self.assertIn("](/en/getting-started)", (self.docs / "en" / "management" / "vehicles.mdx").read_text())

    def test_a_translation_still_broken_after_the_retry_is_refused_and_not_written(self):
        refused = translate_docs.run(self.docs, ["en"], FakeModel(breaks=2), self.glossary)
        self.assertEqual(len(refused), 1)
        self.assertIn("en/management/vehicles.mdx: link targets changed", refused[0])
        self.assertFalse((self.docs / "en" / "management" / "vehicles.mdx").exists())

    def test_a_ui_label_not_written_as_the_app_shows_it_is_refused(self):
        refused = translate_docs.run(self.docs, ["de"], FakeModel(uses_glossary=False), self.glossary)
        self.assertEqual(len(refused), 1)
        self.assertIn("bold label 'Opslaan' is not written as 'Speichern'", refused[0])



class TranslationCheckTest(unittest.TestCase):
    """translate_docs.py --check, the docs CI step, fails on each way the languages drift apart."""

    def setUp(self):
        self.docs = docs_with_base_page(self)
        (self.docs / "nl" / "getting-started.mdx").write_text('---\ntitle: "Aan de slag"\n---\n\nWelkom.\n')
        (self.docs / "nl" / "management" / "time-registrations.mdx").write_text('---\ntitle: "Tijdregistraties"\n---\n\nOverzicht.\n')
        (self.docs / "images" / "captures").mkdir(parents=True)
        (self.docs / "images" / "captures" / "management-vehicles.png").write_bytes(b"png")
        glossary = translate_docs.Glossary(self.docs / ".translations" / "glossary.json")
        self.assertEqual(translate_docs.run(self.docs, list(translate_docs.LANGUAGES), FakeModel(), glossary), [])

    def check(self, *languages):
        """Run the check as CI does and return its result."""
        return subprocess.run([sys.executable, str(SCRIPT), "--check", "--docs", str(self.docs), *languages], capture_output=True, text=True)

    def edit(self, page, old, new):
        """Replace text in a page of the docs."""
        path = self.docs / page
        path.write_text(path.read_text().replace(old, new))

    def assertFails(self, line):
        result = self.check()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(line, result.stdout)

    def test_docs_in_step_pass(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout)

    def test_a_page_missing_in_a_language_fails(self):
        (self.docs / "pl" / "management" / "vehicles.mdx").unlink()
        self.assertFails("pl/management/vehicles.mdx: missing, the translation of nl/management/vehicles.mdx")

    def test_a_translation_of_an_older_dutch_page_fails(self):
        self.edit("nl/management/vehicles.mdx", "uw voertuigen.", "al uw voertuigen.")
        self.assertFails("ro/management/vehicles.mdx: records another version of nl/management/vehicles.mdx")

    def test_a_link_to_a_missing_page_fails(self):
        self.edit("de/management/vehicles.mdx", "/de/getting-started", "/de/getting-startet")
        self.assertFails("de/management/vehicles.mdx: /de/getting-startet is not a page")

    def test_a_link_into_another_language_fails(self):
        self.edit("en/management/vehicles.mdx", 'href="/en/management/time-registrations"', 'href="/nl/management/time-registrations"')
        self.assertFails("en/management/vehicles.mdx: /nl/management/time-registrations leaves the en pages")

    def test_a_missing_image_fails(self):
        (self.docs / "images" / "captures" / "management-vehicles.png").unlink()
        self.assertFails("nl/management/vehicles.mdx: /images/captures/management-vehicles.png does not exist")

    def test_a_label_not_in_the_glossary_fails(self):
        self.edit("en/management/vehicles.mdx", "**Save**", "**Store**")
        self.assertFails("en/management/vehicles.mdx: **Store** is not a UI label of the app in en")

    def test_the_docs_pr_workflow_runs_the_check(self):
        workflow = (SCRIPT.parent.parent / ".github" / "workflows" / "docs-pr.yml").read_text()
        self.assertIn("run: python3 scripts/translate_docs.py --check", workflow)

    def test_an_unknown_language_is_refused(self):
        self.assertEqual(self.check("fr").returncode, 2)


if __name__ == "__main__":
    unittest.main()
