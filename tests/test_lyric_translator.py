import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

HELPER = Path(__file__).resolve().parents[1] / "Plugins" / "LyricTranslator" / "helper"
sys.path.insert(0, str(HELPER))
import worker
import bootstrap
from common import route, TranslationError


class LyricsTests(unittest.TestCase):
    def test_timestamps_duplicates_and_blank_lines(self):
        calls = []
        def translate(text):
            calls.append(text)
            return {"Hello": "Hallo", "Good night": "Gute Nacht"}[text]
        timed, plain = worker.translate_lines("[ar:Example]\r\n[00:01.20][00:04.50]Hello\r\n\r\n[01:02:03,40]Good night\n[00:08.00]Hello\n", translate)
        self.assertEqual(timed, "[ar:Example]\n[00:01.20][00:04.50]Hallo\n\n[01:02:03,40]Gute Nacht\n[00:08.00]Hallo\n")
        self.assertEqual(plain, "Hallo\n\nGute Nacht\nHallo\n")
        self.assertEqual(calls, ["Hello", "Good night"])

    def test_input_limits_and_empty_output(self):
        for bad in ("", " ", "a" * 60001, "a\n" * 1201):
            with self.assertRaises(ValueError):
                worker.translate_lines(bad, lambda text: text)
        with self.assertRaises(ValueError):
            worker.translate_lines("Hello", lambda text: "")

    def test_preserve_unicode_and_section_labels(self):
        timed, plain = worker.translate_lines("[Chorus]\nHello", lambda text: {"[Chorus]":"[Refrain]", "Hello":"Grüße"}[text])
        self.assertEqual(plain, "[Refrain]\nGrüße")
        self.assertEqual(timed, plain)

    def test_persistent_cache_content_and_model_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker.write_json(root / "ready.json", {"model_sha256":"model-A"})
            calls = []
            class Engine:
                def __init__(self, path):
                    calls.append("load")
                def translate(self, text):
                    return "Hallo"
            first = worker.run(root, {"text":"Hello"}, Engine)
            self.assertFalse(first["cached"])
            self.assertTrue(worker.run(root, {"text":"Hello"}, Engine)["cached"])
            self.assertEqual(calls, ["load"])
            worker.run(root, {"text":"Different text"}, Engine)
            worker.write_json(root / "ready.json", {"model_sha256":"model-B"})
            worker.run(root, {"text":"Hello"}, Engine)
            self.assertEqual(len(calls), 3)

    def test_corrupt_cache_is_rebuilt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worker.write_json(root / "ready.json", {"model_sha256":"m"})
            key = worker.cache_key("Hello", "en:de:m")
            (root / "cache").mkdir()
            (root / "cache" / (key + ".json")).write_text("broken")
            class Engine:
                def __init__(self, path): pass
                def translate(self, text): return "Hallo"
            self.assertEqual(worker.run(root, {"text":"Hello"}, Engine)["lyrics"], "Hallo")

    def test_language_contract(self):
        with self.assertRaises(ValueError):
            worker.run(Path("."), {"source":"xx", "text":"Bonjour"})

    def test_zip_traversal_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("../outside.txt", "bad")
            with self.assertRaises(ValueError):
                bootstrap.safe_extract(archive, root / "target")
            self.assertFalse((root / "outside.txt").exists())

    def test_download_hash_mismatch(self):
        from unittest.mock import patch
        import io
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / "download.zip"
            with patch("urllib.request.urlopen", return_value=io.BytesIO(b"invalid")):
                with self.assertRaises(ValueError):
                    bootstrap.download({"url":"https://example.org/file", "sha256":"0"*64, "filename":"file"}, dest)
            self.assertFalse(dest.exists())

    def test_network_block(self):
        with self.assertRaises(TranslationError):
            worker.deny_network()

    def test_network_block_in_fresh_process(self):
        import subprocess
        code = f"import sys; sys.path.insert(0, {str(HELPER)!r}); import worker; worker.disable_network(); import ssl, socket; socket.create_connection(('127.0.0.1', 9))"
        result = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("network_blocked", result.stderr)
        self.assertNotIn("TypeError", result.stderr)

    def test_all_supported_routes(self):
        languages=worker.catalog()['languages']
        self.assertEqual(len(languages),8)
        for source in languages:
            for target in languages:
                if source != target:
                    self.assertLessEqual(len(route(source,target)),2)
        with self.assertRaises(TranslationError): route('de','de')
        with self.assertRaises(TranslationError): route('../en','de')

    def test_auto_detection_and_unchanged_target(self):
        text='The sun shines over the hills today and we are walking home together in the evening.'
        self.assertEqual(worker.detect_language(text)[0],'en')
        german='Heute scheint die Sonne über den Hügeln und wir gehen am Abend gemeinsam nach Hause.'
        self.assertEqual(worker.detect_language(german)[0],'de')
        french='Le soleil brille au-dessus des collines et nous rentrons ensemble à la maison ce soir.'
        self.assertEqual(worker.detect_language(french)[0],'fr')
        result=worker.run(Path('.'),{'source':'auto','target':'de','text':german})
        self.assertTrue(result['unchanged'])
        self.assertEqual(result['source'],'de')

    def test_auto_abstains_and_reports_missing_models(self):
        from unittest.mock import patch
        with self.assertRaises(TranslationError): worker.detect_language('Oh yeah!')
        text='A sufficiently long original line with more than eight words to test this path.'
        with tempfile.TemporaryDirectory() as directory, patch('worker.detect_language',return_value=('fr',0.99)):
            result=worker.run(Path(directory),{'source':'auto','target':'de','text':text})
        self.assertEqual(result['error_code'],'need_setup')
        self.assertEqual(result['source'],'fr')
        with patch('worker.detect_language',return_value=('ja',0.99)):
            result=worker.run(Path('.'),{'source':'auto','target':'de','text':text})
        self.assertEqual(result['error_code'],'unsupported_language')

    def test_mixed_language_abstention(self):
        class Identifier:
            def classify(self,text):
                return ('fr',0.99) if text.startswith('French') else ('en',0.99)
        text='English ' + 'a '*116 + 'French ' + 'b '*120
        with self.assertRaises(TranslationError): worker.detect_language(text,Identifier())

    def test_pivot_order_and_language_cache_isolation(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for key in ('fr-en','en-de','en-es'):
                worker.write_json(root/'models'/key/'ready.json',{'model_sha256':key})
            calls=[]
            class Engine:
                def __init__(self,path): self.direction=path.name
                def translate(self,text):
                    calls.append((self.direction,text))
                    return text+'-'+self.direction
            a=worker.run(root,{'source':'fr','target':'de','text':'Bonjour'},Engine)
            b=worker.run(root,{'source':'fr','target':'es','text':'Bonjour'},Engine)
            self.assertEqual(a['plain'],'Bonjour-fr-en-en-de')
            self.assertEqual(b['plain'],'Bonjour-fr-en-en-es')
            self.assertNotEqual(a['key'],b['key'])
            self.assertEqual(a['via'],'en')


if __name__ == "__main__":
    unittest.main()
