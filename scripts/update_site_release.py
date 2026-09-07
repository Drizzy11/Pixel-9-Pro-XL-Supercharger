#!/usr/bin/env python3
"""Render verified latest stable GitHub release metadata into the static website."""
import argparse
from datetime import datetime, timezone
from html import escape
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = "Drizzy07x/Supercharger_Pixel_9_Series"
BASE = f"https://github.com/{REPO}"
START, END = "<!-- release:start -->", "<!-- release:end -->"


def render_release(data):
    if data.get("draft") is not False or data.get("prerelease") is not False:
        raise ValueError("Only published stable releases can be featured")
    tag = data["tag_name"]
    if not isinstance(tag, str) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Unexpected stable release tag")
    notes = f"{BASE}/releases/tag/{tag}"
    if data["html_url"] != notes:
        raise ValueError("Release URL does not match this repository and tag")
    published = datetime.fromisoformat(data["published_at"].replace("Z", "+00:00"))
    if published.tzinfo is None:
        raise ValueError("Release timestamp requires a timezone")
    date = published.astimezone(timezone.utc).date()
    name = f"Pixel-9-Series-Supercharger-{tag}.zip"
    assets = {}
    for expected in (name, name + ".sha256"):
        matches = [asset for asset in data["assets"] if asset.get("name") == expected]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one release asset: {expected}")
        asset = matches[0]
        url = f"{BASE}/releases/download/{tag}/{expected}"
        if asset.get("browser_download_url") != url:
            raise ValueError("Asset URL does not match this repository and tag")
        if type(asset.get("size")) is not int or asset["size"] <= 0:
            raise ValueError("Release asset must have a positive byte size")
        if asset.get("state", "uploaded") != "uploaded":
            raise ValueError("Release asset is not ready")
        assets[expected] = asset
    zip_asset = assets[name]
    size = f'{zip_asset["size"] / 1024:.1f} KiB'
    return f'''{START}
          <p class="release-meta"><strong>{escape(tag)} · Stable</strong><br>Published <time datetime="{date.isoformat()}">{date.isoformat()}</time> · {size}</p>
          <a class="button blue" href="{escape(zip_asset['browser_download_url'], quote=True)}">Download {escape(tag)} ZIP</a>
          <div class="release-links"><a href="{escape(notes, quote=True)}">Release notes</a><a href="{escape(assets[name + '.sha256']['browser_download_url'], quote=True)}">SHA-256 file</a><a href="{BASE}/releases/latest">All release assets</a></div>
          <p class="release-help">Download the ZIP and its SHA-256 file to check integrity. <a href="#verify-download">How to verify</a></p>
          {END}'''


def update_page(path, data):
    # Validate everything before touching the previous usable snapshot.
    rendered = render_release(data)
    path = path.resolve(strict=True)
    page = path.read_text(encoding="utf-8")
    if page.count(START) != 1 or page.count(END) != 1:
        raise ValueError("Website must have exactly one release region")
    updated, count = re.subn(re.escape(START) + r".*?" + re.escape(END),
                             lambda _: rendered, page, flags=re.S)
    if count != 1:
        raise ValueError("Invalid release marker order")
    write_atomic(path, updated)


def write_atomic(path, content):
    """Write a complete UTF-8 file without truncating an existing destination."""
    path = Path(path).resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    # Stage beside the destination so replacement stays on the same filesystem.
    # A partial write or locked destination must not destroy the last good page.
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.",
                                     suffix=".tmp", delete=False) as temporary:
        candidate = Path(temporary.name)
    try:
        candidate.write_text(content, encoding="utf-8", newline="\n")
        candidate.chmod(mode)
        os.replace(candidate, path)
    finally:
        if candidate.exists():
            # Only the staging file is ours to make writable for cleanup.
            candidate.chmod(stat.S_IMODE(candidate.stat().st_mode) | stat.S_IWUSR)
            candidate.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata", type=Path, help="Offline GitHub release API JSON")
    parser.add_argument("--page", type=Path, default=ROOT / "site/index.html")
    args = parser.parse_args()
    if args.metadata:
        data = json.loads(args.metadata.read_text(encoding="utf-8-sig"))
    else:
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "Supercharger-website"}
        token = os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/latest", headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.load(response)
    update_page(args.page, data)
    print(f"Website release snapshot updated: {data['tag_name']}")


if __name__ == "__main__":
    main()
