# Release preparation

## Build from reviewed source

Prepare releases in a clean worktree so parallel website work, logs, and ignored
local files cannot enter the package. `scripts/build_release.py` reads an archive
of the exact Git commit, validates its source metadata, applies the module's
explicit package allowlist, assigns Unix file modes, and validates the ZIP.

Run the checks described in [Testing](TESTING.md), then commit the synchronized
`module.prop`, `update.json`, installer, service, README, and changelog changes.
Build into a fresh directory outside the source checkout:

```sh
python3 scripts/build_release.py --output /path/to/release-artifacts
```

The builder produces the module ZIP, its SHA-256 file, `update.json`,
`release-notes.md`, and `release-manifest.json`. The manifest records the commit,
ZIP hash, and every packaged file's hash, size, and Unix mode. Timestamps come
from the commit, file order is stable, and repeated builds must match. The source
must be committed and clean; existing output assets are never overwritten.

Both branch CI and the tag-release workflow use this builder. Development docs,
tests, Git metadata, and the separate website are excluded from the ZIP.

## Current beta candidate

- Tag name: `v2.6.8-beta.1`.
- Module ID: `p9pxl_supercharger` (unchanged for upgrade compatibility).
- Version code: `26008`, reserved for this beta.
- Publication flags: draft while preparing; prerelease and not Latest when published.
- Installation: manual ZIP selection in the root manager, followed by a reboot.
- Update feed: keep `module.prop` pointing to stable release assets. The beta
  must not replace the stable feed or be advertised as a stable update.
- Subsequent releases intended to update this beta must have a higher version
  code. Under the existing encoding, `v2.6.9` has `26009`; do not publish a final
  `v2.6.8` with the same `26008` and expect managers to offer it as an update.

## Draft and publication

Create a GitHub draft targeting the full preparation commit, attach the ZIP,
checksum, update metadata, and manifest, and use the generated notes. Verify the
draft flag, prerelease flag, target commit, and downloaded asset hashes.

Do not push a `v*` tag as a preparation shortcut: it triggers the publication
workflow. Publishing the draft is a separate user-authorized action. If the tag
workflow runs after publication, it rebuilds the same committed source through
the shared builder. Prereleases explicitly use `--latest=false`.

Rerunning the tag workflow verifies an already-published release's assets and
leaves them unchanged. A mismatch fails instead of overwriting published bytes.
Only drafts can have their assets replaced, and draft updates retain the draft
flag. An API/authentication failure is not treated as a missing release.

Before publishing, verify that `/releases/latest` and its `update.json` still
refer to the stable release, and that the draft's assets match the manifest.

## Device acceptance still pending

The maintainer currently has no rooted Pixel. Host tests and a valid ZIP do not
establish Android boot, ART, root-manager, performance, or thermal behavior.

Record the following with each tester's device codename, Android build, root
manager/version, profile, thermal setting, and support snapshot:

- Fresh installation and clean boot with Thermal Control off.
- Update from the previous stable version, retaining both profile selections.
  Thermal Control intentionally returns to off after the update; re-enable it
  manually only after confirming a clean boot.
- Normal ART optimization, skipped work, failures, and explicit forced action.
- WebUI hiding/reopening during a job, completion, interruption, and retry.
- Profile changes with reboot and Thermal Control enable/disable with reboot.
- Uninstall and clean reboot, preserving an external thermal add-on's registry.
  Finish maintenance/ART jobs before uninstalling. Record profile selections
  first: uninstall intentionally clears the module's saved settings.

Expected install failures (for example, an unwritable required state file) must
abort installation rather than report completion. Unsupported tuning nodes may
be logged as skipped; do not confuse a safe skip with proof of a performance gain.

Keep the previous stable ZIP available. Use the installed root manager's own
supported recovery/safe-mode procedure if normal boot is unavailable. Do not
declare this beta stable or claim measured performance gains before field evidence.
