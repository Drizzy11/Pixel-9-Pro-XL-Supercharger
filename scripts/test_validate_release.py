import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

from validate_release import REQUIRED, ROOT_EXECUTABLE, check_source, check_zip


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def package(self, *, replacements=None, extras=()):
        replacements = replacements or {}
        path = self.root / "module.zip"
        with zipfile.ZipFile(path, "w") as archive:
            entries = [(name, b"sample\n", None) for name in REQUIRED["main"]]
            entries = [replacements.get(name, (name, data, mode)) for name, data, mode in entries]
            for name, data, mode in entries + list(extras):
                info = zipfile.ZipInfo(name)
                # ZipInfo normalizes backslashes on Windows; retain the raw test name.
                info.filename = name
                info.create_system = 3
                if mode is None:
                    mode = stat.S_IFREG | (0o755 if name in ROOT_EXECUTABLE or name.startswith("bin/") else 0o644)
                info.external_attr = mode << 16
                archive.writestr(info, data)
        return path

    def source(self):
        source = self.root / "source"
        repo = Path(__file__).resolve().parents[1]
        for name in REQUIRED["main"] + ["README.md", "changelog.md"]:
            dest = source / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            # The fixture represents a clean LF checkout on every host.
            dest.write_bytes((repo / name).read_bytes().replace(b"\r\n", b"\n"))
        return source

    def test_valid_package(self):
        self.assertEqual(check_zip(self.package(), "main"), [])

    def test_required_file_cannot_be_a_directory(self):
        path = self.package(replacements={"service.sh": ("service.sh/child", b"", None)})
        self.assertIn("missing package path: service.sh", check_zip(path, "main"))

    def test_unsafe_archive_paths(self):
        for name in ("../outside", "/absolute", "bin/../outside", "C:/outside", "bin\\outside", "./service.sh"):
            with self.subTest(name=name):
                path = self.package(extras=[(name, b"", stat.S_IFREG | 0o644)])
                self.assertTrue(any("unsafe package path" in error for error in check_zip(path, "main")))

    def test_duplicate_package_paths(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            path = self.package(extras=[("module.prop", b"different", None)])
        self.assertTrue(any("duplicate package path" in error for error in check_zip(path, "main")))

    def test_nul_cannot_hide_a_forbidden_extraction_path(self):
        for name in ("system/vendor/etc/thermal_info_config.json", "maintenance.log", "README.md"):
            with self.subTest(name=name):
                path = self.package(extras=[(name + "\x00ignored", b"{}", stat.S_IFREG | 0o644)])
                with zipfile.ZipFile(path) as archive:
                    self.assertEqual(archive.infolist()[-1].filename, name)
                self.assertTrue(any("unsafe package path" in error for error in check_zip(path, "main")))

    def test_symlinks_and_special_permissions(self):
        for mode in (stat.S_IFLNK | 0o755, stat.S_IFREG | 0o4755):
            with self.subTest(mode=oct(mode)):
                path = self.package(replacements={"service.sh": ("service.sh", b"target", mode)})
                self.assertTrue(check_zip(path, "main"))

    def test_crlf_shell_script_in_package(self):
        path = self.package(replacements={"service.sh": ("service.sh", b"#!/system/bin/sh\r\necho ok\r\n", None)})
        self.assertTrue(any("CRLF" in error for error in check_zip(path, "main")))

    def test_valid_source(self):
        self.assertEqual(check_source(self.source(), "main"), [])

    def test_crlf_shell_script_in_source(self):
        source = self.source()
        (source / "service.sh").write_bytes(b"#!/system/bin/sh\r\necho ok\r\n")
        self.assertTrue(any("CRLF" in error for error in check_source(source, "main")))

    def test_required_source_file_cannot_be_a_directory(self):
        source = self.source()
        (source / "service.sh").unlink()
        (source / "service.sh").mkdir()
        self.assertIn("missing source path: service.sh", check_source(source, "main"))

    def test_missing_metadata_docs_report_errors(self):
        source = self.source()
        (source / "README.md").unlink()
        self.assertTrue(any("README.md" in error for error in check_source(source, "main")))

    def test_update_feed_must_be_an_object(self):
        source = self.source()
        (source / "update.json").write_text("[]", encoding="utf-8")
        self.assertTrue(any("update.json" in error for error in check_source(source, "main")))

    def test_module_feed_cannot_follow_unreleased_branch_metadata(self):
        source = self.source()
        prop = source / "module.prop"
        import re
        prop.write_text(re.sub(r"^updateJson=.*$", "updateJson=https://raw.githubusercontent.com/owner/repo/main/update.json", prop.read_text(), flags=re.M), encoding="utf-8")
        self.assertTrue(any("stable GitHub release asset feed" in error for error in check_source(source, "main")))

    def test_update_zip_must_belong_to_the_same_repository(self):
        source = self.source()
        update = source / "update.json"
        update.write_text(update.read_text().replace("Drizzy07x/Supercharger_Pixel_9_Series/releases/download/", "other/other/releases/download/"), encoding="utf-8")
        self.assertTrue(any("exact versioned module ZIP" in error for error in check_source(source, "main")))


if __name__ == "__main__":
    unittest.main()
