#!/usr/bin/env python3
"""Build release assets from a clean Git commit, without executing Android code."""
import argparse
import hashlib
import io
import json
import re
import stat
import subprocess
import tarfile
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath

from validate_release import check_source, check_zip, expected_zip_mode, read_properties


PACKAGE_FILES = {"module.prop", "system.prop", "customize.sh", "service.sh", "uninstall.sh", "update.json"}
PACKAGE_DIRS = {"bin", "common", "webroot", "thermal_profiles"}


def packaged(name):
    return name in PACKAGE_FILES or name.split("/", 1)[0] in PACKAGE_DIRS


def archive_files(data):
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
        for member in archive:
            name = member.name
            if not (packaged(name) or name in {"README.md", "changelog.md"}):
                continue
            if PurePosixPath(name).is_absolute() or any(p in ("", ".", "..") for p in name.split("/")):
                raise ValueError(f"unsafe source path: {name}")
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"release source must be a regular file: {name}")
            files[name] = archive.extractfile(member).read()
    return files


def git_snapshot(source):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(source), *args])
    if git("status", "--porcelain", "--untracked-files=all").strip():
        raise ValueError("release source must be clean and committed; use an isolated worktree")
    revision = git("rev-parse", "HEAD").decode().strip()
    epoch = int(git("show", "-s", "--format=%ct", "HEAD"))
    return archive_files(git("archive", "--format=tar", revision)), revision, epoch


def build_assets(files, output, revision, epoch):
    with tempfile.TemporaryDirectory(prefix="supercharger-package-") as folder:
        snapshot = Path(folder)
        for name, data in files.items():
            if not (packaged(name) or name in {"README.md", "changelog.md"}):
                continue
            if PurePosixPath(name).is_absolute() or any(p in ("", ".", "..") for p in name.split("/")) or "\\" in name or "\x00" in name:
                raise ValueError(f"unsafe source path: {name}")
            path = snapshot / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        errors = check_source(snapshot, "main")
        if errors:
            raise ValueError("\n".join(errors))
        version = read_properties(snapshot / "module.prop")["version"]
        version_code = int(read_properties(snapshot / "module.prop")["versionCode"])
        for name, data in files.items():
            if packaged(name) and name.endswith(".json"):
                json.loads(data)
        changelog = files["changelog.md"].decode("utf-8")
        match = re.search(rf"^## {re.escape(version)}\s*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
        if not match:
            raise ValueError("release notes section missing")
        notes = f"## {version}\n\n" + match.group(1).rstrip() + "\n"

        output = Path(output)
        basename = f"Pixel-9-Series-Supercharger-{version}.zip"
        names = [basename, basename + ".sha256", "update.json", "release-notes.md", "release-manifest.json"]
        if any((output / name).exists() for name in names):
            raise ValueError("release outputs already exist; choose a fresh output directory")
        output.mkdir(parents=True, exist_ok=True)
        date_time = time.gmtime(max(epoch, 315532800))[:6]
        package = snapshot / basename
        entries = []
        with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name in sorted(files):
                if not packaged(name):
                    continue
                data = files[name]
                mode = expected_zip_mode(name, False)
                info = zipfile.ZipInfo(name, date_time=date_time)
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, data, compresslevel=9)
                entries.append({"path": name, "mode": oct(mode), "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        errors = check_zip(package, "main")
        if errors:
            raise ValueError("\n".join(errors))
        content = package.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        (output / basename).write_bytes(content)
        (output / (basename + ".sha256")).write_bytes(f"{digest}  {basename}\n".encode())
        (output / "update.json").write_bytes(files["update.json"])
        (output / "release-notes.md").write_bytes(notes.encode("utf-8"))
        manifest = {"version": version, "versionCode": version_code, "sourceCommit": revision,
                    "sourceCommitTimestamp": epoch, "package": basename, "sha256": digest,
                    "deviceValidation": "not asserted by this build", "files": entries}
        (output / "release-manifest.json").write_bytes((json.dumps(manifest, indent=2) + "\n").encode())
        return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if output.is_relative_to(source):
        parser.error("release output must be outside the source checkout")
    files, revision, epoch = git_snapshot(source)
    manifest = build_assets(files, output, revision, epoch)
    print(json.dumps({"output": str(output), **{k: manifest[k] for k in ("version", "sourceCommit", "package", "sha256")}}, indent=2))


if __name__ == "__main__":
    main()
