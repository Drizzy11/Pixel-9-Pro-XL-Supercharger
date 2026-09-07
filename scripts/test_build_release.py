import hashlib
import io
import json
import stat
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

from build_release import archive_files, build_assets
import test_validate_release as validation_fixtures


class BuildReleaseTests(unittest.TestCase):
    def setUp(self):
        fixture = validation_fixtures.ReleaseValidationTests()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        source = fixture.source()
        self.files = {p.relative_to(source).as_posix(): p.read_bytes() for p in source.rglob("*") if p.is_file()}
        self.temp = tempfile.TemporaryDirectory(prefix="supercharger-build-test-")
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)

    def build(self, output=None):
        return build_assets(self.files, output or self.output / "release", "a" * 40, 1788739200)

    def test_allowlist_and_unix_modes(self):
        self.files.update({"site/index.html": b"website", "docs/private.txt": b"notes", "scripts/dev.py": b"dev"})
        manifest = self.build()
        with zipfile.ZipFile(self.output / "release" / manifest["package"]) as archive:
            names = archive.namelist()
            self.assertNotIn("README.md", names)
            self.assertFalse(any(n.startswith(("site/", "docs/", "scripts/")) for n in names))
            self.assertEqual((archive.getinfo("service.sh").external_attr >> 16) & 0o777, 0o755)
            self.assertEqual((archive.getinfo("module.prop").external_attr >> 16) & 0o777, 0o644)
            self.assertEqual(stat.S_IFMT(archive.getinfo("service.sh").external_attr >> 16), stat.S_IFREG)

    def test_repeated_builds_have_identical_bytes_and_manifest(self):
        first = self.build(self.output / "one")
        second = self.build(self.output / "two")
        self.assertEqual(first, second)
        for path in (self.output / "one").iterdir():
            self.assertEqual(path.read_bytes(), (self.output / "two" / path.name).read_bytes())

    def test_manifest_and_checksum_match_every_package_entry(self):
        manifest = self.build()
        folder = self.output / "release"
        digest = hashlib.sha256((folder / manifest["package"]).read_bytes()).hexdigest()
        self.assertEqual(digest, manifest["sha256"])
        self.assertEqual((folder / (manifest["package"] + ".sha256")).read_text().split()[0], digest)
        self.assertEqual(json.loads((folder / "release-manifest.json").read_text()), manifest)
        self.assertEqual((folder / "update.json").read_bytes(), self.files["update.json"])
        with zipfile.ZipFile(folder / manifest["package"]) as archive:
            for entry in manifest["files"]:
                self.assertEqual(hashlib.sha256(archive.read(entry["path"])).hexdigest(), entry["sha256"])

    def test_bad_metadata_produces_no_release_assets(self):
        self.files["update.json"] = b"{}"
        with self.assertRaises(ValueError):
            self.build()
        self.assertFalse((self.output / "release").exists())

    def test_existing_assets_are_not_overwritten(self):
        self.build()
        with self.assertRaisesRegex(ValueError, "already exist"):
            self.build()

    def test_packaged_symlinks_and_path_traversal_are_rejected(self):
        for name, kind in (("bin/link", tarfile.SYMTYPE), ("bin/../outside", tarfile.REGTYPE)):
            with self.subTest(name=name):
                stream = io.BytesIO()
                with tarfile.open(fileobj=stream, mode="w") as archive:
                    info = tarfile.TarInfo(name)
                    info.type = kind
                    info.linkname = "../../outside" if kind == tarfile.SYMTYPE else ""
                    archive.addfile(info)
                with self.assertRaises(ValueError):
                    archive_files(stream.getvalue())


if __name__ == "__main__":
    unittest.main()
