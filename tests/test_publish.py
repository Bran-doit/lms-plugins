import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).resolve().parents[1] / "scripts/publish.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublicationTests(unittest.TestCase):
    def test_existing_archive_preserved_for_deferred_docs_only(self):
        import io
        def package(code, readme):
            target = io.BytesIO()
            with zipfile.ZipFile(target, 'w') as archive:
                archive.writestr('Example/Plugin.pm', code)
                archive.writestr('Example/README.md', readme)
            return target.getvalue()
        original = package('original\n', 'old docs')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Example.zip'
            path.write_bytes(package('original\r\n', 'new docs'))
            publisher.preserve_released_archive(original, path)
            self.assertEqual(path.read_bytes(), original)
            changed = package('changed code', 'new docs')
            path.write_bytes(changed)
            with self.assertRaises(ValueError):
                publisher.preserve_released_archive(original, path)
            self.assertEqual(path.read_bytes(), changed)

    def test_release_notes_select_requested_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plugin = root / "Plugins" / "Example"
            plugin.mkdir(parents=True)
            (plugin / "CHANGELOG.md").write_text("# Changelog\n\n## 1.2.3\n\nNew release.\n\n## 1.2.2\n\nOlder release.\n", encoding="utf-8")
            with patch.object(publisher, "ROOT", root):
                self.assertEqual(publisher.release_notes("Example-v1.2.3"), "New release.")
                self.assertEqual(publisher.release_notes("Example-v1.2.2"), "Older release.")
                self.assertIn("README", publisher.release_notes("Example-v1.0.0"))

    def test_archive_and_index_are_consistent_and_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plugin = root / "Plugins" / "Example"
            plugin.mkdir(parents=True)
            (plugin / "install.xml").write_text('<extension><name>Example</name><version>1.2.3</version><targetApplication><minVersion>8.0</minVersion><maxVersion>9.*</maxVersion></targetApplication></extension>')
            (plugin / "Plugin.pm").write_text("package Plugins::Example::Plugin; 1;")
            (plugin / "__pycache__").mkdir()
            (plugin / "__pycache__" / "ignored.pyc").write_bytes(b"cache")
            with patch.object(publisher, "ROOT", root):
                packages, index = publisher.build("example/plugins")
                archive = packages[0][1]
                first = archive.read_bytes()
                entry = ET.parse(index).find("plugins/plugin")
                self.assertEqual(entry.findtext("sha"), hashlib.sha1(first).hexdigest())
                self.assertIn("Example-v1.2.3/Example-1.2.3.zip", entry.findtext("url"))
                with zipfile.ZipFile(archive) as zipped:
                    self.assertEqual(set(zipped.namelist()), {"Example/install.xml", "Example/Plugin.pm"})
                publisher.build("example/plugins")
                self.assertEqual(first, archive.read_bytes())

    def test_empty_repository_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(publisher, "ROOT", Path(directory)):
                with self.assertRaises(ValueError):
                    publisher.build("example/plugins")
