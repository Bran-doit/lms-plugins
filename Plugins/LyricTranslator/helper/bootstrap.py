"""Install locked wheels and an Argos model into a private embedded runtime."""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile

from worker import write_json
from common import route, model_path, model_hash


def download(item, destination):
    if destination.exists() and hashlib.sha256(destination.read_bytes()).hexdigest() == item["sha256"]:
        return
    temporary = destination.with_suffix(".download")
    digest = hashlib.sha256()
    request = urllib.request.Request(item["url"], headers={"User-Agent": "Lyric-Translator/0.2.0"})
    with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != item["sha256"]:
        temporary.unlink(missing_ok=True)
        raise ValueError("Checksum mismatch: " + item["filename"])
    os.replace(temporary, destination)


def safe_extract(archive, target):
    target = target.resolve()
    with zipfile.ZipFile(archive) as package:
        for entry in package.infolist():
            path = (target / entry.filename).resolve()
            if not path.is_relative_to(target) or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Unsafe archive path.")
        package.extractall(target)


def install(root, manifest, source="en", target="de", detected_source=""):
    if source == 'auto':
        effective = detected_source if detected_source in manifest['languages'] else 'en'
        keys = [] if effective == target else route(effective, target, manifest)
    else:
        keys = route(source, target, manifest)
    def status(code, detail=""):
        write_json(root / "setup-status.json", dict(state="running", code=code, detail=detail, source=source, target=target))
    downloads = root / "downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    library = root / "runtime" / "Lib" / "site-packages"
    library.mkdir(parents=True, exist_ok=True)
    # Embedded Python omits a non-existing _pth entry at startup. On a first
    # installation this directory has only just been created by this process.
    sys.path.insert(0, str(library))
    for item in manifest["wheels"]:
        status("engine", item["name"])
        archive = downloads / item["filename"]
        download(item, archive)
        safe_extract(archive, library)
    installed = []
    for key in keys:
        item = manifest["models"][key]
        # Preserve the legacy model and already verified other language models.
        try:
            path = model_path(root, key)
            if model_hash(root, key) == item["sha256"] and (path / "model" / "model.bin").is_file() and (path / "sentencepiece.model").is_file():
                installed.append((key, path, item))
                continue
        except (ValueError, OSError, KeyError):
            pass
        status("model", key)
        archive = downloads / item["filename"]
        download(item, archive)
        staging = root / "model-unpacked" / key
        safe_extract(archive, staging)
        candidates = list(staging.rglob("sentencepiece.model"))
        if len(candidates) != 1 or not (candidates[0].parent / "model" / "model.bin").is_file():
            raise ValueError("Unsupported model layout: " + key)
        metadata = json.loads((candidates[0].parent / "metadata.json").read_text(encoding="utf-8"))
        if metadata["from_code"] != item["source"] or metadata["to_code"] != item["target"]:
            raise ValueError("Model direction mismatch: " + key)
        path = root / "models" / key
        # Invalidate only this model while repairing it; other languages remain installed.
        (path / "ready.json").unlink(missing_ok=True)
        shutil.copytree(candidates[0].parent, path, dirs_exist_ok=True)
        installed.append((key, path, item))
    # Modules were extracted after interpreter startup; discard cached missing paths.
    importlib.invalidate_caches()
    # This smoke test runs without network and must succeed before readiness is published.
    from worker import Engine, disable_network
    disable_network()
    samples = {"en":"The sun shines today.","de":"Die Sonne scheint heute.","es":"El sol brilla hoy.","fr":"Le soleil brille aujourd’hui.","it":"Il sole splende oggi.","pt":"O sol brilha hoje.","nl":"De zon schijnt vandaag.","ru":"Сегодня светит солнце."}
    status("checking")
    from worker import detect_language
    detected, confidence = detect_language("The sun shines over the hills today and we are walking home together in the evening.")
    if detected != 'en':
        raise ValueError("Language detection self-test failed.")
    for key, path, item in installed:
        translated = Engine(path).translate(samples[item["source"]])
        if not translated or translated == samples[item["source"]]:
            raise ValueError("Translation self-test failed: " + key)
        marker = root / "ready.json" if path == root / "model" else path / "ready.json"
        write_json(marker, dict(version=manifest["version"], model_sha256=item["sha256"], sample=translated))
    write_json(root / "runtime-ready.json",dict(version=manifest["version"],detection=True))
    write_json(root / "setup-status.json", dict(state="ready", code="ready", source=source, target=target))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--source", default="en")
    parser.add_argument("--target", default="de")
    parser.add_argument("--detected-source", default="")
    args = parser.parse_args()
    try:
        install(args.root, json.loads(args.manifest.read_text(encoding="utf-8-sig")), args.source, args.target, args.detected_source)
    except Exception as error:
        import traceback
        traceback.print_exc()
        write_json(args.root / "setup-status.json", dict(state="error", code=getattr(error,"code","setup_error"), detail=str(error), source=args.source, target=args.target))
        sys.exit(1)
