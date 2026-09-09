import contextlib
import io
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from check import check_shell_scripts


class ShellPreflightTests(unittest.TestCase):
    def test_syntax_errors_in_every_module_script_are_rejected(self):
        shell = shutil.which("bash")
        git = shutil.which("git")
        if git:
            git_bash = Path(git).resolve().parents[1] / "bin/bash.exe"
            if git_bash.is_file():
                shell = str(git_bash)
        self.assertIsNotNone(shell, "Bash is required for the repository checks")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "bin").mkdir()
            names = ["customize.sh", "service.sh", "uninstall.sh", "bin/supercharger_ctl.sh"]
            for name in names:
                (root / name).write_bytes(b"echo valid\n")
            with contextlib.redirect_stdout(io.StringIO()):
                check_shell_scripts(root, shell)
            for name in names:
                with self.subTest(script=name):
                    (root / name).write_bytes(b"if then\n")
                    with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError):
                        check_shell_scripts(root, shell)
                    (root / name).write_bytes(b"echo valid\n")


if __name__ == "__main__":
    unittest.main()
