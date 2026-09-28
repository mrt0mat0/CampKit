"""Tests for scripts/release.py. Run from the repo root: python3 tests/test_release.py"""
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True   # no __pycache__, which would block a release
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
import release  # noqa: E402


class UploadFormTest(unittest.TestCase):
    def test_metadata_is_sent_verbatim(self):
        # A ';' in the changelog made curl -F truncate the metadata (HTTP 400 on 1.2.2).
        form = release.upload_form('{"changelog": "a; b"}', "/tmp/x.zip")
        self.assertEqual(form[0], "--form-string")
        self.assertEqual(form[1], 'metadata={"changelog": "a; b"}')
        self.assertEqual(form[2:], ("-F", "file=@/tmp/x.zip"))


class RedactTest(unittest.TestCase):
    def test_token_hidden(self):
        self.assertEqual(release.redact("X-Api-Token: abc-123 failed", "abc-123"), "X-Api-Token: <token> failed")

    def test_failure_message_hides_token(self):
        with self.assertRaises(SystemExit) as caught:
            release.run("sh", "-c", "echo 'bad request' ; exit 1", "abc-123", capture=True, secret="abc-123")
        message = str(caught.exception.code)
        self.assertNotIn("abc-123", message)
        self.assertIn("bad request", message)


class TocTest(unittest.TestCase):
    def test_toc_fields(self):
        toc = "## Version: 1.2\n## X-Curse-Project-ID: 42\n\nA.lua\nLocales/deDE.lua\n"
        self.assertEqual(release.toc_field(toc, "X-Curse-Project-ID"), "42")
        self.assertEqual(release.toc_files(toc), ["A.lua", "Locales/deDE.lua"])


if __name__ == "__main__":
    unittest.main()
