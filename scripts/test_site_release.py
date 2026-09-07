"""Website release links must identify real, complete, stable module assets."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from update_site_release import BASE, START, END, render_release, update_page


def release():
    tag = "v2.6.7"
    name = f"Pixel-9-Series-Supercharger-{tag}.zip"
    return {
        "tag_name": tag, "draft": False, "prerelease": False,
        "published_at": "2026-07-30T22:23:12Z",
        "html_url": f"{BASE}/releases/tag/{tag}",
        "assets": [{"name": asset, "size": size, "state": "uploaded",
                    "browser_download_url": f"{BASE}/releases/download/{tag}/{asset}"}
                   for asset, size in ((name, 68740), (name + ".sha256", 105))],
    }


class SiteReleaseTests(unittest.TestCase):
    def test_renders_version_date_size_and_matching_links(self):
        html = render_release(release())
        for expected in ("v2.6.7 · Stable", 'datetime="2026-07-30"', "67.1 KiB",
                         "Download v2.6.7 ZIP", "v2.6.7.zip.sha256", "Release notes"):
            self.assertIn(expected, html)

    def test_rejects_drafts_prereleases_and_unsafe_tags(self):
        for key, value in (("draft", True), ("prerelease", True),
                           ("tag_name", "v2.6.7-beta"), ("tag_name", '<script>')):
            with self.subTest(key=key, value=value):
                data = release(); data[key] = value
                with self.assertRaises(ValueError):
                    render_release(data)

    def test_source_archive_is_not_an_installable_asset(self):
        data = release()
        data["assets"][0]["name"] = "Source code.zip"
        with self.assertRaises(ValueError):
            render_release(data)

    def test_rejects_incomplete_or_duplicate_assets(self):
        for mutation in (lambda d: d["assets"].pop(),
                         lambda d: d["assets"].append(copy.deepcopy(d["assets"][0])),
                         lambda d: d["assets"][0].update(size=0),
                         lambda d: d["assets"][0].update(state="starter")):
            data = release(); mutation(data)
            with self.assertRaises(ValueError):
                render_release(data)

    def test_rejects_external_or_mismatched_links(self):
        for url in ("javascript:alert(1)", "https://github.com/another/repo/file.zip",
                    f"{BASE}/releases/download/v2.6.6/old.zip"):
            data = release(); data["assets"][0]["browser_download_url"] = url
            with self.assertRaises(ValueError):
                render_release(data)
        data = release(); data["html_url"] = "https://example.com"
        with self.assertRaises(ValueError):
            render_release(data)

    def test_updates_only_marked_region_idempotently(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "index.html"
            path.write_text(f"before\n{START}old{END}\nafter\n", encoding="utf-8")
            mode = path.stat().st_mode
            update_page(path, release())
            self.assertEqual(mode, path.stat().st_mode)
            first = path.read_bytes()
            update_page(path, release())
            self.assertEqual(first, path.read_bytes())
            self.assertTrue(first.startswith(b"before\n"))
            self.assertTrue(first.endswith(b"\nafter\n"))
            self.assertNotIn(b"\r\n", first)

    def test_failure_preserves_previous_snapshot(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "index.html"
            original = f"before {START}last working release{END} after"
            path.write_text(original, encoding="utf-8")
            data = release(); data["assets"] = []
            with self.assertRaises(ValueError):
                update_page(path, data)
            self.assertEqual(original, path.read_text(encoding="utf-8"))

    def test_rejects_missing_duplicate_or_reversed_markers(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "index.html"
            for original in ("no markers", START + START + END, END + START):
                path.write_text(original, encoding="utf-8")
                with self.assertRaises(ValueError):
                    update_page(path, release())
                self.assertEqual(original, path.read_text(encoding="utf-8"))

    def test_partial_write_failure_keeps_previous_page_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "index.html"
            original = f"before {START}working snapshot{END} after"
            path.write_text(original, encoding="utf-8")

            def fail_after_truncation(target, *args, **kwargs):
                target.write_bytes(b"partial write")
                raise OSError("simulated disk write failure")

            with patch.object(Path, "write_text", fail_after_truncation):
                with self.assertRaises(OSError):
                    update_page(path, release())
            self.assertEqual(original, path.read_text(encoding="utf-8"))
            self.assertEqual([path], list(Path(temp).iterdir()))

    def test_replace_failure_keeps_previous_page_and_cleans_temporary_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "index.html"
            original = f"before {START}working snapshot{END} after"
            path.write_text(original, encoding="utf-8")
            with patch("update_site_release.os.replace", side_effect=OSError("destination locked")):
                with self.assertRaises(OSError):
                    update_page(path, release())
            self.assertEqual(original, path.read_text(encoding="utf-8"))
            self.assertEqual([path], list(Path(temp).iterdir()))


if __name__ == "__main__":
    unittest.main()
