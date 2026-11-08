"""Proves scripts/build-glossary.py collects every app label in nl, en, de, pl and ro."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent
SCRIPT = DOCS / "scripts" / "build-glossary.py"
WORKSPACE = DOCS.parent
LANGUAGES = ("nl", "en", "de", "pl", "ro")


def build(workspace, out):
    """Run the glossary script on a workspace and return its result and glossary."""
    result = subprocess.run([sys.executable, str(SCRIPT), "--workspace", str(workspace), "--out", str(out)], capture_output=True, text=True)
    return result, json.loads(out.read_text()) if out.exists() else None


def write(root, path, content):
    """Write a label file below a workspace."""
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(content, ensure_ascii=False))


class GlossaryFromLabelFilesTest(unittest.TestCase):
    """Each layout of the app's label files ends up in the glossary under its file and key."""

    def test_every_layout_gives_its_labels_in_five_languages(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for lang in LANGUAGES:
                write(root, f"mytimeflow/resources/js/i18n/languages/{lang}.json", {"navigation": {"general": f"general-{lang}"}})
                write(root, f"mytimeflow/resources/js/i18n/languages/capability-configuration/{lang}.json", {"title": f"capability-{lang}"})
                write(root, f"mytimeflow/lang/{lang}/menu.json", {"customers": {"label": f"customers-{lang}"}})
                write(root, f"platform/resources/js/i18n/languages/{lang}.json", {"save": f"save-{lang}"})
                write(root, f"platform/lang/{lang}.json", {"30 Days": f"30-{lang}"})
                write(root, f"platform/lang/{lang}/app.json", {"name": f"app-{lang}"})
                write(root, f"shared.js/src/i18n/languages/{lang}.json", {"components": {"form": {"select_date": f"date-{lang}"}}})
            result, glossary = build(root, root / "out" / "glossary.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(glossary["languages"], list(LANGUAGES))
        expected = {
            "mytimeflow/resources/js/i18n/languages/{lang}.json#navigation.general": "general",
            "mytimeflow/resources/js/i18n/languages/capability-configuration/{lang}.json#title": "capability",
            "mytimeflow/lang/{lang}/menu.json#customers.label": "customers",
            "platform/resources/js/i18n/languages/{lang}.json#save": "save",
            "platform/lang/{lang}.json#30 Days": "30",
            "platform/lang/{lang}/app.json#name": "app",
            "shared.js/src/i18n/languages/{lang}.json#components.form.select_date": "date",
        }
        self.assertEqual(set(glossary["labels"]), set(expected))
        for key, text in expected.items():
            self.assertEqual(glossary["labels"][key], {lang: f"{text}-{lang}" for lang in LANGUAGES}, key)

    def test_a_label_a_language_lacks_is_left_out_and_counted(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for lang in LANGUAGES:
                labels = {"save": f"save-{lang}"} if lang == "ro" else {"save": f"save-{lang}", "cancel": f"cancel-{lang}"}
                write(root, f"shared.js/src/i18n/languages/{lang}.json", labels)
            result, glossary = build(root, root / "glossary.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ro", glossary["labels"]["shared.js/src/i18n/languages/{lang}.json#cancel"])
        self.assertIn("'ro': 1", result.stdout)

    def test_no_label_files_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            result, glossary = build(Path(folder), Path(folder) / "glossary.json")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(glossary)


@unittest.skipUnless((WORKSPACE / "mytimeflow").is_dir(), "the app repositories are not next to the docs")
class CommittedGlossaryTest(unittest.TestCase):
    """The committed glossary is what the script builds from the app's current label files."""

    def test_committed_glossary_is_current(self):
        with tempfile.TemporaryDirectory() as folder:
            result, glossary = build(WORKSPACE, Path(folder) / "glossary.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        committed = json.loads((DOCS / ".translations" / "glossary.json").read_text())
        self.assertEqual(committed, glossary, "run scripts/build-glossary.py and commit .translations/glossary.json")
        self.assertEqual(glossary["labels"]["mytimeflow/resources/js/i18n/languages/{lang}.json#navigation.settings.organization.general"]["nl"], "Algemeen")
        self.assertTrue(all(set(texts) == set(LANGUAGES) for texts in glossary["labels"].values()))


if __name__ == "__main__":
    unittest.main()
