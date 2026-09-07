"""Run explicitly selected shell functions in temporary, non-Android sandboxes."""
import os
import re
import signal
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_contained(command, *, cwd, timeout):
    job = None
    process = None
    launch_input = None
    options = {"cwd": cwd, "stdout": subprocess.PIPE, "stderr": subprocess.PIPE, "text": True}
    if os.name == "nt":
        from windows_job import WindowsJob
        job = WindowsJob()
        # Do not let Bash spawn children until its Python launcher belongs to the
        # job. Descendants inherit containment even if intermediate parents exit.
        bootstrap = (
            "import subprocess,sys; "
            "ready=sys.stdin.buffer.read(1); "
            "sys.exit(subprocess.call(sys.argv[1:],stdin=subprocess.DEVNULL) if ready==b'1' else 125)"
        )
        launch_command = [sys.executable, "-c", bootstrap, *command]
        options.update(stdin=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
        launch_input = "1"
    else:
        launch_command = command
        options.update(stdin=subprocess.DEVNULL, start_new_session=True)

    def terminate_tree():
        if job:
            job.close()
        elif process:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    try:
        process = subprocess.Popen(launch_command, **options)
        if job:
            try:
                job.assign(process.pid)
            except BaseException:
                # The launcher is still waiting for input; no Bash children exist.
                process.kill()
                raise
        try:
            stdout, stderr = process.communicate(input=launch_input, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            terminate_tree()
            stdout, stderr = process.communicate()
            raise subprocess.TimeoutExpired(command, timeout, output=stdout, stderr=stderr) from exc
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
    finally:
        terminate_tree()
        if process:
            process.communicate()


def shell_executable():
    git = shutil.which("git")
    if git:
        bundled = Path(git).resolve().parents[1] / "bin/bash.exe"
        if bundled.is_file():
            return str(bundled)
    shell = shutil.which("bash")
    if not shell:
        raise RuntimeError("Bash is required for shell regression tests")
    return shell


def functions_from(filename, names):
    source = (ROOT / filename).read_text(encoding="utf-8")
    functions = []
    for name in names:
        match = re.search(rf"^{re.escape(name)}\(\) \{{\n.*?^\}}$", source, re.MULTILINE | re.DOTALL)
        if not match:
            raise AssertionError(f"Missing isolated function: {filename}:{name}")
        functions.append(match.group(0))
    return "\n\n".join(functions)


def run_shell(source, *, timeout=15):
    with tempfile.TemporaryDirectory(prefix="supercharger-shell-") as folder:
        root = Path(folder)
        script = root / "test.sh"
        script.write_bytes(source.encode("utf-8"))
        return run_contained([shell_executable(), str(script)], cwd=root, timeout=timeout)
