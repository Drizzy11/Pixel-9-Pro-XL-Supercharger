import shlex
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from shell_harness import run_shell


class ShellHarnessTests(unittest.TestCase):
    def test_timeout_terminates_descendants_before_cleanup(self):
        with tempfile.TemporaryDirectory(prefix="supercharger-timeout-proof-") as directory:
            marker = Path(directory) / "survived"
            ready = Path(directory) / "started"
            # Bounded even on the broken runner: the child naturally exits after
            # writing the marker, so a regression cannot leak an infinite loop.
            source = f"(echo started > {shlex.quote(ready.as_posix())}; sleep 2; echo survived > {shlex.quote(marker.as_posix())}) &\nwait\n"
            with self.assertRaises(subprocess.TimeoutExpired):
                run_shell(source, timeout=1)
            self.assertTrue(ready.exists(), "the descendant must start before the timeout")
            time.sleep(2.1)
            self.assertFalse(marker.exists(), "a descendant survived the timeout")

    def test_success_also_cleans_up_orphaned_descendants(self):
        with tempfile.TemporaryDirectory(prefix="supercharger-orphan-proof-") as directory:
            marker = Path(directory) / "survived"
            ready = Path(directory) / "started"
            source = f'''
(echo started > {shlex.quote(ready.as_posix())}; sleep 2; echo survived > {shlex.quote(marker.as_posix())}) >/dev/null 2>&1 &
while [ ! -f {shlex.quote(ready.as_posix())} ]; do sleep 0.02; done
exit 0
'''
            self.assertEqual(run_shell(source).returncode, 0)
            self.assertTrue(ready.exists())
            time.sleep(2.1)
            self.assertFalse(marker.exists(), "a descendant outlived a successful sandbox")

    def test_result_keeps_the_exit_code_and_both_output_streams(self):
        result = run_shell("echo 'output ⚠️'; echo 'problem 🚀' >&2; exit 7\n")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout.strip(), "output ⚠️")
        self.assertEqual(result.stderr.strip(), "problem 🚀")


if __name__ == "__main__":
    unittest.main()
