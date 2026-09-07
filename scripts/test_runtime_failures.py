"""Failure-path tests using extracted functions and temporary files only."""
import unittest

from shell_harness import functions_from, run_shell


SANDBOX = r'''
MODDIR="$PWD/module"
mkdir -p "$MODDIR/bin"
STATUS_ENV="$MODDIR/module_status.env"
ADDON_API_ENV="$MODDIR/addon_api.env"
SNAPSHOT_FILE="$MODDIR/support_snapshot.txt"
MAINTENANCE_LOG="$MODDIR/maintenance.log"
DEBUG_LOG="$MODDIR/debug.log"
PROP_FILE="$MODDIR/module.prop"
CTL="$MODDIR/bin/supercharger_ctl.sh"
touch "$CTL" "$MODDIR/service.sh" "$PROP_FILE"
log_maintenance() { :; }
'''


class RuntimeFailureTests(unittest.TestCase):
    def check(self, names, body, filename="bin/supercharger_ctl.sh"):
        result = run_shell(functions_from(filename, names) + SANDBOX + body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_repair_reads_quoted_health_without_a_false_warning(self):
        self.check(["repair_dashboard_files", "env_value"], r'''
write_status() { printf 'HEALTH="pass"\nBATTERY_TEMP="30.0C"\n' > "$STATUS_ENV"; }
set_module_description() { echo "$1" > description; }
repair_dashboard_files || exit 1
grep -q 'Profile Active' description || { cat description; exit 2; }
''')

    def test_repair_propagates_status_failure(self):
        self.check(["repair_dashboard_files", "env_value"], r'''
write_status() { return 1; }
set_module_description() { :; }
if repair_dashboard_files > output; then cat output; exit 1; fi
! grep -q '\[PASS\].*refreshed' output || exit 2
''')

    def test_full_maintenance_releases_lock_and_reports_failed_steps(self):
        for failed in ("repair_dashboard_files", "cleanup_updater_state", "write_status", "make_snapshot"):
            with self.subTest(failed=failed):
                self.check(["run_full_maintenance"], r'''
acquire_lock_or_exit() { :; }
release_locks() { touch released; }
repair_dashboard_files() { :; }
cleanup_updater_state() { :; }
write_status() { :; }
verify_active_tuning() { :; }
make_snapshot() { touch "$SNAPSHOT_FILE"; echo "$SNAPSHOT_FILE"; }
check_processes() { :; }
FAILED_STEP() { return 1; }
if run_full_maintenance > output; then cat output; exit 1; fi
[ -f released ] || exit 2
! grep -q '^Done\.' output || exit 3
'''.replace("FAILED_STEP", failed))

    def test_thermal_disable_does_not_claim_removed_files_after_failure(self):
        self.check(["disable_integrated_thermal_control", "remove_integrated_thermal_overlay"], r'''
INTEGRATED_THERMAL_ACTIVE_DIR="$MODDIR/system/vendor/etc"
mkdir -p "$INTEGRATED_THERMAL_ACTIVE_DIR"
touch "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json"
read_integrated_thermal_profile() { echo balanced; }
write_integrated_thermal_state() { touch state-written; }
rm() { return 1; }
if disable_integrated_thermal_control > output; then cat output; exit 1; fi
[ ! -e state-written ] || exit 2
! grep -q 'Thermal Control: disabled' output || exit 3
''')

    def test_thermal_disable_propagates_state_write_failure(self):
        self.check(["disable_integrated_thermal_control"], r'''
read_integrated_thermal_profile() { echo balanced; }
remove_integrated_thermal_overlay() { :; }
write_integrated_thermal_state() { return 1; }
if disable_integrated_thermal_control > output; then cat output; exit 1; fi
''')

    def test_gpu_restore_ignores_a_previous_boot_and_legacy_records(self):
        self.check(["gpu_restore_policy", "gpu_state_current_boot"], r'''
GPU_STATE_FILE="$PWD/gpu-state"
current_boot_id() { echo new-boot; }
log_line() { :; }
record_applied() { :; }
for header in 'boot_id|old-boot' ''; do
  echo vendor-current > "$PWD/governor"
  printf '%s\ngovernor|%s|old-policy\n' "$header" "$PWD/governor" > "$GPU_STATE_FILE"
  gpu_restore_policy
  [ "$(cat "$PWD/governor")" = vendor-current ] || exit 1
done
''', filename="service.sh")

    def test_negative_subdegree_temperature_retains_sign(self):
        self.check(["get_battery_temp"], r'''
safe_read() { echo -5; }
[ "$(get_battery_temp)" = '-0.5C' ] || exit 1
''')

    def test_temperature_parsing_rejects_malformed_and_accepts_decimal_zeroes(self):
        for filename, names, command in (
            ("service.sh", ["normalize_temp_decic", "format_temp_label"], 'format_temp_label "$reading"'),
            ("bin/supercharger_ctl.sh", ["get_battery_temp"], "get_battery_temp"),
        ):
            with self.subTest(filename=filename):
                self.check(names, r'''
safe_read() { echo "$reading"; }
while IFS='|' read -r reading expected; do
  actual="$(COMMAND)"
  [ "$actual" = "$expected" ] || { echo "$reading: $actual != $expected"; exit 1; }
done <<'READINGS'
008|0.8C
-005|-0.5C
-123|-12.3C
0|0.0C
-000|0.0C
300|30.0C
--5|Temp Unavailable
1-2|Temp Unavailable
-|Temp Unavailable
|Temp Unavailable
99999999999999999999|Temp Unavailable
READINGS
'''.replace("COMMAND", command), filename=filename)

    def test_gpu_backup_is_first_value_per_boot_and_restore_is_same_boot_only(self):
        self.check(["gpu_state_current_boot", "gpu_state_has", "gpu_state_save", "gpu_restore_policy"], r'''
GPU_STATE_FILE="$PWD/gpu-state"
BOOT_TOKEN=one
current_boot_id() { echo "$BOOT_TOKEN"; }
log_line() { :; }
record_applied() { :; }
echo stock-one > "$PWD/governor"
gpu_state_save governor "$PWD/governor" stock-one || exit 1
echo performance > "$PWD/governor"
gpu_state_save governor "$PWD/governor" performance || exit 2
gpu_restore_policy
[ "$(cat "$PWD/governor")" = stock-one ] || exit 3
BOOT_TOKEN=two
echo stock-two > "$PWD/governor"
gpu_restore_policy
[ "$(cat "$PWD/governor")" = stock-two ] || exit 4
gpu_state_save governor "$PWD/governor" stock-two || exit 5
! grep -q stock-one "$GPU_STATE_FILE" || exit 6
echo performance > "$PWD/governor"
gpu_restore_policy
[ "$(cat "$PWD/governor")" = stock-two ] || exit 7
''', filename="service.sh")

    def test_gpu_does_not_tune_a_node_without_a_backup(self):
        self.check(["apply_gpu_devfreq_policy"], r'''
mkdir gpu
echo vendor > gpu/governor
safe_read() { cat "$1" 2>/dev/null; }
log_line() { :; }
gpu_state_save() { return 1; }
experimental_write_if_needed() { touch tuned; }
if apply_gpu_devfreq_policy "$PWD/gpu/governor"; then exit 1; fi
[ ! -e tuned ] || exit 2
''', filename="service.sh")

    def test_profile_persistence_failure_is_reported_without_truncating_old_state(self):
        self.check(["save_selected_profile", "ensure_persist_state_dir", "write_selection_file", "commit_state_file"], r'''
PROFILE_FILE="$MODDIR/profile"
PERSIST_STATE_DIR="$PWD/persist"
PERSIST_PROFILE_FILE="$PERSIST_STATE_DIR/profile"
mkdir -p "$PERSIST_PROFILE_FILE"
if save_selected_profile performance_gaming 2> error; then exit 1; fi
[ "$(cat "$PROFILE_FILE")" = performance_gaming ] || exit 2
grep -q 'saved locally' error || exit 3
[ -z "$(ls -A "$PERSIST_PROFILE_FILE")" ] || exit 4
# A failed rename must preserve the existing selection rather than truncate it.
mv() { return 1; }
if write_selection_file "$PROFILE_FILE" active_smooth; then exit 5; fi
[ "$(cat "$PROFILE_FILE")" = performance_gaming ] || exit 6
[ ! -e "$PROFILE_FILE.tmp.$$" ] || exit 7
''')

    def test_status_write_failure_does_not_return_an_old_success_record(self):
        self.check(["write_status", "write_env_pair", "env_value", "commit_state_file"], r'''
for name in ensure_integrated_thermal_state adopt_thermal_control_selection read_selected_profile profile_label_for thermal_profile_for get_profile_mode performance_engine_for detect_root_env get_battery_temp getprop safe_read physical_block_list detect_thermal_addon updater_state maintenance_status app_opt_status current_boot_id integrated_thermal_status; do
  eval "$name() { :; }"
done
has_active_swap() { return 1; }
echo old-success > "$STATUS_ENV"
mv() { return 1; }
if write_status > output; then exit 1; fi
[ ! -s output ] || exit 2
[ "$(cat "$STATUS_ENV")" = old-success ] || exit 3
[ ! -e "$STATUS_ENV.tmp.$$" ] || exit 4
''')

    def test_status_response_keeps_task_state_when_updater_replaces_the_file(self):
        self.check(["write_status", "write_env_pair", "env_value", "commit_state_file"], r'''
for name in ensure_integrated_thermal_state adopt_thermal_control_selection read_selected_profile profile_label_for thermal_profile_for get_profile_mode performance_engine_for detect_root_env get_battery_temp getprop safe_read physical_block_list detect_thermal_addon updater_state current_boot_id integrated_thermal_status; do
  eval "$name() { :; }"
done
has_active_swap() { return 1; }
maintenance_status() { printf 'STATE="running"\nLABEL="Existing maintenance"\n'; }
app_opt_status() { echo 'STATE="idle"'; }
mv() {
  command mv "$@" || return 1
  # Simulate the dashboard updater replacing the file before the controller
  # returns its response. This record intentionally contains no task fields.
  echo 'BATTERY_TEMP="31.0C"' > "$STATUS_ENV"
}
write_status > response || exit 1
[ "$(env_value MAINTENANCE_TASK_STATE response)" = running ] || exit 2
[ "$(env_value TASK_LABEL response)" = 'Existing maintenance' ] || exit 3
''')

    def test_service_writers_reject_directory_destinations(self):
        for function, destination in (("write_module_status_env", "STATUS_ENV"), ("write_addon_api", "ADDON_API_ENV"), ("write_support_snapshot", "SNAPSHOT_FILE")):
            with self.subTest(function=function):
                self.check([function, "write_env_pair", "commit_state_file"], r'''
physical_block_status_fallback() { echo sda; }
emit_integrated_thermal_status() { :; }
detect_thermal_addon() { :; }
write_thermal_request() { :; }
DESTINATION="$PWD/destination"
mkdir "$DESTINATION"
if FUNCTION; then exit 1; fi
[ -z "$(ls -A "$DESTINATION")" ] || exit 2
'''.replace("DESTINATION", destination).replace("FUNCTION", function), filename="service.sh")

    def test_failed_thermal_state_commit_preserves_the_existing_record(self):
        self.check(["write_integrated_thermal_state", "write_env_pair", "commit_state_file"], r'''
INTEGRATED_THERMAL_STATE="$MODDIR/thermal_control.env"
echo 'THERMAL_CONTROL_ENABLED="0"' > "$INTEGRATED_THERMAL_STATE"
valid_integrated_thermal_profile() { :; }
integrated_thermal_available() { :; }
integrated_thermal_overlay_active() { :; }
integrated_thermal_label_for() { echo Balanced; }
save_integrated_thermal_profile() { touch selection-saved; }
mv() { return 1; }
if write_integrated_thermal_state 1 balanced 1 testing; then exit 1; fi
grep -q 'ENABLED="0"' "$INTEGRATED_THERMAL_STATE" || exit 2
[ ! -e selection-saved ] || exit 3
''')

    def test_snapshot_write_failure_preserves_the_previous_snapshot(self):
        self.check(["make_snapshot", "commit_state_file"], r'''
for name in read_selected_profile profile_label_for thermal_profile_for performance_engine_for write_status getprop detect_root_env get_battery_temp safe_read updater_state detect_thermal_addon; do
  eval "$name() { :; }"
done
physical_block_list() { echo 'sda|0'; }
echo old-snapshot > "$SNAPSHOT_FILE"
mv() { return 1; }
if make_snapshot > output; then exit 1; fi
[ ! -s output ] || exit 2
[ "$(cat "$SNAPSHOT_FILE")" = old-snapshot ] || exit 3
[ ! -e "$SNAPSHOT_FILE.tmp.$$" ] || exit 4
''')

    def test_failed_thermal_apply_removes_partial_overlay_and_reports_failure(self):
        for failure in ("copy", "state"):
            with self.subTest(failure=failure):
                self.check(["apply_integrated_thermal_profile", "remove_integrated_thermal_overlay"], r'''
INTEGRATED_THERMAL_ACTIVE_DIR="$MODDIR/system/vendor/etc"
INTEGRATED_THERMAL_PROFILES="$PWD/profiles"
mkdir -p "$INTEGRATED_THERMAL_PROFILES/balanced/vendor/etc"
echo '{}' > "$INTEGRATED_THERMAL_PROFILES/balanced/vendor/etc/thermal_info_config.json"
echo '{}' > "$INTEGRATED_THERMAL_PROFILES/balanced/vendor/etc/thermal_info_config_lpm.json"
valid_integrated_thermal_profile() { :; }
integrated_thermal_available() { :; }
integrated_thermal_label_for() { echo Balanced; }
write_integrated_thermal_state() { [ "$1" = 0 ]; }
FAIL_COPY
if apply_integrated_thermal_profile balanced supercharger > output; then cat output; exit 1; fi
[ ! -e "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" ] || exit 2
[ ! -e "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" ] || exit 3
! grep -q 'Thermal Control: enabled' output || exit 4
'''.replace("FAIL_COPY", 'cp() { return 1; }' if failure == "copy" else ""))


if __name__ == "__main__":
    unittest.main()
