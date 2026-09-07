#!/usr/bin/env python3
import argparse
import json
import re
import stat
import sys
import zipfile
from pathlib import Path


RUNTIME_NAMES = {
    ".maintenance.lock.guard",
    ".app_optimization.lock.guard",
    ".maintenance_task.lock.guard",
    ".app_optimization_task.lock.guard",
    "current_profile",
    "thermal_current_profile",
    "thermal_control.env",
    "gpu_policy_state.env",
    "module_status.env",
    "addon_api.env",
    "support_snapshot.txt",
    "debug.log",
    "debug.previous.log",
    "maintenance.log",
    "maintenance_task.log",
    "maintenance_task.env",
    "maintenance_task.pid",
    "app_optimization.log",
    "app_optimization.env",
    "app_optimization.pid",
    "dashboard_updater.pid",
    "action.log",
    "last_action_status.txt",
}

ACTIVE_OVERLAY_PATHS = {
    "system/vendor/etc/thermal_info_config.json",
    "system/vendor/etc/thermal_info_config_lpm.json",
    "system/vendor/etc/thermal_info_config_charge.json",
}

ZIP_BLOCKED_PREFIXES = (
    ".git/",
    ".github/",
    "dist/",
    "docs/",
    "release-check/",
    "scripts/",
)

ZIP_BLOCKED_ROOT = {
    ".gitignore",
    ".gitattributes",
    "README.md",
    "README.txt",
    "LICENSE",
    "changelog.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "AGENTS.md",
    "TODO.md",
}

REQUIRED = {
    "main": [
        "module.prop",
        "system.prop",
        "customize.sh",
        "service.sh",
        "uninstall.sh",
        "update.json",
        "common/repo.json",
        "bin/supercharger_ctl.sh",
        "webroot/index.html",
        "webroot/index.mjs",
        "webroot/kernelsu.js",
        "thermal_profiles/balanced/vendor/etc/thermal_info_config.json",
        "thermal_profiles/balanced/vendor/etc/thermal_info_config_lpm.json",
        "thermal_profiles/gaming/vendor/etc/thermal_info_config.json",
        "thermal_profiles/gaming/vendor/etc/thermal_info_config_lpm.json",
        "thermal_profiles/charge_cool/vendor/etc/thermal_info_config.json",
        "thermal_profiles/charge_cool/vendor/etc/thermal_info_config_lpm.json",
    ],
    "thermal": [
        "module.prop",
        "customize.sh",
        "service.sh",
        "post-fs-data.sh",
        "uninstall.sh",
        "update.json",
        "bin/profile_lib.sh",
        "bin/switch_profile.sh",
        "webroot/index.html",
        "webroot/kernelsu.js",
        "profiles/balanced/vendor/etc/thermal_info_config.json",
        "profiles/balanced/vendor/etc/thermal_info_config_lpm.json",
        "profiles/gaming/vendor/etc/thermal_info_config.json",
        "profiles/gaming/vendor/etc/thermal_info_config_lpm.json",
        "profiles/charge_cool/vendor/etc/thermal_info_config.json",
        "profiles/charge_cool/vendor/etc/thermal_info_config_lpm.json",
    ],
}

ROOT_EXECUTABLE = {
    "customize.sh",
    "service.sh",
    "post-fs-data.sh",
    "uninstall.sh",
}


# Prerelease suffix mirrors the -alpha/-beta/-rc channels derived in release.yml.
VERSION_PATTERN = re.compile(
    r"v(?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)"
    r"(?P<suffix>-[0-9A-Za-z][0-9A-Za-z.-]*)?"
)


def norm(value):
    return str(value).replace("\\", "/").strip("/")


def read_properties(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def check_main_metadata(root):
    errors = []
    module = read_properties(root / "module.prop")
    version = module.get("version", "")
    version_code = module.get("versionCode", "")

    match = VERSION_PATTERN.fullmatch(version)
    version_core = ""
    if not match:
        errors.append(f"invalid module version: {version or '<missing>'}")
    else:
        major, minor, patch = (int(match.group(name)) for name in ("major", "minor", "patch"))
        version_core = f"v{major}.{minor}.{patch}"
        # major*10000 + minor*1000 leaves a single decimal digit for minor, so the
        # encoding stops being injective and monotonic past those bounds.
        if minor >= 10 or patch >= 1000:
            errors.append(
                f"module version {version} cannot be encoded: versionCode "
                f"major*10000 + minor*1000 + patch collides once minor >= 10 or "
                f"patch >= 1000 (v2.10.0 and v3.0.0 both encode to 30000); "
                f"bump the major version instead"
            )
        else:
            expected_code = major * 10000 + minor * 1000 + patch
            if version_code != str(expected_code):
                errors.append(
                    f"module versionCode {version_code or '<missing>'} does not match "
                    f"{version} (expected {expected_code})"
                )

    try:
        update = json.loads((root / "update.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"invalid update.json: {exc}")
        update = {}

    if not isinstance(update, dict):
        errors.append("invalid update.json: expected a JSON object")
        update = {}

    if update.get("version") != version:
        errors.append("update.json version does not match module.prop")
    if str(update.get("versionCode", "")) != version_code:
        errors.append("update.json versionCode does not match module.prop")
    feed = module.get("updateJson", "")
    feed_match = re.fullmatch(r"(https://github\.com/[A-Za-z0-9-]+/[A-Za-z0-9_.-]+)/releases/latest/download/update\.json", feed)
    if not feed_match:
        errors.append("module.prop updateJson must follow the stable GitHub release asset feed")
    else:
        repo_url = feed_match.group(1)
        expected_zip = f"{repo_url}/releases/download/{version}/Pixel-9-Series-Supercharger-{version}.zip"
        if update.get("zipUrl") != expected_zip:
            errors.append("update.json zipUrl must reference this repository's exact versioned module ZIP")
    # The root manager downloads each URL and uses its raw content, so a GitHub
    # release page in `changelog` would be rendered to the user as HTML markup.
    for field, suffix in (("zipUrl", ".zip"), ("changelog", ".md")):
        value = str(update.get(field, ""))
        if version and version not in value:
            errors.append(f"update.json {field} does not reference {version}")
        if not value.endswith(suffix):
            errors.append(
                f"update.json {field} must point at a {suffix} file: {value or '<missing>'}"
            )

    metadata_files = {
        "customize.sh": [f"Build: {version}", f'PROFILE_VERSION="{version}"'],
        "service.sh": [f'PROFILE_VERSION="{version}"'],
    }
    for filename, markers in metadata_files.items():
        text = (root / filename).read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                errors.append(f"{filename} is missing version marker: {marker}")

    readme = (root / "README.md").read_text(encoding="utf-8")
    readme_versions = set(re.findall(r"v\d+\.\d+\.\d+", readme))
    if readme_versions != {version_core}:
        errors.append(
            "README version markers do not match module.prop: "
            + (", ".join(sorted(readme_versions)) or "none found")
        )

    changelog = (root / "changelog.md").read_text(encoding="utf-8")
    first_heading = re.search(r"^##\s+(v\S+)", changelog, re.MULTILINE)
    if not first_heading or first_heading.group(1) != version:
        errors.append(f"changelog latest section does not match {version}")

    return errors


def check_source(root, profile):
    errors = []
    required_paths = REQUIRED[profile] + (["README.md", "changelog.md"] if profile == "main" else [])
    for required in required_paths:
        if not (root / required).is_file():
            errors.append(f"missing source path: {required}")
        elif required.endswith(".sh") and b"\r\n" in (root / required).read_bytes():
            errors.append(f"CRLF line endings in source script: {required}; use LF for Android")

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        rel = norm(path.relative_to(root))
        name = path.name
        if rel in ACTIVE_OVERLAY_PATHS:
            errors.append(f"active thermal overlay must not ship from source: {rel}")
        if name in RUNTIME_NAMES:
            errors.append(f"runtime state file must not be tracked: {rel}")
        if rel.startswith("dist/") or rel.startswith("release-check/"):
            errors.append(f"local release output must stay outside source: {rel}")
    if profile == "main" and not errors:
        errors.extend(check_main_metadata(root))
    return errors


def safe_zip_path(name):
    # Check the raw archive name before normalization can hide an absolute path.
    return bool(name) and "\x00" not in name and "\\" not in name and ":" not in name and all(
        part not in ("", ".", "..") for part in name.removesuffix("/").split("/")
    )


def zip_mode(info):
    return (info.external_attr >> 16) & 0o7777


def expected_zip_mode(name, is_dir):
    if is_dir:
        return 0o755
    if name in ROOT_EXECUTABLE or name.startswith("bin/"):
        return 0o755
    return 0o644


def check_zip(path, profile):
    errors = []
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = {
            info.orig_filename for info in infos
            if safe_zip_path(info.orig_filename) and not info.is_dir()
            and stat.S_IFMT(info.external_attr >> 16) in (0, stat.S_IFREG)
        }

        for required in REQUIRED[profile]:
            if required not in names:
                errors.append(f"missing package path: {required}")

        seen = set()
        for info in infos:
            if not safe_zip_path(info.orig_filename):
                errors.append(f"unsafe package path: {info.orig_filename}")
                continue
            name = info.orig_filename.removesuffix("/")
            if name in seen:
                errors.append(f"duplicate package path: {name}")
            seen.add(name)
            base = Path(name).name
            if name in ACTIVE_OVERLAY_PATHS:
                errors.append(f"active thermal overlay found in package: {name}")
            if base in RUNTIME_NAMES:
                errors.append(f"runtime state file found in package: {name}")
            if name in ZIP_BLOCKED_ROOT or any(name.startswith(prefix) for prefix in ZIP_BLOCKED_PREFIXES):
                errors.append(f"blocked package path found: {name}")

            mode = zip_mode(info)
            expected = expected_zip_mode(name, info.is_dir())
            file_type = stat.S_IFMT(info.external_attr >> 16)
            expected_type = stat.S_IFDIR if info.is_dir() else stat.S_IFREG
            if file_type not in (0, expected_type):
                errors.append(f"unsupported file type for package path: {name}")
            if mode and mode != expected:
                errors.append(f"unexpected mode {oct(mode)} for {name}; expected {oct(expected)}")
            if not mode:
                errors.append(f"missing Unix mode for package path: {name}")
            if not info.is_dir() and name.endswith(".sh") and b"\r\n" in archive.read(info):
                errors.append(f"CRLF line endings in package script: {name}; use LF for Android")
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=sorted(REQUIRED), required=True)
    parser.add_argument("--source", default=".")
    parser.add_argument("--skip-source", action="store_true")
    parser.add_argument("--zip")
    args = parser.parse_args()

    errors = []
    if not args.skip_source:
        errors.extend(check_source(Path(args.source), args.profile))
    if args.zip:
        errors.extend(check_zip(Path(args.zip), args.profile))

    if errors:
        for item in errors:
            print(f"ERROR: {item}", file=sys.stderr)
        return 1

    print("release validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
