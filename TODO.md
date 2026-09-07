# TODO

## Now

- [ ] Publish the prepared beta only after release approval, keeping it marked
  prerelease and not Latest. See [Release preparation](docs/RELEASING.md).
- [ ] Review [PR #11](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/pull/11)
  before merging; verify the checks for its latest commit.

## Next

- [ ] Record a real Pixel validation session before the next release: codename,
  Android build, root manager/version, clean boot, profile persistence after an
  update, Thermal Control enable/disable with reboot, and support snapshot.
  Deferred: the maintainer's Pixel currently has no root. This does not block
  repository fixes or isolated host regression tests.

## Completed locally

- [x] Audit candidate failure paths: abort failed installer state creation,
  validate update/download routing, and protect published release assets.
- [x] Prepare beta metadata/changelog and a shared clean-commit release builder
  with checksums, per-file manifest, and packaging regression tests.
- [x] Batch task state/log progress into one bounded response and suspend WebUI
  pollers while hidden, rejecting stale responses and resuming completed jobs.
- [x] Batch package inventories into two queries, cache the WebUI list for up to
  one minute, and invalidate it on refresh, return, or boot/module identity changes.
- [x] Use incremental ART compilation with capability-gated background priority,
  explicit selected-app force, and truthful performed/skipped/failed reporting.
- [x] Commit and push the maintenance branch, open PR #11, and verify the hosted
  push and pull-request checks on the initial maintenance commit `ad752d8`.
- [x] Add isolated installation/update/uninstall tests, including all six saved
  performance/thermal profile combinations, invalid persisted values, device and
  Magisk gates, registry ownership, and PID validation.
- [x] Remove the stale dashboard updater lock during reinstall; make expected
  absent/non-empty registry cleanup succeed and reject invalid uninstall PIDs.
- [x] Add a functions-only shell harness for background workers, state readers,
  lock ownership, and dashboard updater shutdown; Android operations are stubbed.
- [x] Preserve final task state when a worker finishes quickly or a status poll
  overlaps completion. Only the worker writes its lifecycle state.
- [x] Serialize asynchronous launches before changing logs/state, preserve job
  labels across operation calls, and report initialization failures.
- [x] Protect incomplete lock records and serialize acquisition/recovery with a
  kernel-managed `flock` guard that releases automatically when its owner dies.
- [x] Terminate complete test process trees on timeout and sandbox exit, using
  Windows Job Objects or POSIX process groups, with regressions on both platforms.
- [x] Reject NUL bytes in ZIP paths before checking forbidden runtime/thermal
  entries, with tests for the effective extraction name.
- [x] Exit the dashboard updater on termination signals and verify HUP/TERM
  cleanup in subprocess tests.

See [host validation and device boundaries](docs/TESTING.md) for the evidence.
