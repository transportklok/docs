"""Proves the local mint renders and link-checks a docs site with navigation.languages (fixtures/languages)."""

import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = ROOT / "fixtures" / "languages"
SWITCHER = Path(__file__).resolve().parent / "language_switcher.cjs"
# latest is what CI runs (docs-pr.yml); MINT_VERSIONS=latest,4.2.1011 also proves the lowest version known to work.
MINT_VERSIONS = tuple(os.environ.get("MINT_VERSIONS", "latest").split(","))
PLAYWRIGHT = "playwright-core@1.65.0"
TITLES = {"nl": "Aan de slag", "en": "Getting started"}


def step(text):
    """Log a step with the time, so a run stopped by the test budget shows where it was."""
    print(f"[{time.strftime('%H:%M:%S')}] {text}", file=sys.stderr, flush=True)


def mint(version, cwd, *args, timeout=180):
    """Run the mint CLI of a version in a folder."""
    step(f"mint@{version} {' '.join(args)} in {Path(cwd).name}")
    return subprocess.run(
        ["npx", "--yes", f"mint@{version}", *args],
        cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout,
    )


def free_port():
    """Return a port nothing listens on."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def fetch(url):
    """Return the status and body of a GET within a minute, or None while the server does not answer."""
    result = subprocess.run(["curl", "-s", "-m", "60", "-w", "\n%{http_code}", url], capture_output=True, text=True)
    body, _, status = result.stdout.rpartition("\n")
    return (int(status), body) if result.returncode == 0 and status.isdigit() else None


class MintVersion:
    """Names the mint version the other tests of its version run on, for the log."""

    def test_version(self):
        result = subprocess.run(["npm", "view", f"mint@{self.mint_version}", "version"], capture_output=True, text=True, timeout=120)
        print(f"\nmint@{self.mint_version} resolves to {result.stdout.strip()}")
        self.assertEqual(result.returncode, 0, result.stderr)


class BrokenLinks:
    """mint broken-links checks the pages of every language."""

    def test_fixture_has_no_broken_links(self):
        result = mint(self.mint_version, FIXTURE, "broken-links")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_broken_link_in_a_language_page_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            copy = Path(folder) / "languages"
            shutil.copytree(FIXTURE, copy)
            page = copy / "en" / "getting-started.mdx"
            page.write_text(page.read_text().replace("/en/management/time-registrations", "/en/management/missing-page"))
            result = mint(self.mint_version, copy, "broken-links")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("missing-page", result.stdout + result.stderr)


class DevServer:
    """mint dev serves both languages under their English paths and the switcher moves between them."""

    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        cls.base = f"http://localhost:{cls.port}"
        cls.log = tempfile.NamedTemporaryFile("w+", suffix=".log", delete=False)
        step(f"mint@{cls.mint_version} dev on port {cls.port}")
        cls.server = subprocess.Popen(
            ["npx", "--yes", f"mint@{cls.mint_version}", "dev", "--port", str(cls.port), "--no-open"],
            cwd=FIXTURE, stdin=subprocess.DEVNULL, stdout=cls.log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        deadline = time.time() + 240
        while time.time() < deadline:
            if cls.server.poll() is not None:
                break
            answer = fetch(f"{cls.base}/nl/getting-started")
            if answer and answer[0] == 200:
                step("mint dev serves the fixture")
                return
            time.sleep(3)
        cls.tearDownClass()
        raise AssertionError(f"mint dev did not serve the fixture:\n{Path(cls.log.name).read_text()[-4000:]}")

    @classmethod
    def tearDownClass(cls):
        if cls.server.poll() is None:
            os.killpg(cls.server.pid, signal.SIGTERM)
            try:
                cls.server.wait(timeout=30)
            except subprocess.TimeoutExpired:
                os.killpg(cls.server.pid, signal.SIGKILL)

    def test_each_language_renders_its_pages(self):
        for language, title in TITLES.items():
            for path in ("getting-started", "management/time-registrations"):
                with self.subTest(language=language, path=path):
                    status, body = fetch(f"{self.base}/{language}/{path}")
                    self.assertEqual(status, 200)
            status, body = fetch(f"{self.base}/{language}/getting-started")
            self.assertIn(title, body)

    def test_switcher_changes_language(self):
        with tempfile.TemporaryDirectory() as modules:
            step(f"npm install {PLAYWRIGHT}")
            install = subprocess.run(
                ["npm", "install", "--no-save", "--no-audit", "--no-fund", "--prefix", modules, PLAYWRIGHT],
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(install.returncode, 0, install.stderr)
            step("language switcher in Chrome")
            result = subprocess.run(
                ["node", str(SWITCHER), self.base],
                env={**os.environ, "NODE_PATH": str(Path(modules) / "node_modules")},
                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=120,
            )
        print(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


for _version in MINT_VERSIONS:
    for _check in (MintVersion, BrokenLinks, DevServer):
        _name = f"{_check.__name__}Mint{_version.replace('.', '_').title()}Test"
        globals()[_name] = type(_name, (_check, unittest.TestCase), {"mint_version": _version})


if __name__ == "__main__":
    unittest.main()
