# Contributing

Thanks for helping improve Pixel 9 Series Supercharger. This project is
deliberately conservative: a change that makes a benchmark look better but costs
stability, battery, or thermal headroom is not an improvement here.

## Before you start

Open an issue first for anything beyond a typo. Tuning changes in particular are
worth discussing before implementation, because most of them depend on whether a
given kernel actually accepts the write.

Out of scope, regardless of implementation quality:

- Bypassing thermal safety limits
- Overriding charging behavior
- Forcing fixed CPU or GPU clocks in the stable profile
- Global IRQ affinity, or writes to nodes the kernel has not accepted
- Changes tied rigidly to one Android build

## Design rules

Every change should hold to the behavior the module already promises:

1. **Best effort, never forced.** If the kernel rejects a node, log it as
   skipped and leave it unchanged. Never retry with a wider hammer.
2. **Validate before writing.** Confirm a path exists and is writable, and that
   a block device is physical, before touching it.
3. **Log what you did.** Use the existing `[PASS]` / `[SKIP]` / `[INFO]` /
   `[ERROR]` prefixes so `debug.log` stays greppable.
4. **No hidden behavior.** The WebUI should apply what the user asked for and
   nothing else.
5. **Keep it POSIX.** Module scripts run under `/system/bin/sh`. Avoid bashisms.

## Repository layout

| Path                  | Purpose                                              |
| --------------------- | ---------------------------------------------------- |
| `customize.sh`        | Installer: device gate, permissions, initial state    |
| `service.sh`          | Boot-time tuning and status collection                |
| `bin/supercharger_ctl.sh` | Command surface the WebUI calls                   |
| `webroot/`            | WebUI dashboard (`index.html`, `index.mjs`)           |
| `common/repo.json`    | Extended module metadata read by MMRL                 |
| `thermal_profiles/`   | Balanced, Gaming, and Charge Cool overlays            |
| `scripts/`            | Release validation and WebUI regression tests         |
| `docs/`               | README images and branding assets, never packaged     |

## Running the checks

Use Python 3.10+, Node.js 24, Bash, and Linux `flock`. The same entry point runs locally,
on branch pushes and pull requests, and before release packaging:

```sh
python3 scripts/check.py
```

On Windows, use your installed Python command and Git for Windows Bash:

```powershell
python scripts/check.py --shell 'C:\Program Files\Git\bin\bash.exe'
wsl -d Ubuntu -- python3 -m unittest discover -s scripts -p 'test_*.py'
```

Native Git Bash runs the Windows-compatible checks and explicitly skips Linux
kernel-lock tests. The WSL command above runs the full Python suite, including
real `flock` behavior. CI runs the complete suite on Ubuntu and separately tests
native Windows process containment.

The checks parse every module shell script individually, check WebUI JavaScript
syntax, run WebUI and Python regressions, parse JSON, and validate release source.
They do not execute Android tuning on the development host. Keep scripts in LF
format; `.gitattributes` preserves this on Windows and the validator rejects CRLF
scripts in source and ZIP files. Shell parsing does not replace Android runtime
testing.

`validate_release.py` also enforces cross-file consistency: the version in
`module.prop`, `update.json`, `customize.sh`, `service.sh`, `README.md`, and the
newest `changelog.md` section must all agree. All README release version markers
must match the module's version.

To validate a locally built release ZIP, keep it outside the source tree and run:

```sh
python3 scripts/validate_release.py --profile main --skip-source --zip /path/to/module.zip
```

The ZIP validator requires actual files at the mandatory paths and rejects unsafe
or duplicate paths, symbolic links, unexpected permissions, runtime state, and
development-only content. Package creation still uses the explicit allowlist in
`.github/workflows/release.yml`.

If you change WebUI state handling, add coverage to
`scripts/webui_regression.test.mjs`. It stubs the KernelSU `ksu.exec` bridge, so
you can exercise the dashboard without a device.

Shell lifecycle coverage lives in `scripts/test_task_lifecycle.py`. It extracts
named functions into temporary directories and replaces Android operations with
test doubles; it never launches the complete Android entry scripts on the host.
See [Testing](docs/TESTING.md) for covered scenarios and device validation limits.
Installation, update persistence, and uninstall cleanup are covered by
`scripts/test_install_lifecycle.py` using the same functions-only sandbox.
App inventory batching, ART capability probing, result handling, and the bounded
progress response are covered by `scripts/test_optimization_policy.py`. Its Android
package-manager commands are test doubles; it never compiles host or device apps.

## Testing on a device

Automated checks cannot tell you whether tuning actually helped. For anything
touching `service.sh` or the profiles, please also report:

- Device codename and Android build
- Root solution and version
- Whether the device booted cleanly, and whether Thermal Control was enabled
- The relevant `debug.log` section, including skipped entries

## Pull requests

- Keep the diff scoped to one change; do not reformat unrelated code.
- Match the style of the file you are editing.
- Comment non-obvious logic only.
- Use [Conventional Commits](https://www.conventionalcommits.org) for commit
  subjects: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`, `build:`.
- Do not bump the version or edit `changelog.md`; releases are cut by the
  maintainer.

## Reporting problems

Use the [bug report template](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/issues/new?template=bug_report.yml)
and attach a support snapshot from the WebUI **Support** tab. Security issues go
through [SECURITY.md](SECURITY.md) instead, not a public issue.

## Public website

The static English/Spanish website lives in `site/`, separately from `webroot/`.
Use Python 3.10+ and Node 24:

```sh
python3 scripts/build_site.py
python3 scripts/check_site.py
python3 scripts/serve_site.py
```

Use `python3 scripts/build_site.py --refresh` to refresh public release data.
See [website development](docs/WEBSITE.md) for generated files, translations,
image preparation, browser checks, and GitHub Pages deployment. Website changes
need browser verification; sample dashboard values are not device evidence.
