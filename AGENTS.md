# Supercharger contributor instructions

## Project and boundaries

Pixel 9 Series Supercharger is a systemless Android root module for Tensor G4.
Read `CONTRIBUTING.md` and `README.md` before changing behavior. Android module
scripts target `/system/bin/sh`; retain existing shell patterns and avoid new
Bash-only syntax. Never execute the installer, service, controller, or uninstaller
on the development host as a way to test them. Shell regression tests may extract
explicitly named functions into temporary sandboxes with Android operations
replaced by test doubles; see `docs/TESTING.md`.

Preserve best-effort writes, device checks, thermal safety, and Thermal Control's
off-by-default installation. Do not force clocks in the stable profile, bypass
thermal limits, or override charging behavior.

## Layout

- `customize.sh`: installation, device gate, and persistent profile restoration.
- `service.sh`: boot tuning, status generation, and dashboard updater.
- `bin/supercharger_ctl.sh`: WebUI commands, maintenance, app optimization, profiles.
- `webroot/`: standalone HTML/ES modules and the KernelSU bridge; no npm build.
- `thermal_profiles/`: bundled opt-in overlays, never active `system/vendor/etc` files.
- `scripts/`: Python release validation and Node/Python regression tests.
- `.github/workflows/release.yml`: tag/version gate and explicit package allowlist.

## Validation and releases

- Run `python3 scripts/check.py` (Python 3.10+, Node 24, Bash, Linux `flock`).
- Windows: `python scripts/check.py --shell 'C:\Program Files\Git\bin\bash.exe'`.
  Kernel-lock tests skip in native Git Bash; also run the Python suite in WSL:
  `wsl -d Ubuntu -- python3 -m unittest discover -s scripts -p 'test_*.py'`.
- WebUI state changes need coverage in `scripts/webui_regression.test.mjs`.
- Release validation changes need Python regression coverage in `scripts/test_*.py`.
- Worker/lock/status lifecycle changes need `scripts/test_task_lifecycle.py` coverage.
- Keep the `.lock.guard` files at stable paths; never unlink them during runtime.
  Their kernel locks cover directory acquisition/recovery, not whole task execution.
- Harness process cleanup must pass `scripts/test_shell_harness.py` on Linux and
  native Windows; GitHub Actions includes both platforms for this regression.
- Installer/uninstaller and profile persistence changes need `scripts/test_install_lifecycle.py` coverage.
- Keep text LF. Keep temporary packages outside the source checkout; never ship
  logs, runtime state, docs, tests, or Git metadata in module ZIPs.
- Do not bump versions or edit `changelog.md` during routine maintenance. Release
  metadata is synchronized across files by the validator; a release is separate work.
- Changes to tuning or profiles need real-device evidence (codename, build, root
  manager, boot/thermal state, and logs). Host checks do not prove device behavior.

## Maintenance documentation

Keep usage in `README.md`, contributor commands in `CONTRIBUTING.md`, and concrete
unfinished work in `TODO.md`. Use Conventional Commit subjects when committing.
