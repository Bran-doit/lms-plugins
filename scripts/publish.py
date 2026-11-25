"""Build deterministic LMS packages; publish immutable versions and a shared index."""
import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def api(path, method="GET", data=None, binary=False):
    url = path if path.startswith("https://") else "https://api.github.com/" + path
    headers = {"Authorization": "Bearer " + os.environ["GH_TOKEN"],
               "Accept": "application/vnd.github+json",
               "Content-Type": "application/octet-stream" if binary else "application/json",
               "User-Agent": "lms-plugin-publisher"}
    body = data if binary else (json.dumps(data).encode() if data is not None else None)
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return json.load(response) if response.status != 204 else None
    except urllib.error.HTTPError as error:
        if error.code == 404 and method == "GET":
            return None
        raise


def upload(release, path):
    url = release["upload_url"].split("{")[0]
    return api(url + "?" + urllib.parse.urlencode({"name": path.name}),
               "POST", path.read_bytes(), binary=True)


def build(repository):
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    index = ET.Element("extensions")
    details = ET.SubElement(index, "details")
    ET.SubElement(details, "title", lang="EN").text = "Bran-doit LMS Plugins"
    plugins = ET.SubElement(index, "plugins")
    packages = []
    for manifest in sorted((ROOT / "Plugins").glob("*/install.xml")):
        source = manifest.parent
        extension = ET.parse(manifest).getroot()
        name, version = extension.findtext("name"), extension.findtext("version")
        if name != source.name or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name or ""):
            raise ValueError("Invalid plugin name: " + str(name))
        if not re.fullmatch(r"\d+(?:\.\d+)+", version or ""):
            raise ValueError("Expected numeric plugin version")
        archive = output / f"{name}-{version}.zip"
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
            for file in sorted(source.rglob("*")):
                if not file.is_file() or "__pycache__" in file.parts or file.suffix == ".pyc":
                    continue
                if file.is_symlink():
                    raise ValueError("Symlinks are not supported")
                info = zipfile.ZipInfo(file.relative_to(source.parent).as_posix(), (2020, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                zipped.writestr(info, file.read_bytes())
        tag = f"{name}-v{version}"
        target = extension.find("targetApplication")
        attrs = {"name": name, "version": version,
                 "minTarget": target.findtext("minVersion"),
                 "maxTarget": target.findtext("maxVersion")}
        if name in {"LyricTranslator", "DBRepair"}:
            attrs["target"] = "windows"
        entry = ET.SubElement(plugins, "plugin", attrs)
        for child in extension:
            if child.tag in {"title", "desc", "creator"}:
                entry.append(copy.deepcopy(child))
        ET.SubElement(entry, "category").text = extension.findtext("category") or ("radio" if name == "RadioStations" else "information")
        ET.SubElement(entry, "link").text = f"https://github.com/{repository}"
        ET.SubElement(entry, "url").text = f"https://github.com/{repository}/releases/download/{tag}/{archive.name}"
        ET.SubElement(entry, "sha").text = hashlib.sha1(archive.read_bytes()).hexdigest()
        packages.append((tag, archive))
    if not packages:
        raise ValueError("No plugins found")
    ET.indent(index)
    index_path = output / "repo.xml"
    ET.ElementTree(index).write(index_path, encoding="utf-8", xml_declaration=True)
    return packages, index_path


def release_notes(tag):
    name, version = tag.rsplit("-v", 1)
    changelog = ROOT / "Plugins" / name / "CHANGELOG.md"
    if changelog.exists():
        sections = re.split(r"(?m)^## ", changelog.read_text(encoding="utf-8"))
        for section in sections[1:]:
            heading, _, body = section.partition("\n")
            if heading.strip() == version:
                return body.strip()
    return "Automatically built from the plugin source. See the plugin README for requirements."


def publish(repository, packages, index_path):
    prefix = f"repos/{repository}"
    for tag, archive in packages:
        release = api(f"{prefix}/releases/tags/{tag}")
        if release is None:
            release = api(f"{prefix}/releases", "POST", {
                "tag_name": tag, "target_commitish": os.environ["GITHUB_SHA"],
                "name": tag, "draft": True,
                "body": release_notes(tag)})
        assets = api(f"{prefix}/releases/{release['id']}/assets?per_page=100")
        asset = next((a for a in assets if a["name"] == archive.name), None)
        if asset:
            request = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "lms-plugin-publisher"})
            with urllib.request.urlopen(request, timeout=120) as response:
                existing = response.read()
            if existing != archive.read_bytes():
                preserve_released_archive(existing, archive)
                # Documentation-only main updates belong to a future version.
                # Keep the immutable published bytes and their actual checksum.
                tree = ET.parse(index_path)
                name = tag.rsplit("-v", 1)[0]
                for entry in tree.findall("plugins/plugin"):
                    if entry.get("name") == name:
                        entry.find("sha").text = hashlib.sha1(existing).hexdigest()
                tree.write(index_path, encoding="utf-8", xml_declaration=True)
        else:
            upload(release, archive)
        if release["draft"]:
            api(f"{prefix}/releases/{release['id']}", "PATCH", {"draft": False})
        print("Published", tag)
    # Update the index only after every referenced archive is available.
    release = api(f"{prefix}/releases/tags/repository")
    if release is None:
        release = api(f"{prefix}/releases", "POST", {
            "tag_name": "repository", "target_commitish": os.environ["GITHUB_SHA"],
            "name": "LMS plugin repository", "make_latest": "false",
            "body": "Stable LMS index. Add the repo.xml download URL to Additional repositories."})
    assets = api(f"{prefix}/releases/{release['id']}/assets?per_page=100")
    for asset in assets:
        if asset["name"] == index_path.name:
            api(f"{prefix}/releases/assets/{asset['id']}", "DELETE")
    upload(release, index_path)
    print(f"LMS URL: https://github.com/{repository}/releases/download/repository/repo.xml")


def preserve_released_archive(existing, archive):
    """Allow deferred documentation, never silently replace released runtime code."""
    def runtime_files(data):
        with zipfile.ZipFile(io.BytesIO(data)) as zipped:
            result = {}
            for name in zipped.namelist():
                if name.endswith("/"):
                    continue
                path = Path(name)
                if path.suffix.lower() == ".md" or path.name == "README.txt":
                    continue
                content = zipped.read(name)
                if path.suffix.lower() in {".py", ".pm", ".pl", ".ps1", ".js", ".html", ".css", ".xml", ".txt", ".json", ".svg"} or path.name in {"LICENSE", "NOTICE", "COPYING"}:
                    content = content.replace(b"\r\n", b"\n")
                result[name] = content
            return result
    if runtime_files(existing) != runtime_files(archive.read_bytes()):
        raise ValueError(f"{archive.name} already exists with different runtime content. Increase install.xml version.")
    archive.write_bytes(existing)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    repository = os.environ.get("GITHUB_REPOSITORY", "Bran-doit/lms-plugins")
    packages, index_path = build(repository)
    if args.publish:
        publish(repository, packages, index_path)
    else:
        print(index_path)
