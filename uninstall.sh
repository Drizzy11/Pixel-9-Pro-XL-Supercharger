#!/system/bin/sh
MODDIR="${0%/*}"
PIDFILE="$MODDIR/dashboard_updater.pid"
LOCKDIR="$MODDIR/.dashboard_updater.lock"
PERSIST_STATE_DIR="/data/adb/supercharger_state"
THERMAL_REGISTRY_DIR="/data/adb/supercharger_thermal_control"
THERMAL_REQUEST_ENV="$THERMAL_REGISTRY_DIR/profile_request.env"

current_boot_id() {
  [ -r /proc/sys/kernel/random/boot_id ] || return 0
  tr -d '\r\n' < /proc/sys/kernel/random/boot_id 2>/dev/null
}

stop_dashboard_updater() {
  local pid stamped_boot current_boot
  if [ -f "$PIDFILE" ]; then
    pid="$(head -n 1 "$PIDFILE" 2>/dev/null | tr -d '\r\n')"
    stamped_boot="$(sed -n '2p' "$PIDFILE" 2>/dev/null | tr -d '\r\n')"
    current_boot="$(current_boot_id)"
    case "$pid" in
      ''|*[!0-9]*) ;;
      *)
        # A record from an earlier boot points at a recycled pid, never at our updater.
        if [ "$pid" -gt 1 ] 2>/dev/null && [ -n "$stamped_boot" ] && [ "$stamped_boot" = "$current_boot" ]; then
          kill "$pid" 2>/dev/null
        fi
        ;;
    esac
  fi
}

cleanup_uninstall_state() {
  rm -f "$PIDFILE" 2>/dev/null
  rm -rf "$LOCKDIR" 2>/dev/null
  rm -rf "$PERSIST_STATE_DIR" 2>/dev/null

  # Only drop the thermal request we wrote ourselves; rmdir keeps an external
  # Thermal Control add-on's registry intact because it refuses a non-empty dir.
  if grep -q '^SUPERCHARGER_MODULE_ID="p9pxl_supercharger"' "$THERMAL_REQUEST_ENV" 2>/dev/null; then
    rm -f "$THERMAL_REQUEST_ENV" 2>/dev/null
  fi
  # A missing registry or an external add-on's remaining files are expected.
  rmdir "$THERMAL_REGISTRY_DIR" 2>/dev/null || true
}

stop_dashboard_updater
cleanup_uninstall_state
