import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


class TranslationError(ValueError):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


def catalog():
    return json.loads((HERE / "downloads.json").read_text(encoding="utf-8"))


def route(source, target, manifest=None):
    manifest = manifest or catalog()
    if source not in manifest["languages"] or target not in manifest["languages"]:
        raise TranslationError("unsupported_pair")
    if source == target:
        raise TranslationError("same_language")
    direct = source + "-" + target
    keys = [direct] if direct in manifest["models"] else [source + "-en", "en-" + target]
    if any(key not in manifest["models"] for key in keys):
        raise TranslationError("unsupported_pair")
    return keys


def model_path(root, key):
    """Read old 0.1 installation in place; do not redownload German on upgrade."""
    path = root / "models" / key
    if (path / "ready.json").is_file():
        return path
    if key == "en-de" and (root / "ready.json").is_file():
        return root / "model"
    raise TranslationError("need_setup")


def model_hash(root, key):
    path = model_path(root, key)
    marker = root / "ready.json" if path == root / "model" else path / "ready.json"
    return json.loads(marker.read_text(encoding="utf-8"))["model_sha256"]
