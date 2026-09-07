# Release candidate code audit

Date: 2026-09-07. Candidate: `v2.6.8-beta.1`.

This pass reviews the shipped code and the candidate changes against `v2.6.7`,
including the earlier maintenance and release-preparation work. Changes are on
`codex/release-v2.6.8-beta.1` in an isolated worktree; the separate website work
and the existing maintenance PR are not included in this patch set.

## Scope

| Area | Review and checks |
| --- | --- |
| Installer and uninstaller | Device/root-manager gates, required state initialization, persistence, targeted cleanup, process ownership; lifecycle regressions |
| Boot service | Best-effort node writes, profile selection, GPU backup/restore, temperature/status handling, updater lifecycle; static analysis and isolated functions |
| Controller | Command dispatch, async workers/locks, ART inventory/compilation, maintenance, snapshots, thermal operations, state serialization and failures |
| WebUI and bridge | All three shipped web files; state rendering, busy controls, polling/visibility, cache invalidation, failed commands, callback cleanup |
| Static tuning and overlays | `system.prop` and all six thermal JSON files; valid JSON without duplicate keys and no changes from the stable tag |
| Release/build tooling | Python runner, validators, builder, shell harness and Windows containment; both workflows, metadata, package allowlist and publication behavior |
| Documentation | Usage, contributor instructions, testing, release checklist, changelog and outstanding device acceptance |

## Findings corrected

1. **Maintenance could report success after failures.** Repairs ignored status
   writes, and the aggregate task ignored failed repairs or snapshots. Failures now
   propagate while locks are released; the async worker can report a failed task.
2. **Healthy status was misread.** Removing single quotes from double-quoted ENV
   values left `"pass"` unequal to `pass`. Repairs now use the existing ENV reader.
3. **Thermal changes could misreport success.** File removal, permissions, registry,
   selection and state failures were ignored. They now return errors. Failed apply
   attempts remove incomplete overlays where possible; failed cleanup explicitly
   tells the user to disable the module before rebooting.
4. **State replacement could lose or misreport data.** Complete temporary records
   are committed only after permissions are set; directory destinations are
   refused. Failed replacement preserves the old record. Profile persistence
   failures report partial local success instead of promising update persistence.
5. **GPU state survived its valid lifetime.** Old backups could overwrite the
   current boot's vendor policy. A boot identifier now limits reuse and restore to
   the same boot; legacy/old records are ignored. Experimental node writes require
   successful backup of their original value.
6. **Temperature parsing was unsafe and inaccurate.** `-5` deci-degrees displayed
   as positive `0.5C`; malformed/zero-prefixed readings reached shell arithmetic.
   Decimal normalization now handles sign and leading zeros and rejects malformed
   or excessively large values without arithmetic evaluation.
7. **Concurrent status replacement could hide an active task.** The controller now
   returns its own complete task-aware snapshot even if the temperature updater
   replaces the shared file before the response is returned.
8. **WebUI errors enabled conflicting actions.** Progress read failures now retry
   on the existing cadence while controls remain busy. Failed launch or partial
   profile/thermal updates reconcile status before enabling state-dependent controls.
9. **Windows could fail while decoding diagnostics.** The shell harness now reads
   UTF-8 explicitly, including the module's icon-bearing output, while preserving
   process containment and exit status.
10. **Unrecognized version suffixes could enter the stable channel.** All accepted
    suffixed versions are treated as prereleases, including `-preview.1`.

## Evidence

- Isolated regression cases reproduced the original maintenance, thermal-disable,
  stale GPU restore and temperature defects before correction. No full Android
  script was executed on the development host.
- The complete suite contains 19 Node tests and 79 Python tests. Native Windows
  explicitly skips nine Linux-lock cases; WSL runs all Python cases without skips.
- ShellCheck 0.11.0 analyzes all four Android shell files in Bash mode at warning
  severity. This supplements parsing; it does not certify Android shell behavior.
- The shared clean-commit builder validates package metadata, paths, permissions,
  JSON, checksum and manifest. The draft is rebuilt after the audit commit, and
  the hosted CI digest and downloaded draft must match the local artifact.

## Rendered WebUI QA

Playwright used the installed Chrome browser with a temporary loopback preview
and a simulated KernelSU bridge. The Browser plugin was not available; no browser
dependency was installed. The preview server is stopped after the checks.

| Check | Result |
| --- | --- |
| Page identity and meaningful content | Correct title and rendered dashboard |
| Runtime/console health | No application errors, warnings or error overlay |
| Desktop, 1280 x 1000 | Progress error visible, conflicting buttons disabled, automatic retry renders completion and restores controls |
| Mobile, 390 x 844 | Partial profile failure remains visible, selected profile refreshes, no horizontal overflow |
| Screenshots | Retry and completion on desktop, partial-profile error on mobile; captured outside the source checkout |

The tested flow was Maintenance -> Optimize app list -> temporary progress read
failure -> automatic retry -> completion, followed by Profiles -> Gaming ->
simulated persistence failure -> refreshed selection and preserved error message.

## Limits and release disposition

Keep this release a draft prerelease until publication is authorized. These fixes
do not establish that every defect has been eliminated. The maintainer's Pixel has
no root, so Android `/system/bin/sh`, boot/OTA behavior, real sysfs writes, ART,
root-manager mounting, thermal enable/disable across reboot, and performance or
battery outcomes remain unverified. Follow [device acceptance](../RELEASING.md).

The six thermal profiles and static system properties are unchanged. No new
thermal thresholds, charging overrides or stable-profile clock settings were
introduced. A bridge call that never invokes its native callback still requires
real root-manager lifecycle investigation; transient callback errors are covered.
