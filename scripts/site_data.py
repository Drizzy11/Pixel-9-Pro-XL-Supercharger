"""Fetch a public release snapshot and the matching published checksum."""
from datetime import datetime, timezone
import json
import os
import re
import urllib.request

from update_site_release import BASE, REPO, render_release


def get_json(url):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Supercharger-website"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
        return json.load(response)


def parse_checksum(text, filename):
    match = re.fullmatch(r"\s*([a-fA-F0-9]{64})\s+\*?([^\r\n]+)\s*", text)
    if not match or match[2].strip() != filename:
        raise ValueError("Checksum must name the selected module ZIP")
    return match[1].lower()


def public_history(items):
    result = []
    for item in items:
        if item.get("draft") is not False or not item.get("published_at"):
            continue
        tag = item.get("tag_name", "")
        if not re.fullmatch(r"v[0-9]+(?:\.[0-9]+){1,2}(?:-[a-zA-Z0-9.]+)?", tag):
            continue
        url = f"{BASE}/releases/tag/{tag}"
        if item.get("html_url") != url:
            raise ValueError("Unexpected history release URL")
        date = datetime.fromisoformat(item["published_at"].replace("Z", "+00:00")).date().isoformat()
        result.append({"tag": tag, "date": date, "url": url,
                       "prerelease": bool(item.get("prerelease")), "notes": item.get("body") or ""})
    return sorted(result, key=lambda record: record["date"], reverse=True)


def fetch_snapshot():
    latest = get_json(f"https://api.github.com/repos/{REPO}/releases/latest")
    render_release(latest)  # Require a complete stable module release.
    filename = f"Pixel-9-Series-Supercharger-{latest['tag_name']}.zip"
    assets = [asset for asset in latest["assets"] if asset["name"] in (filename, filename + '.sha256')]
    checksum_url = next(asset["browser_download_url"] for asset in assets if asset["name"].endswith('.sha256'))
    # Public asset requests carry no API token, including across GitHub redirects.
    with urllib.request.urlopen(checksum_url, timeout=30) as response:
        text = response.read(4097)
    if len(text) > 4096:
        raise ValueError("Unexpected checksum file size")
    checksum = parse_checksum(text.decode('utf-8'), filename)
    minimal = {key: latest[key] for key in ('tag_name', 'published_at', 'html_url', 'draft', 'prerelease')}
    minimal['assets'] = [{key: asset[key] for key in ('name', 'size', 'state', 'browser_download_url')} for asset in assets]
    items = []
    for page in range(1, 11):
        batch = get_json(f"https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}")
        items.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise ValueError("Release pagination exceeded the website limit")
    return {"latest": minimal, "sha256": checksum, "history": public_history(items),
            "updated": datetime.now(timezone.utc).isoformat()}
