# Testing Supercharger

## Host checks without a rooted phone

Run `python3 scripts/check.py` from a checkout with Python 3.10+, Node.js 24,
Bash, and Linux `flock`. On Windows with Git for Windows:

```powershell
python scripts/check.py --shell 'C:\Program Files\Git\bin\bash.exe'
wsl -d Ubuntu -- python3 -m unittest discover -s scripts -p 'test_*.py'
```

Native Git Bash lacks `flock`, so Linux kernel-lock cases explicitly skip there.
Run the full Python suite in WSL as shown above; do not count skips as device or
Linux lock validation. CI requires the full Ubuntu checks and a separate native
Windows process-containment job.

The same runner is used by the branch/PR checks and release preflight. It checks
each module shell script separately, JavaScript syntax, WebUI regressions, Python
regressions, JSON, and source release metadata.

`scripts/shell_harness.py` reads only explicitly selected function definitions.
Tests run these definitions in temporary directories with synthetic state files,
real child processes and locks, and test doubles for Android operations. They do
not execute the full installer, service, controller, or uninstaller. Tests never
invoke ART compilation or write device tuning nodes.

The harness contains each test process tree. Linux uses a dedicated process
group; Windows assigns a waiting launcher to a Job Object before allowing Bash
to start. Timeout or sandbox exit terminates descendants before directory cleanup.
The Job Object also catches children orphaned by an intermediate parent exiting.

## Lifecycle regressions

`scripts/test_task_lifecycle.py` covers:

- Fast workers retaining `done` rather than being overwritten by a launcher's
  delayed `running` record.
- A status poll overlapping completion without rewriting the task's record.
- State writers preserving their caller's variables.
- Five competing launches producing one operation and preserving its output,
  label, final state, and lock cleanup.
- Incomplete owner records not being mistaken for stale locks.
- Kernel-serialized stale-lock recovery keeping one owner across competing starts.
- A killed reclaimer releasing its kernel guard so a retry succeeds immediately.
- Legacy abandoned `.reclaim` directories not blocking new acquisition.
- Failed workers releasing their locks so a retry can succeed.
- Initialization failures returning an error without running the operation.
- Interrupted tasks being reported without modifying shared state during a read.
- Dashboard updater exit and PID/lock cleanup on HUP and TERM.

Asynchronous tasks hold a lifecycle lock in addition to the operation's existing
lock. The launcher reserves ownership before shared output is changed, and the
worker publishes its initial state before launch acknowledgment. Only the worker
writes task state afterward. Status readers render an interruption if a recorded
worker is gone. Acquisition and recovery use `flock` on a stable `.lock.guard` file;
the kernel releases that guard when its process dies. Never delete the guard file
during runtime, since another process may still hold its inode. Boot/install
cleanup still handles abandoned task locks and legacy `.reclaim` directories;
an incomplete task owner record is conservatively treated as busy until cleanup.
See [the lock guard decision](decisions/001-kernel-lock-recovery-guard.md).

## Verified locally

The initial maintenance checkout passed 10 Node WebUI tests and 22 Python tests (including
10 shell lifecycle tests), shell/JavaScript parsing, JSON/source validation, and
`git diff --check` on Windows with Python 3.11, Node 24, and Git Bash. The fast
completion, status overwrite, variable clobbering, stale-recovery race, and updater
termination cases were reproduced against the original affected functions.

The installation/update/uninstall follow-up adds nine tests in
`scripts/test_install_lifecycle.py`, bringing that revision to 10 Node and 31 Python
tests. These cover safe fresh-install defaults, all six persisted profile
combinations, malformed values, stale lock cleanup, boot log rotation, device and
Magisk gates, registry ownership, repeatable cleanup, and uninstall PID validation.
The reinstall lock leak, non-empty/missing registry exit status, and invalid PID
cases failed before their corrections. Installer/uninstaller logic is exposed as
named functions so tests can use temporary paths and stub process signals without
running the full Android entry scripts.

The PR-review fixes bring the suite to 10 Node and 37 Python tests. All 37 Python
tests passed under Ubuntu/WSL without skips. Native Windows passed its applicable
checks, including all three process-containment regressions, and explicitly
skipped nine Linux-only cases. NUL-path tests reproduce extraction aliases for
active thermal files, runtime logs, and blocked documentation files.

The initial commit `ad752d8` also passed hosted
[push checks](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/actions/runs/34074833370)
and [PR checks](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/actions/runs/34074853523).
Check the latest commit's results on
[PR #11](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/pull/11) before merging.

## WebUI and ART efficiency regressions

`scripts/webui_regression.test.mjs` now includes 17 tests. New cases cover one
progress bridge call, hidden/visible transitions, late responses, completion while
hidden, cache expiry, refresh coalescing, invalidation during an in-flight request,
error handling, and the explicit selected-app recompilation action.

`scripts/test_optimization_policy.py` adds 10 host-only shell tests. Fixtures check
two package inventory queries, preservation of user scope and core exclusions,
failure versus empty inventory, `pm` fallback, ART capability probing once per
batch, non-forced commands, zero-exit failure results, and bounded progress output.
No forced `verify` fallback is sent. Without verbose ART output, accepted requests
are reported without claiming that compilation was performed.

The suite now contains 17 Node tests and 47 Python tests. Browser checks use a
temporary preview bridge and therefore establish UI behavior only; device ART,
root-manager lifecycle events, and real resource savings remain unverified.

## Release packaging regressions

`scripts/test_build_release.py` adds six tests for the package allowlist, Unix
modes, byte-for-byte repeatability, checksum/manifest consistency, rejection of
bad metadata, existing-output protection, and unsafe archive entries. The release
preparation suite contains 17 Node and 53 Python tests. CI also runs the actual
clean-commit builder before any tag is published. See [Releasing](RELEASING.md).

The final release audit adds failed-installer-state coverage, stable-feed and
repository URL checks, and five tests of the actual publication workflow block.
GitHub commands in those tests are doubles: they verify draft preservation,
published-asset equality/mismatch behavior, prerelease flags, and API failure
handling without publishing anything. This brings the suite to 17 Node and
61 Python tests.

## Device validation remains separate

Host Bash behavior is not proof of Android `/system/bin/sh`, ART, root-manager
integration, tuning effectiveness, boot stability, or thermal behavior. Before
releasing runtime changes, record a Pixel session with the codename, Android
build, root manager/version, clean boot, task progress and retry, profile
persistence after update, Thermal Control enable/disable with reboot, and logs.

The maintainer's Pixel currently has no root, so that session is deferred. No
device performance or thermal improvement is claimed by the host checks.
