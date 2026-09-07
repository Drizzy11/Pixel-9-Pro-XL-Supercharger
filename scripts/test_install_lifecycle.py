import unittest

from shell_harness import functions_from, run_shell


SANDBOX = r'''
MODPATH="$PWD/module"
MODDIR="$MODPATH"
PERSIST_STATE_DIR="$PWD/persistent"
PROFILE_FILE="$MODPATH/current_profile"
PERSIST_PROFILE_FILE="$PERSIST_STATE_DIR/current_profile"
INTEGRATED_THERMAL_PROFILE_FILE="$MODPATH/thermal_current_profile"
PERSIST_THERMAL_PROFILE_FILE="$PERSIST_STATE_DIR/thermal_current_profile"
PIDFILE="$MODPATH/dashboard_updater.pid"
LOCKDIR="$MODPATH/.dashboard_updater.lock"
THERMAL_REGISTRY_DIR="$PWD/thermal-registry"
THERMAL_REQUEST_ENV="$THERMAL_REGISTRY_DIR/profile_request.env"
mkdir -p "$MODPATH" "$PERSIST_STATE_DIR" "$THERMAL_REGISTRY_DIR"
'''
INSTALL = ["restore_persistent_state", "initialize_module_state"]
UNINSTALL = ["stop_dashboard_updater", "cleanup_uninstall_state"]


class InstallLifecycleTests(unittest.TestCase):
    def check(self, body, *, installer=INSTALL, uninstaller=(), controller=()):
        source = "\n\n".join([
            functions_from("customize.sh", installer),
            functions_from("uninstall.sh", uninstaller),
            functions_from("bin/supercharger_ctl.sh", ["env_value", *controller]),
        ])
        result = run_shell(source + SANDBOX + body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fresh_install_defaults_to_safe_profiles_without_overlay(self):
        self.check(r'''
initialize_module_state
[ "$(cat "$PROFILE_FILE")" = active_smooth ] || exit 1
[ "$(cat "$INTEGRATED_THERMAL_PROFILE_FILE")" = balanced ] || exit 2
[ "$(env_value THERMAL_CONTROL_ENABLED "$MODPATH/thermal_control.env")" = 0 ] || exit 3
[ ! -d "$MODPATH/system/vendor/etc" ] || exit 4
for name in debug.log maintenance.log module_status.env addon_api.env support_snapshot.txt; do
  [ -f "$MODPATH/$name" ] || exit 5
done
''')

    def test_update_restores_all_saved_profile_combinations(self):
        self.check(r'''
for performance in active_smooth performance_gaming; do
  for thermal in balanced gaming charge_cool; do
    save_selected_profile "$performance" || exit 1
    save_integrated_thermal_profile "$thermal"
    # A root-manager update replaces module-local selections with a fresh tree.
    rm -f "$PROFILE_FILE" "$INTEGRATED_THERMAL_PROFILE_FILE"
    initialize_module_state
    [ "$(cat "$PROFILE_FILE")" = "$performance" ] || exit 2
    [ "$(cat "$INTEGRATED_THERMAL_PROFILE_FILE")" = "$thermal" ] || exit 3
    [ "$(env_value THERMAL_CONTROL_ENABLED "$MODPATH/thermal_control.env")" = 0 ] || exit 4
  done
done
''', controller=["ensure_persist_state_dir", "save_selected_profile", "save_integrated_thermal_profile"])

    def test_failed_state_creation_is_not_a_successful_install(self):
        for name in ("current_profile", "thermal_current_profile", "thermal_control.env", "module_status.env", "debug.log"):
            with self.subTest(name=name):
                self.check(r'''
mkdir "$MODPATH/STATE_NAME"
if initialize_module_state >/dev/null 2>error; then
  echo 'Initialization reported success after a required state write failed'; exit 1
fi
[ -s error ] || exit 2
'''.replace("STATE_NAME", name))

    def test_invalid_persisted_values_fall_back_without_evaluation(self):
        self.check(r'''
printf '%s\n' '$(touch injected)' > "$PERSIST_PROFILE_FILE"
printf '%s\n' '../../invalid' > "$PERSIST_THERMAL_PROFILE_FILE"
initialize_module_state
[ "$(cat "$PROFILE_FILE")" = active_smooth ] || exit 1
[ "$(cat "$INTEGRATED_THERMAL_PROFILE_FILE")" = balanced ] || exit 2
[ ! -e injected ] || exit 3
printf 'performance_gaming\r\n' > "$PERSIST_PROFILE_FILE"
printf 'charge_cool\r\n' > "$PERSIST_THERMAL_PROFILE_FILE"
initialize_module_state
[ "$(cat "$PROFILE_FILE")" = performance_gaming ] || exit 4
[ "$(cat "$INTEGRATED_THERMAL_PROFILE_FILE")" = charge_cool ] || exit 5
''')

    def test_reinstall_cleans_stale_locks_and_rotates_the_boot_log(self):
        self.check(r'''
echo old-boot > "$MODPATH/debug.log"
for lock in .dashboard_updater.lock .maintenance.lock .app_optimization.lock .maintenance_task.lock .app_optimization_task.lock; do
  mkdir -p "$MODPATH/$lock"
  echo stale-owner > "$MODPATH/$lock/pid"
done
mkdir -p "$MODPATH/.app_optimization_task.lock.reclaim"
mkdir -p "$MODPATH/system/vendor/etc"
touch "$MODPATH/system/vendor/etc/thermal_info_config.json"
touch "$MODPATH/system/vendor/etc/thermal_info_config_lpm.json"
echo preserve > "$MODPATH/system/vendor/etc/unrelated.conf"
initialize_module_state
[ "$(cat "$MODPATH/debug.previous.log")" = old-boot ] || exit 1
for lock in .dashboard_updater.lock .maintenance.lock .app_optimization.lock .maintenance_task.lock .app_optimization_task.lock .app_optimization_task.lock.reclaim; do
  [ ! -d "$MODPATH/$lock" ] || { echo "Left stale lock: $lock"; exit 2; }
done
[ ! -e "$MODPATH/system/vendor/etc/thermal_info_config.json" ] || exit 3
[ ! -e "$MODPATH/system/vendor/etc/thermal_info_config_lpm.json" ] || exit 4
[ "$(cat "$MODPATH/system/vendor/etc/unrelated.conf")" = preserve ] || exit 5
''')

    def test_uninstall_removes_own_state_and_preserves_external_registry(self):
        self.check(r'''
echo selected > "$PERSIST_PROFILE_FILE"
echo 123 > "$PIDFILE"
mkdir "$LOCKDIR"
echo external-status > "$THERMAL_REGISTRY_DIR/status.env"
echo 'SUPERCHARGER_MODULE_ID="p9pxl_supercharger"' > "$THERMAL_REQUEST_ENV"
cleanup_uninstall_state || { echo 'Uninstall reported failure while preserving external files'; exit 1; }
[ ! -d "$PERSIST_STATE_DIR" ] && [ ! -d "$LOCKDIR" ] && [ ! -f "$PIDFILE" ] || exit 2
[ ! -f "$THERMAL_REQUEST_ENV" ] || exit 3
[ "$(cat "$THERMAL_REGISTRY_DIR/status.env")" = external-status ] || exit 4
''', installer=(), uninstaller=UNINSTALL)

    def test_uninstall_preserves_another_modules_request_and_is_repeatable(self):
        self.check(r'''
echo 'SUPERCHARGER_MODULE_ID="external_module"' > "$THERMAL_REQUEST_ENV"
cp "$THERMAL_REQUEST_ENV" expected-request
cleanup_uninstall_state || exit 1
cleanup_uninstall_state || exit 2
cmp expected-request "$THERMAL_REQUEST_ENV" || exit 3
''', installer=(), uninstaller=UNINSTALL)

    def test_uninstall_handles_an_absent_registry(self):
        self.check(r'''
rmdir "$THERMAL_REGISTRY_DIR"
cleanup_uninstall_state || exit 1
cleanup_uninstall_state || exit 2
''', installer=(), uninstaller=UNINSTALL)

    def test_uninstall_only_signals_a_plausible_pid_from_this_boot(self):
        self.check(r'''
current_boot_id() { echo this-boot; }
# Record the request; never signal a host process in this uninstall test.
kill() { printf '%s\n' "$*" >> signalled; }
for value in 0 1 000 01 invalid -1 ''; do
  printf '%s\nthis-boot\n' "$value" > "$PIDFILE"
  stop_dashboard_updater
done
printf '123\nold-boot\n' > "$PIDFILE"
stop_dashboard_updater
[ ! -e signalled ] || { cat signalled; exit 1; }
printf '123\nthis-boot\n' > "$PIDFILE"
stop_dashboard_updater
[ "$(cat signalled)" = 123 ] || exit 2
''', installer=(), uninstaller=UNINSTALL)

    def test_installer_device_and_magisk_gates(self):
        source = functions_from("customize.sh", ["validate_install_environment"])
        for device, version, ksu, apatch, expected in (
            ("tokay", "30700", "", "", 0), ("caiman", "30700", "", "", 0),
            ("komodo", "30700", "", "", 0), ("comet", "30700", "", "", 0),
            ("unsupported", "30700", "", "", 42), ("tokay", "30600", "", "", 42),
            ("tokay", "", "true", "", 0), ("tokay", "", "", "true", 0),
        ):
            with self.subTest(device=device, version=version, ksu=ksu, apatch=apatch):
                result = run_shell(source + f'''
DEVICE='{device}'; MODEL=fixture; MAGISK_VER_CODE='{version}'; KSU='{ksu}'; APATCH='{apatch}'
ui_print() {{ :; }}
abort() {{ exit 42; }}
validate_install_environment
''')
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
