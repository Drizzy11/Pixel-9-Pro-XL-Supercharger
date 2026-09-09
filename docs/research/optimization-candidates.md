# Optimization candidates for Supercharger

Research date: 2026-09-07. Source baseline: `d0369dc` on
`codex/maintenance-validation` (PR #11).

Status: candidates 1-3 now have an implementation following the research below;
candidates 4-6 remain proposals, not a release roadmap. No Pixel performance
measurements were taken.
The maintainer's Pixel currently has no root. Host preparation is possible now;
runtime benefits must be established separately on the target phone.

## Implementation status

- WebUI: one bounded state/log progress response, visibility-aware polling, stale
  response rejection, and reuse of task state already in the full status response.
  A separate boot-metadata cache is not part of this change.
- App inventory: two batched package-manager queries, existing user scopes and
  protected-package exclusions, and a one-minute UI cache with manual refresh,
  visibility-return, and boot/module identity invalidation.
- ART: incremental normal requests, capability-gated background priority and
  verbose results, truthful outcome reporting, and an explicit forced action for
  the selected app. Automatic forced verification fallback is removed.
- The optional deferred battery/thermal queue described below is still a proposal.
  No automatic boot-time job was added.

## Recommended order

| Candidate | Expected improvement to evaluate | Preparation now | Device gate |
| --- | --- | --- | --- |
| 1. Cheaper WebUI polling | Fewer root-bridge calls and hidden-page work | Mocked bridge and visibility tests | Verify root-manager WebView lifecycle |
| 2. Batched app inventory | Faster app-list refresh with fewer shell processes | Package fixtures and invocation counts | Verify package/user semantics |
| 3. Incremental ART maintenance | Avoid redundant compilation and foreground contention | Command-selection and queue tests | ART capabilities, timing, thermal behavior |
| 4. Before/after diagnostics | Identify changes that improve real workloads | Trace configuration and fixture parsers | Capture supported sources on Pixel |
| 5. Stock-aware memory policy | Reduce stalls without unnecessary app reloads | Capability detection and policy fixtures | Rooted A/B memory workloads |
| 6. Bounded Gaming sessions | Improve sustained frame pacing and recovery | Ownership/restore state-machine tests | Rooted sustained-game and thermal sessions |

## 1. Cheaper WebUI polling

**Repository evidence:** [index.mjs](../../webroot/index.mjs) sets
`TASK_POLL_MS=1800`. Each progress poll separately calls the controller for state
and log output. `refreshStatus()` calls `status-quiet` and then two additional
task-state commands. There is no `visibilitychange` listener in the module.

**Proposal:** introduce one bounded progress response containing state and log;
stop UI polling when the document is hidden, then refresh and resume the existing
job when visible. Retain a single in-flight request and reject stale responses.
Keep task execution independent of page visibility. Reuse static boot/device
metadata instead of recomputing it for every full refresh, with invalidation on
boot/module changes and an explicit refresh path.

The [HTML visibility model](https://html.spec.whatwg.org/multipage/interaction.html#page-visibility)
provides the browser lifecycle signal. Actual root-manager WebView delivery must
still be tested. The intended two-to-one bridge-call reduction per progress poll
is an implementation target, not a measured battery or latency improvement.

**Acceptance:** hidden UI creates no new progress calls; reopening resumes one
poller; completing a job while hidden is rendered correctly; measured request
counts fall without losing error or interruption states.

## 2. Batched app inventory

**Repository evidence:** [supercharger_ctl.sh](../../bin/supercharger_ctl.sh)
contains 22 entries in `safe_system_package_candidates`. `list_safe_system_apps`
checks them individually through `is_installed_package` / `pm path`.
`list_optimizable_apps` also uses a temporary file and per-package `grep` calls.
The WebUI reloads the list every time its Maintenance tab is selected.

**Proposal:** collect package inventories once per refresh, intersect the existing
safe allowlist in a single pass, and deduplicate in memory. Cache the result for
the current UI session with explicit refresh and invalidation. Preserve protected
package exclusions and distinguish package-manager failure from an empty list.
Verify user/profile selection before changing how apps are enumerated.

**Acceptance:** identical output for existing fixtures, duplicates, absent apps,
and protected packages; package-manager invocation count bounded independently
of the allowlist length; no stale selection after an explicit refresh.

## 3. Incremental ART maintenance with an optional background queue

**Repository evidence:** both single-app and bulk optimization force
`cmd package compile -m speed-profile -f`, then force `verify` as a fallback.
The module also exposes a separate native background-dexopt job.

**Proposal:** make normal maintenance non-forced and let ART determine whether
work is necessary. Keep forced recompilation as an explicit advanced action.
Probe command help before selecting optional background priority or verbose
result flags. Report performed/skipped/failed and the actual compiler filter when
the platform provides them. Do not treat an unchanged APK version as proof that
runtime profiles have not changed.

For a user-requested deferred queue, check battery/thermal eligibility before the
next package, expose its waiting reason, and support cancellation between apps.
Do not start a hidden boot-time optimization job. Prefer the platform's native
scheduled path where it meets the request rather than duplicating its policies.

The [AOSP ART shell implementation](https://android.googlesource.com/platform/art/+/c7772140ae0e287efed1731a8bb01d4cf78e8daf/libartservice/service/java/com/android/server/art/ArtShellCommand.java)
documents that `-f` can force work even when the requested filter is not better,
and exposes a background priority class. These flags remain capability-gated.
[ART Service configuration](https://source.android.com/docs/core/runtime/configure/art-service)
explains profile-guided compilation, filter fallback, and cancellation of the
scheduled background job at moderate thermal status. A manually invoked compile
command must not be assumed to inherit all scheduled-job constraints.

**Acceptance:** repeated normal requests can skip unnecessary work; failures do
not silently downgrade useful artifacts; heat, CPU time, storage writes, and app
startup measurements are recorded before calling the mode an improvement.

## 4. Before/after diagnostics

**Repository evidence:** current snapshots include device/profile information and
tuning audits, but no PSI-based workload comparison or frame-timing assessment.

**Proposal:** add a manual, bounded capture/report workflow for CPU, memory and
I/O pressure, available zRAM counters, thermal state, and frame timing. Missing
permissions or sources must render as unavailable. Compare the same workload
with the module disabled and enabled, then change one setting at a time.

[PSI](https://docs.kernel.org/accounting/psi.html) reports time lost to resource
pressure. [Perfetto Android tracing](https://perfetto.dev/docs/quickstart/android-tracing)
offers an ADB-based route for baseline collection; available data varies by build
and permissions. [FrameTimeline](https://perfetto.dev/docs/data-sources/frametimeline)
helps diagnose missed frames, but its documented SurfaceView limitation means it
must not be presented as universal game-FPS coverage.

Some baseline traces may be possible on the unrooted Pixel with ADB authorization.
Comparing module behavior still requires root. Current code sets block `iostats=0`,
so verify counter availability before deriving disk-I/O conclusions from them.

**Acceptance:** record build, root manager, profile, refresh rate, app version,
battery/charging state, ambient/starting thermal conditions, and repeat runs in
alternating order. Report distributions and uncertainty, not one best run or a
promised percentage gain. Keep capture overhead visible.

## 5. Stock-aware memory policy

**Repository evidence:** `apply_vm_tuning` in [service.sh](../../service.sh)
preserves stock swappiness in Active Smooth but forces `40` in Performance/Gaming.
The gaming profile also changes dirty ratios and writeback timing. `page-cluster=0`
already exists when swap is active; it is not a new optimization to add.

**Proposal:** inventory stock values and actual swap/zRAM capabilities, then
evaluate retaining stock gaming swappiness before inventing a new fixed value.
Use PSI, reclaim/swap counters and foreground-app reloads to decide whether any
alternative policy is worth adding. Keep VM and dirty-writeback experiments
separate so their effects can be attributed.

The [kernel VM documentation](https://docs.kernel.org/6.15/admin-guide/sysctl/vm.html)
defines swappiness as a relative I/O-cost policy, not a percentage of RAM, and
explicitly allows values above 100 for in-memory swap. This does not establish an
optimal Tensor G4 setting. Android's [LMKD](https://source.android.com/docs/core/perf/lmkd)
already uses memory-pressure information; an extra aggressive cleaner or altered
kill thresholds could work against that policy.

**Acceptance:** rooted, repeated multitasking workloads show lower stalls or
fewer reloads without unacceptable CPU, battery, or storage regression. No
universal swappiness, zRAM size, or compression algorithm is selected by research.

## 6. Bounded Gaming sessions

**Repository evidence:** `apply_gpu_devfreq_policy` may select the `performance`
governor and raise frequency limits. `apply_performance_experimental_tuning`
changes top-app/foreground uclamp values and graphics floors at boot. The current
profile switch is documented as requiring a reboot.

**Proposal:** evaluate an explicitly started/stopped Gaming session that preserves
the vendor governor and applies only measured, temporary changes. Capture original
values with boot/build identity, restore only values still owned by the module,
and define expiration, interruption and recovery. Keep vendor thermal limits
authoritative; do not raise a vendor thermal cap to satisfy a requested boost.

Android's [Thermal API guidance](https://developer.android.com/games/optimize/adpf/thermal)
supports adapting workload to sustainable thermal conditions. Those app/NDK APIs
are not directly callable by the existing shell/WebUI architecture. A reliable
thermal signal needs separate design; battery temperature alone is not thermal
headroom. Do not add a companion APK or continual polling daemon without weighing
its complexity and overhead.

**Acceptance:** longer sessions show better frame-time stability at comparable
thermal/battery cost, and every supported exit path restores owned changes.
Until then this remains an experiment, not a replacement for Active Smooth.

## Scope and handoff

WebUI/inventory overhead and incremental ART are implemented in the maintenance
branch and tracked in `TODO.md`. Prepare the measurement workflow next. Only
promote memory and Gaming changes after real-device A/B evidence; those remain
research candidates rather than confirmed implementation tasks.
