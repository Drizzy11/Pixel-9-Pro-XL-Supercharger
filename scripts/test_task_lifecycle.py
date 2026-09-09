import os
import shutil
import unittest

from shell_harness import functions_from, run_shell


HAS_FLOCK = os.name != "nt" and shutil.which("flock") is not None

STATE_FUNCTIONS = [
    "write_env_pair", "env_value", "maintenance_status",
    "write_maintenance_state", "app_opt_status", "write_app_opt_state",
    "read_task_status",
]
BACKGROUND_FUNCTIONS = ["start_background_task", "acquire_lock_or_exit", "release_locks", "lock_holder_alive", "set_lock_owner_pid"]
SANDBOX = r'''
MODDIR="$PWD"
MAINT_STATE="$PWD/maintenance.env"
MAINT_PIDFILE="$PWD/maintenance.pid"
MAINT_TASK_LOG="$PWD/maintenance.log"
APP_OPT_STATE="$PWD/apps.env"
APP_OPT_PIDFILE="$PWD/apps.pid"
APP_OPT_LOG="$PWD/apps.log"
MAINT_LOCKDIR="$PWD/.maintenance.lock"
APP_LOCKDIR="$PWD/.apps.lock"
MAINT_ASYNC_LOCKDIR="$PWD/.maintenance_task.lock"
APP_ASYNC_LOCKDIR="$PWD/.app_optimization_task.lock"
ACQUIRED_LOCKS=""
current_boot_id() { echo test-boot; }
write_status() { :; }
log_maintenance() { :; }
'''


class TaskLifecycleTests(unittest.TestCase):
    def assert_shell(self, body, names=STATE_FUNCTIONS):
        if "acquire_lock_or_exit" in names and not HAS_FLOCK:
            self.skipTest("Kernel flock tests require Linux/WSL; run them in CI or WSL")
        result = run_shell(functions_from("bin/supercharger_ctl.sh", names) + SANDBOX + body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_status_poll_does_not_overwrite_a_completion(self):
        # Simulate completion between a liveness observation and the poll's return.
        for kind, state, pid in (("maintenance", "MAINT_STATE", "MAINT_PIDFILE"), ("app_opt", "APP_OPT_STATE", "APP_OPT_PIDFILE")):
            writer = "write_maintenance_state" if kind == "maintenance" else "write_app_opt_state"
            with self.subTest(kind=kind):
                self.assert_shell(f'''
echo "$$" > "${pid}"
{writer} running "Original job" "$$"
kill() {{ {writer} done "Original job" ""; return 0; }}
{kind}_status > poll.txt
[ "$(env_value STATE "${state}")" = done ] || {{ cat "${state}"; exit 1; }}
''')

    def test_state_writers_do_not_clobber_caller_variables(self):
        self.assert_shell(r'''
state=caller-state; label=caller-label; pid=caller-pid; tmp=caller-temp
write_maintenance_state running "Maintenance job" 123
write_app_opt_state done "App job" ""
[ "$state|$label|$pid|$tmp" = 'caller-state|caller-label|caller-pid|caller-temp' ] || {
  echo "$state|$label|$pid|$tmp"; exit 1;
}
''')

    @unittest.skipUnless(HAS_FLOCK, "Kernel flock tests require Linux/WSL")
    def test_fast_workers_keep_their_final_state(self):
        for kind, state, writer, start, operation in (
            ("maintenance", "MAINT_STATE", "write_maintenance_state", "run_maintenance_background", "run_full_maintenance"),
            ("apps", "APP_OPT_STATE", "write_app_opt_state", "run_app_opt_background all", "optimize_all_listed_apps"),
        ):
            with self.subTest(kind=kind):
                names = STATE_FUNCTIONS + BACKGROUND_FUNCTIONS + [start.split()[0]]
                source = functions_from("bin/supercharger_ctl.sh", names)
                source = source.replace(f"{writer}() {{", f"real_{writer}() {{")
                result = run_shell(source + SANDBOX + f'''
{operation}() {{ echo work-complete; return 0; }}
{writer}() {{
  [ "$1" = running ] && sleep 0.3
  real_{writer} "$@"
}}
{start} > start.log
wait
[ "$(env_value STATE "${state}")" = done ] || {{ cat "${state}"; exit 1; }}
''')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_concurrent_launches_run_once_and_preserve_the_job(self):
        for start, operation, state, lock, job_log, label in (
            ("run_maintenance_background", "run_full_maintenance", "MAINT_STATE", "MAINT_ASYNC_LOCKDIR", "MAINT_TASK_LOG", "One-tap maintenance"),
            ("run_app_opt_background all", "optimize_all_listed_apps", "APP_OPT_STATE", "APP_ASYNC_LOCKDIR", "APP_OPT_LOG", "Optimizing listed apps"),
        ):
            with self.subTest(start=start):
                self.assert_shell(f'''
{operation}() {{
  echo executed >> executions
  echo preserved-output
  label=operation-label; pid=operation-pid
  for tick in $(seq 1 200); do
    [ -f release-worker ] && return 0
    sleep 0.02
  done
  return 9
}}
for attempt in 1 2 3 4 5; do
  ({start} > "launch.$attempt"; echo "$?" > "result.$attempt") &
done
wait
[ "$(grep -l '^0$' result.* | wc -l | tr -d ' ')" = 1 ] || {{ cat result.*; exit 1; }}
for tick in $(seq 1 200); do
  [ -f executions ] && break
  sleep 0.02
done
[ "$(wc -l < executions | tr -d ' ')" = 1 ] || exit 2
[ "$(env_value STATE "${state}")" = running ] || {{ cat "${state}"; exit 3; }}
grep -q preserved-output "${job_log}" || exit 4
: > release-worker
for tick in $(seq 1 200); do
  [ ! -d "${lock}" ] && break
  sleep 0.02
done
[ ! -d "${lock}" ] || exit 5
[ "$(env_value STATE "${state}")" = done ] || {{ cat "${state}"; exit 6; }}
[ "$(env_value LABEL "${state}")" = '{label}' ] || exit 7
''', STATE_FUNCTIONS + BACKGROUND_FUNCTIONS + [start.split()[0]])

    def test_empty_lock_is_not_reclaimed_during_owner_publication(self):
        self.assert_shell(r'''
mkdir "$APP_LOCKDIR"
if acquire_lock_or_exit "$APP_LOCKDIR" "App optimization"; then
  echo 'Reclaimed a lock whose creator has not published its PID'; exit 1
fi
[ -d "$APP_LOCKDIR" ] && [ ! -e "$APP_LOCKDIR/pid" ] || exit 2
''', BACKGROUND_FUNCTIONS)

    def test_failed_worker_and_stale_lock_can_be_retried(self):
        self.assert_shell(r'''
mkdir "$APP_ASYNC_LOCKDIR"
printf '99999999\nprevious-boot\n' > "$APP_ASYNC_LOCKDIR/pid"
optimize_all_listed_apps() { echo expected-failure; return 7; }
run_app_opt_background all > launch.log
wait
[ "$(env_value STATE "$APP_OPT_STATE")" = failed ] || { cat "$APP_OPT_STATE"; exit 1; }
[ ! -e "$APP_OPT_PIDFILE" ] && [ ! -d "$APP_ASYNC_LOCKDIR" ] || exit 2
optimize_all_listed_apps() { return 0; }
run_app_opt_background all > retry.log
wait
[ "$(env_value STATE "$APP_OPT_STATE")" = done ] || exit 3
''', STATE_FUNCTIONS + BACKGROUND_FUNCTIONS + ["run_app_opt_background"])

    def test_interruption_is_reported_without_mutating_the_record(self):
        self.assert_shell(r'''
write_app_opt_state running "Lost worker" 99999999
echo 99999999 > "$APP_OPT_PIDFILE"
cp "$APP_OPT_STATE" original-state
app_opt_status > observed-state
[ "$(env_value STATE observed-state)" = interrupted ] || exit 1
[ "$(env_value PID observed-state)" = '' ] || exit 2
cmp original-state "$APP_OPT_STATE" || exit 3
''')

    def test_initialization_failure_does_not_report_a_started_job(self):
        self.assert_shell(r'''
write_app_opt_state() { return 1; }
optimize_all_listed_apps() { touch unexpected-work; }
if run_app_opt_background all > launch.log; then
  echo 'Reported success after state initialization failed'; exit 1
fi
wait
[ ! -e unexpected-work ] || exit 2
[ ! -e "$APP_OPT_PIDFILE" ] && [ ! -d "$APP_ASYNC_LOCKDIR" ] || exit 3
''', STATE_FUNCTIONS + BACKGROUND_FUNCTIONS + ["run_app_opt_background"])

    def test_legacy_recovery_guard_does_not_strand_retries(self):
        self.assert_shell(r'''
mkdir "$APP_LOCKDIR" "$APP_LOCKDIR.reclaim"
printf '99999999\nprevious-boot\n' > "$APP_LOCKDIR/pid"
acquire_lock_or_exit "$APP_LOCKDIR" test || exit 1
release_locks
acquire_lock_or_exit "$APP_LOCKDIR" test || exit 2
release_locks
''', BACKGROUND_FUNCTIONS)

    def test_kernel_guard_is_released_when_reclaimer_dies(self):
        self.assert_shell(r'''
mkdir "$APP_LOCKDIR"
printf '99999999\nprevious-boot\n' > "$APP_LOCKDIR/pid"
(
  flock() {
    command flock "$@" || return
    touch kernel-guard-acquired
    set_lock_owner_pid
    kill -KILL "$LOCK_OWNER_PID"
  }
  acquire_lock_or_exit "$APP_LOCKDIR" test
)
[ "$?" = 1 ] && [ -f kernel-guard-acquired ] || exit 1
acquire_lock_or_exit "$APP_LOCKDIR" test || exit 2
release_locks
''', BACKGROUND_FUNCTIONS)

    def test_competing_stale_recovery_keeps_one_owner(self):
        self.assert_shell(r'''
mkdir "$APP_LOCKDIR"
printf '99999999\nprevious-boot\n' > "$APP_LOCKDIR/pid"
for attempt in 1 2 3 4 5; do
  (
    acquire_lock_or_exit "$APP_LOCKDIR" test
    acquired="$?"
    echo "$acquired" > "result.$attempt"
    if [ "$acquired" = 0 ]; then
      echo won >> winners
      for tick in $(seq 1 200); do
        [ -f release-owner ] && exit 0
        sleep 0.02
      done
      exit 1
    fi
  ) > "attempt.$attempt" &
done
for tick in $(seq 1 200); do
  [ -f winners ] && [ "$(find . -name 'result.*' | wc -l | tr -d ' ')" = 5 ] && break
  sleep 0.02
done
[ "$(find . -name 'result.*' | wc -l | tr -d ' ')" = 5 ] || exit 3
[ "$(wc -l < winners | tr -d ' ')" = 1 ] || exit 1
: > release-owner
wait
[ "$(wc -l < winners | tr -d ' ')" = 1 ] || exit 4
[ ! -d "$APP_LOCKDIR" ] || exit 2
''', BACKGROUND_FUNCTIONS)

    def test_updater_exits_on_termination_signals(self):
        source = functions_from("service.sh", ["start_temp_dashboard_updater"])
        for signal in ("TERM", "HUP"):
            with self.subTest(signal=signal):
                result = run_shell(source + r'''
PIDFILE="$PWD/updater.pid"
LOCKDIR="$PWD/.updater.lock"
TEMP_UPDATE_INTERVAL=0.02
log_line() { :; }
write_updater_record() { echo "$1" > "$PIDFILE"; }
get_battery_temp_decic() { touch loop-ready; }
start_temp_dashboard_updater "" > updater.log 2>&1
child=$!
trap 'kill -KILL "$child" 2>/dev/null; wait "$child" 2>/dev/null' EXIT
# The loop reaches its sensor only after installing its traps.
for tick in $(seq 1 200); do
  [ -f loop-ready ] && break
  sleep 0.01
done
[ -f loop-ready ] || exit 3
kill -''' + signal + r''' "$child"
for tick in $(seq 1 200); do
  kill -0 "$child" 2>/dev/null || break
  sleep 0.01
done
if kill -0 "$child" 2>/dev/null; then
  echo "Updater survived termination"; exit 1
fi
[ ! -e "$PIDFILE" ] && [ ! -d "$LOCKDIR" ] || exit 2
wait "$child" 2>/dev/null
trap - EXIT
exit 0
''')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
