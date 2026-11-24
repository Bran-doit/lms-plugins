"""Offline file-based worker. No HTTP listener, shell commands or cloud fallback."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys
import time
from common import TranslationError, route, model_path, model_hash, catalog

ENGINE_REVISION = "multilingual-0.2"
MAX_TEXT = 60000
MAX_LINES = 1200
STAMP = re.compile(r"^(?:\[(?:\d+:)?\d+:\d+(?:[.,]\d+)?\])+")
META = re.compile(r"^\[(?:ar|al|ti|au|by|offset|re|ve|length):", re.I)


def write_json(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temporary, path)


def deny_network(*args, **kwargs):
    raise TranslationError("network_blocked")


def disable_network():
    # Keep socket.socket a class: replacing it with a function breaks ssl imports.
    def audit(event, args):
        if event in {"socket.__new__", "socket.connect", "socket.sendto", "socket.getaddrinfo", "socket.gethostbyname"}:
            deny_network()
    sys.addaudithook(audit)


def cache_key(text: str, identity: str) -> str:
    return hashlib.sha256((ENGINE_REVISION + "\0" + identity + "\0" + text).encode()).hexdigest()


def translate_lines(text: str, translate):
    """Keep every LRC prefix, blank line and metadata line in its original position."""
    if not isinstance(text, str) or not text.strip():
        raise TranslationError("invalid_text")
    if len(text) > MAX_TEXT or len(text.splitlines()) > MAX_LINES:
        raise TranslationError("invalid_text")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    output, plain, memo = [], [], {}
    for line in text.split("\n"):
        if META.match(line):
            output.append(line)
            continue
        stamp = STAMP.match(line)
        prefix = stamp.group() if stamp else ""
        words = line[len(prefix):]
        if not words.strip():
            result = words
        else:
            words = words.strip()
            if words not in memo:
                memo[words] = translate(words)
                if not isinstance(memo[words], str) or not memo[words].strip():
                    raise TranslationError("empty_translation")
            result = memo[words]
        output.append(prefix + result)
        plain.append(result)
    return "\n".join(output), "\n".join(plain)


def detect_language(text, identifier=None):
    # Remove timing tags/section headers and duplicate chorus lines before detection.
    lines = list(dict.fromkeys(STAMP.sub("", line).strip() for line in text.splitlines()
                              if not META.match(line) and not re.fullmatch(r"\s*\[[^\]]+\]\s*", line)))
    clean = "\n".join(line for line in lines if line)
    if sum(c.isalpha() for c in clean) < 50 or len(clean.split()) < 8:
        raise TranslationError("uncertain_language")
    if identifier is None:
        from py3langid.langid import LanguageIdentifier, MODEL_FILE
        identifier = LanguageIdentifier.from_model_file(MODEL_FILE, norm_probs=True)
    language, confidence = identifier.classify(clean)
    if float(confidence) < 0.85 or language in {"und", "zxx"}:
        raise TranslationError("uncertain_language")
    # A second substantial language is a reason to abstain, not to force a guess.
    votes = {}
    chunks = [clean[i:i+240] for i in range(0, len(clean), 240)]
    for chunk in chunks:
        weight = sum(c.isalpha() for c in chunk)
        if weight < 80:
            continue
        code, score = identifier.classify(chunk)
        if float(score) >= 0.9:
            votes[code] = votes.get(code, 0) + weight
    total = sum(votes.values())
    if total and sum(weight for code, weight in votes.items() if code != language) / total > 0.25:
        raise TranslationError("uncertain_language")
    return str(language), float(confidence)


class Engine:
    def __init__(self, model: Path):
        import ctranslate2
        import sentencepiece
        self.tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(model / "sentencepiece.model"))
        self.translator = ctranslate2.Translator(str(model / "model"), device="cpu", compute_type="int8", inter_threads=1, intra_threads=2)
        metadata = json.loads((model / "metadata.json").read_text(encoding="utf-8"))
        self.target_prefix = metadata.get("target_prefix", "")

    def translate(self, text: str) -> str:
        tokens = self.tokenizer.encode(text, out_type=str)
        if len(tokens) > 450:
            raise TranslationError("line_too_long")
        prefix = [[self.target_prefix]] if self.target_prefix else None
        result = self.translator.translate_batch([tokens], target_prefix=prefix, beam_size=4, max_input_length=0, max_decoding_length=1024)[0]
        if len(result.hypotheses[0]) >= 1024:
            raise TranslationError("output_too_long")
        output = result.hypotheses[0]
        if self.target_prefix and output and output[0] == self.target_prefix:
            output = output[1:]
        return self.tokenizer.decode(output).replace("▁", " ").strip()


def run(root: Path, request: dict, engine_factory=Engine):
    source, target = request.get("source", "en"), request.get("target", "de")
    text = request.get("text")
    if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT or len(text.splitlines()) > MAX_LINES:
        raise TranslationError("invalid_text")
    detection = {}
    if source == 'auto':
        source, confidence = detect_language(text)
        detection = dict(detected=True, confidence=confidence)
        if source not in catalog()["languages"]:
            return dict(state="error",error_code="unsupported_language",source=source,target=target,**detection)
        if source == target:
            timed, plain = translate_lines(text, lambda line: line)
            return dict(state="ok",lyrics=timed,plain=plain,source=source,target=target,unchanged=True,cached=False,**detection)
    keys = route(source, target)
    try:
        identity = source + ":" + target + ":" + ":".join(model_hash(root, key) for key in keys)
    except (TranslationError, OSError, KeyError):
        return dict(state="error",error_code="need_setup",source=source,target=target,**detection)
    key = cache_key(text, identity)
    cached = root / "cache" / (key + ".json")
    if cached.is_file():
        try:
            result = json.loads(cached.read_text(encoding="utf-8"))
            if result.get("key") == key and result.get("state") == "ok" and isinstance(result.get("lyrics"), str) and isinstance(result.get("plain"), str):
                return dict(result, cached=True, **detection)
        except (ValueError, OSError):
            pass
    engines = [engine_factory(model_path(root, key)) for key in keys]
    def translate(text):
        for engine in engines:
            text = engine.translate(text)
        return text
    timed, plain = translate_lines(text, translate)
    result = dict(state="ok", key=key, lyrics=timed, plain=plain, source=source, target=target, via="en" if len(keys)>1 else "", cached=False)
    write_json(cached, result)
    # Bound retained lyrics; never touch music files or MAI's original cache.
    files = sorted((root / "cache").glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in files[1000:]:
        old.unlink(missing_ok=True)
    return dict(result, **detection)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--response", type=Path, required=True)
    args = parser.parse_args()
    # Also protects against accidental online behavior in dependencies.
    disable_network()
    started = time.monotonic()
    try:
        if args.request.stat().st_size > 400000:
            raise TranslationError("invalid_text")
        result = run(args.root, json.loads(args.request.read_text(encoding="utf-8")))
    except Exception as error:
        result = dict(state="error", error_code=getattr(error,"code","translation_error"), detail="" if isinstance(error,TranslationError) else str(error))
    result["seconds"] = round(time.monotonic() - started, 3)
    write_json(args.response, result)
    return 0 if result["state"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
