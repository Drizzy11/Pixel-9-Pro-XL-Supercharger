#!/usr/bin/env python3
"""Run the shared local, pull-request, and release preflight checks."""
import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def check_shell_scripts(root, shell):
    # bash -n accepts one script; extra filenames become its positional arguments.
    for path in sorted(root.glob("*.sh")) + sorted((root / "bin").rglob("*.sh")):
        print(f"Checking shell syntax: {path.relative_to(root)}", flush=True)
        subprocess.run([shell, "-n", str(path)], cwd=root, check=True, capture_output=True, text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shell", default="bash", help="Bash executable used for syntax checks")
    args = parser.parse_args()
    try:
        check_shell_scripts(ROOT, args.shell)
        for path in sorted((ROOT / "webroot").glob("*.mjs")) + sorted((ROOT / "webroot").glob("*.js")):
            subprocess.run(["node", "--check", str(path)], cwd=ROOT, check=True)
        subprocess.run(["node", "--test", "scripts/webui_regression.test.mjs"], cwd=ROOT, check=True)
        subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "scripts", "-p", "test_*.py"], cwd=ROOT, check=True)
        for path in [ROOT / "update.json", ROOT / "common/repo.json", *sorted((ROOT / "thermal_profiles").rglob("*.json"))]:
            print(f"Checking JSON: {path.relative_to(ROOT)}", flush=True)
            json.loads(path.read_text(encoding="utf-8"))
        subprocess.run([sys.executable, "scripts/validate_release.py", "--profile", "main", "--source", "."], cwd=ROOT, check=True)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
            print(exc.stderr.rstrip(), file=sys.stderr)
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("All repository checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
