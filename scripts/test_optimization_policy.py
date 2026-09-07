import unittest

from shell_harness import functions_from, run_shell


INVENTORY = ["package_inventory", "list_user_apps", "safe_system_package_candidates",
             "is_blocked_core_package", "list_safe_system_apps", "list_optimizable_apps"]
ART = ["prepare_art_compile", "compile_art_package", "optimize_package_list",
       "optimize_one_app", "is_installed_package", "is_blocked_core_package"]
SANDBOX = r'''
MODDIR="$PWD"
APP_LOCKDIR="$PWD/.apps.lock"
ART_HELP_READY=0
acquire_lock_or_exit() { :; }
release_locks() { :; }
log_maintenance() { :; }
pm() { echo 'Unexpected per-package lookup' >&2; return 99; }
'''
HELP = r'''
  compile [options] PACKAGE
    -m Set the target compiler filter.
    -p Set the priority.
       'PRIORITY_BACKGROUND'.
    -v Verbose mode.
    -f Force compilation.
  clear PACKAGE
'''


class OptimizationPolicyTests(unittest.TestCase):
    def check(self, body, names=ART):
        source = functions_from("bin/supercharger_ctl.sh", names) + SANDBOX
        source += "\ncat > art-help <<'EOF_HELP'\n" + HELP + "EOF_HELP\n"
        result = run_shell(source + body)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_inventory_uses_two_queries_and_keeps_scope_and_exclusions(self):
        self.check(r'''
cmd() {
  echo "$*" >> calls
  case "$*" in
    'package list packages -3') printf '%s\n' package:com.example.user package:com.android.chrome package:com.example.user package:com.android.systemui ;;
    'package list packages --user 0') printf '%s\n' package:com.android.chrome package:com.google.android.gm package:com.example.other ;;
    *) return 99 ;;
  esac
}
list_optimizable_apps > actual || exit 1
printf '%s\n' 'user|com.android.chrome' 'user|com.example.user' 'system|com.google.android.gm' > expected
cmp actual expected || { cat actual; exit 2; }
[ "$(wc -l < calls | tr -d ' ')" = 2 ] || exit 3
''', INVENTORY)

    def test_inventory_failure_never_emits_partial_success(self):
        self.check(r'''
cmd() {
  case "$*" in
    'package list packages -3') echo package:com.example.user ;;
    *) echo 'service unavailable' >&2; return 1 ;;
  esac
}
if list_optimizable_apps > actual 2> error; then exit 1; fi
[ ! -s actual ] && [ -s error ] || exit 2
''', INVENTORY)

    def test_empty_inventory_and_malformed_output_are_distinct(self):
        self.check(r'''
cmd() { :; }
list_optimizable_apps > empty || exit 1
[ ! -s empty ] || exit 2
cmd() { echo 'Error: Unknown option'; }
if list_optimizable_apps > malformed 2>/dev/null; then exit 3; fi
[ ! -s malformed ] || exit 4
''', INVENTORY)

    def test_pm_inventory_fallback_keeps_arguments(self):
        self.check(r'''
command() {
  [ "$1|$2" = '-v|cmd' ] && return 1
  builtin command "$@"
}
pm() { echo "$*" >> calls; echo package:com.example.user; }
list_user_apps > actual || exit 1
[ "$(cat actual)" = com.example.user ] || exit 2
[ "$(cat calls)" = 'list packages -3' ] || exit 3
''', INVENTORY)

    def test_incremental_compile_uses_advertised_priority_without_force(self):
        self.check(r'''
cmd() {
  [ "$*" = 'package help' ] && { cat art-help; return; }
  printf '%s\n' "$*" >> compile-calls
  echo 'Final Status: SKIPPED'
}
compile_art_package com.example.app || exit 1
compile_art_package com.example.app || exit 2
[ "$ART_RESULT" = skipped ] || exit 3
grep -qx 'package compile -m speed-profile -p PRIORITY_BACKGROUND -v com.example.app' compile-calls || exit 4
grep -q ' -f\| -m verify' compile-calls && exit 5
exit 0
''')

    def test_help_is_probed_once_per_batch_and_not_from_other_commands(self):
        self.check(r'''
cmd() {
  if [ "$*" = 'package help' ]; then echo help >> help-calls; cat art-help; return; fi
  echo 'Final Status: PERFORMED'
}
optimize_package_list test 'com.example.one
com.example.two' > result || exit 1
[ "$(wc -l < help-calls | tr -d ' ')" = 1 ] || exit 2
grep -q 'performed: 2' result || exit 3
ART_HELP_READY=0
printf '  compile [options] PACKAGE\n    -m filter\n  other\n    -p PRIORITY_BACKGROUND\n    -v verbose\n    -f force\n' > art-help
prepare_art_compile
[ "$ART_BACKGROUND|$ART_VERBOSE|$ART_FORCE_SUPPORTED" = '0|0|0' ] || exit 4
''')

    def test_unknown_capabilities_keep_minimal_nonforced_command(self):
        self.check(r'''
cmd() {
  [ "$*" = 'package help' ] && return 1
  echo "$*" > compile-call
  echo Success
}
compile_art_package com.example.app || exit 1
[ "$ART_RESULT" = accepted ] || exit 2
[ "$(cat compile-call)" = 'package compile -m speed-profile com.example.app' ] || exit 3
''')

    def test_failure_status_with_zero_exit_code_is_not_success_or_downgraded(self):
        for output in ("Failure", "Final Status: FAILED", "Final Status: CANCELLED"):
            with self.subTest(output=output):
                self.check(r'''
cmd() {
  [ "$*" = 'package help' ] && { cat art-help; return; }
  echo "$*" >> compile-calls
  echo 'OUTPUT'
}
if compile_art_package com.example.app; then exit 1; fi
[ "$ART_RESULT" = failed ] || exit 2
[ "$(wc -l < compile-calls | tr -d ' ')" = 1 ] || exit 3
'''.replace("OUTPUT", output))

    def test_force_is_explicit_and_protected_apps_are_refused(self):
        self.check(r'''
pm() { return 0; }
cmd() {
  [ "$*" = 'package help' ] && { cat art-help; return; }
  echo "$*" >> compile-calls
  echo 'Final Status: PERFORMED'
}
optimize_one_app com.example.app force || exit 1
grep -q ' -f com.example.app$' compile-calls || exit 2
if optimize_one_app com.android.systemui force; then exit 3; fi
[ "$(wc -l < compile-calls | tr -d ' ')" = 1 ] || exit 4
ART_FORCE_SUPPORTED=0
if compile_art_package com.example.other force; then exit 5; fi
[ "$(wc -l < compile-calls | tr -d ' ')" = 1 ] || exit 6
''')

    def test_progress_frames_state_separately_from_bounded_log(self):
        self.check(r'''
APP_OPT_LOG="$PWD/task.log"
app_opt_status() { printf 'STATE="running"\nLABEL="Test job"\n'; }
printf '%50000s' ' ' | tr ' ' x > "$APP_OPT_LOG"
task_progress apps > actual || exit 1
grep -q '^STATE="running"$' actual || exit 2
grep -q '^__SUPERCHARGER_LOG__$' actual || exit 3
[ "$(wc -c < actual)" -lt 17000 ] || exit 4
if task_progress unknown >/dev/null 2>&1; then exit 5; fi
''', ["task_progress"])


if __name__ == "__main__":
    unittest.main()
