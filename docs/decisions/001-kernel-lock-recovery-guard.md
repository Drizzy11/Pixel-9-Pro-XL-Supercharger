# ADR-001: Kernel guard for task-lock acquisition and recovery

Status: Accepted

## Context

A process could die after creating a `.reclaim` directory but before removing it.
Every later attempt treated that directory as an active recovery, blocking work
until reboot or manual cleanup. Recovering a recovery-directory lock introduces
the same ownership and publication races recursively.

## Decision

Serialize task-lock acquisition and stale-owner inspection with `flock -n 9` on a
stable `.lock.guard` file. File descriptor 9 exists only in the critical-section
subshell; process exit, including SIGKILL, releases its kernel lock. Do not unlink
the guard file at runtime. Existing directory/PID/boot records retain operation
ownership after the short critical section ends.

`flock` is enabled in the official
[Android 16 Toybox device configuration](https://android.googlesource.com/platform/external/toybox/+/refs/heads/android16-release/config-device).
Refuse the action with an explicit error if the runtime cannot find it; do not
fall back to an unsafe recovery path.

## Consequences

Legacy `.reclaim` directories no longer govern acquisition and remain covered by
boot/install cleanup. Incomplete task owner records still fail closed until that
cleanup; this change addresses recovery guards, not speculative owner recovery.

Real kernel-lock regressions run on Linux/WSL and Ubuntu CI. Native Git Bash skips
those cases because it lacks `flock`; it exercises Windows Job Object containment
instead. Android shell and root-manager validation remains a separate device gate.
