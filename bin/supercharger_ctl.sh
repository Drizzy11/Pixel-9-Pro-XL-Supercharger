#!/system/bin/sh

MODDIR="${MODDIR:-/data/adb/modules/p9pxl_supercharger}"
CTL="$MODDIR/bin/supercharger_ctl.sh"
PROP_FILE="$MODDIR/module.prop"
STATUS_ENV="$MODDIR/module_status.env"
ADDON_API_ENV="$MODDIR/addon_api.env"
SNAPSHOT_FILE="$MODDIR/support_snapshot.txt"
MAINTENANCE_LOG="$MODDIR/maintenance.log"
DEBUG_LOG="$MODDIR/debug.log"
PIDFILE="$MODDIR/dashboard_updater.pid"
LOCKDIR="$MODDIR/.dashboard_updater.lock"
MAINT_LOCKDIR="$MODDIR/.maintenance.lock"
APP_LOCKDIR="$MODDIR/.app_optimization.lock"
MAINT_ASYNC_LOCKDIR="$MODDIR/.maintenance_task.lock"
APP_ASYNC_LOCKDIR="$MODDIR/.app_optimization_task.lock"
APP_OPT_LOG="$MODDIR/app_optimization.log"
APP_OPT_STATE="$MODDIR/app_optimization.env"
APP_OPT_PIDFILE="$MODDIR/app_optimization.pid"
ACQUIRED_LOCKS=""
THERMAL_REGISTRY_DIR="/data/adb/supercharger_thermal_control"
THERMAL_STATUS_ENV="$THERMAL_REGISTRY_DIR/status.env"
THERMAL_REQUEST_ENV="$THERMAL_REGISTRY_DIR/profile_request.env"
MAINT_TASK_LOG="$MODDIR/maintenance_task.log"
MAINT_STATE="$MODDIR/maintenance_task.env"
MAINT_PIDFILE="$MODDIR/maintenance_task.pid"
PROFILE_FILE="$MODDIR/current_profile"
INTEGRATED_THERMAL_PROFILES="$MODDIR/thermal_profiles"
INTEGRATED_THERMAL_STATE="$MODDIR/thermal_control.env"
INTEGRATED_THERMAL_PROFILE_FILE="$MODDIR/thermal_current_profile"
PERSIST_STATE_DIR="/data/adb/supercharger_state"
PERSIST_PROFILE_FILE="$PERSIST_STATE_DIR/current_profile"
PERSIST_THERMAL_PROFILE_FILE="$PERSIST_STATE_DIR/thermal_current_profile"
INTEGRATED_THERMAL_ACTIVE_DIR="$MODDIR/system/vendor/etc"
PROFILE_VERSION="$(grep '^version=' "$PROP_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-)"
[ -z "$PROFILE_VERSION" ] && PROFILE_VERSION="unknown"
STATUS_LOG_QUIET="${STATUS_LOG_QUIET:-0}"

log_maintenance() {
  echo "[$(date)] $1" >> "$MAINTENANCE_LOG"
}

safe_read() {
  [ -r "$1" ] && cat "$1" 2>/dev/null
}

set_module_description() {
  desc="$1"
  tmp="${PROP_FILE}.tmp.$$"
  [ -f "$PROP_FILE" ] || return 1
  if awk -v desc="$desc" '
    BEGIN { done = 0 }
    /^description=/ { print "description=" desc; done = 1; next }
    { print }
    END { if (done == 0) print "description=" desc }
  ' "$PROP_FILE" > "$tmp" 2>/dev/null && cat "$tmp" > "$PROP_FILE" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

write_env_pair() {
  local key="$1"
  local value="$(printf "%s" "$2" | tr -d '
')"
  printf '%s="%s"
' "$key" "$value"
}

env_value() {
    local key="$1"
    local file="$2"
    local line=""
    local value=""
    [ -n "$key" ] || return 0
    [ "$file" = "-" ] || [ -r "$file" ] || return 0
    line="$(grep -m 1 "^${key}=" "$file" 2>/dev/null)"
    [ -n "$line" ] || return 0
    value="${line#*=}"
    case "$value" in
        "'"*) value="${value#?}" ;;
        \"*) value="${value#?}" ;;
    esac
    case "$value" in
        *"'") value="${value%?}" ;;
        *\") value="${value%?}" ;;
    esac
    printf "%s" "$value"
}
current_or_unavailable() {
  v="$(safe_read "$1")"
  [ -z "$v" ] && v="Unavailable"
  echo "$v"
}

detect_root_env() {
  if [ -d /data/adb/ksu ] || [ -n "$KSU" ] || [ -n "$KSU_VER" ]; then
    echo "KernelSU"
  elif [ -d /data/adb/ap ] || [ -n "$APATCH" ]; then
    echo "APatch"
  elif [ -d /data/adb/magisk ] || [ -n "$MAGISK_VER" ]; then
    echo "Magisk"
  else
    echo "Unknown"
  fi
}

get_battery_temp() {
  raw="$(safe_read /sys/class/power_supply/battery/temp)"
  case "$raw" in
    ''|*[!0-9-]*) echo "Temp Unavailable" ;;
    *)
      whole=$((raw / 10))
      frac=$((raw % 10))
      [ "$frac" -lt 0 ] && frac=$((frac * -1))
      echo "${whole}.${frac}C"
      ;;
  esac
}

read_selected_profile() {
  value=""
  [ -r "$PROFILE_FILE" ] && value="$(tr -d '
' < "$PROFILE_FILE" 2>/dev/null)"
  case "$value" in
    active_smooth|performance_gaming) echo "$value" ;;
    *) echo "active_smooth" ;;
  esac
}

ensure_persist_state_dir() {
  mkdir -p "$PERSIST_STATE_DIR" 2>/dev/null || return 1
  chmod 0755 "$PERSIST_STATE_DIR" 2>/dev/null || true
  return 0
}

save_selected_profile() {
  profile_value="$1"
  echo "$profile_value" > "$PROFILE_FILE" 2>/dev/null || return 1
  chmod 0644 "$PROFILE_FILE" 2>/dev/null || true
  if ensure_persist_state_dir; then
    echo "$profile_value" > "$PERSIST_PROFILE_FILE" 2>/dev/null || true
    chmod 0644 "$PERSIST_PROFILE_FILE" 2>/dev/null || true
  fi
  return 0
}

profile_label_for() {
  case "$1" in
    performance_gaming) echo "Performance / Gaming" ;;
    *) echo "Active Smooth" ;;
  esac
}

thermal_profile_for() {
  case "$1" in
    performance_gaming) echo "gaming" ;;
    *) echo "balanced" ;;
  esac
}

valid_integrated_thermal_profile() {
  case "$1" in
    balanced|gaming|charge_cool) return 0 ;;
    *) return 1 ;;
  esac
}

integrated_thermal_label_for() {
  case "$1" in
    gaming) echo "Gaming" ;;
    charge_cool) echo "Charge Cool" ;;
    *) echo "Balanced" ;;
  esac
}

integrated_thermal_available() {
  [ -d "$INTEGRATED_THERMAL_PROFILES" ] || return 1
  [ -r "$INTEGRATED_THERMAL_PROFILES/balanced/vendor/etc/thermal_info_config.json" ] || return 1
  [ -r "$INTEGRATED_THERMAL_PROFILES/gaming/vendor/etc/thermal_info_config.json" ] || return 1
  [ -r "$INTEGRATED_THERMAL_PROFILES/charge_cool/vendor/etc/thermal_info_config.json" ] || return 1
  return 0
}

integrated_thermal_enabled() {
  [ "$(env_value THERMAL_CONTROL_ENABLED "$INTEGRATED_THERMAL_STATE")" = "1" ]
}

integrated_thermal_overlay_active() {
  [ -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" ] || return 1
  [ -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" ] || return 1
  return 0
}

read_integrated_thermal_profile() {
  value=""
  [ -r "$INTEGRATED_THERMAL_PROFILE_FILE" ] && value="$(tr -d '\r\n' < "$INTEGRATED_THERMAL_PROFILE_FILE" 2>/dev/null)"
  [ -z "$value" ] && value="$(env_value THERMAL_CONTROL_PROFILE "$INTEGRATED_THERMAL_STATE")"
  valid_integrated_thermal_profile "$value" || value="$(thermal_profile_for "$(read_selected_profile)")"
  valid_integrated_thermal_profile "$value" || value="balanced"
  echo "$value"
}

save_integrated_thermal_profile() {
  thermal_value="$1"
  echo "$thermal_value" > "$INTEGRATED_THERMAL_PROFILE_FILE" 2>/dev/null || true
  chmod 0644 "$INTEGRATED_THERMAL_PROFILE_FILE" 2>/dev/null || true
  if ensure_persist_state_dir; then
    echo "$thermal_value" > "$PERSIST_THERMAL_PROFILE_FILE" 2>/dev/null || true
    chmod 0644 "$PERSIST_THERMAL_PROFILE_FILE" 2>/dev/null || true
  fi
}

write_integrated_thermal_state() {
  enabled="$1"
  profile="$2"
  reboot="$3"
  message="$4"
  valid_integrated_thermal_profile "$profile" || profile="balanced"
  mkdir -p "$MODDIR" 2>/dev/null
  {
    write_env_pair "THERMAL_CONTROL_MERGED" "1"
    write_env_pair "THERMAL_CONTROL_AVAILABLE" "$(integrated_thermal_available && echo 1 || echo 0)"
    write_env_pair "THERMAL_CONTROL_ENABLED" "$enabled"
    write_env_pair "THERMAL_CONTROL_PROFILE" "$profile"
    write_env_pair "THERMAL_CONTROL_LABEL" "$(integrated_thermal_label_for "$profile")"
    write_env_pair "THERMAL_CONTROL_OVERLAY_ACTIVE" "$(integrated_thermal_overlay_active && echo 1 || echo 0)"
    write_env_pair "THERMAL_CONTROL_REBOOT_REQUIRED" "$reboot"
    write_env_pair "THERMAL_CONTROL_MESSAGE" "$message"
    write_env_pair "LAST_UPDATED" "$(date)"
  } > "$INTEGRATED_THERMAL_STATE" 2>/dev/null
  chmod 0644 "$INTEGRATED_THERMAL_STATE" 2>/dev/null
  save_integrated_thermal_profile "$profile"
}

ensure_integrated_thermal_state() {
  integrated_thermal_available || return 0
  [ -r "$INTEGRATED_THERMAL_STATE" ] && return 0
  profile="$(thermal_profile_for "$(read_selected_profile)")"
  write_integrated_thermal_state 0 "$profile" 0 "Off by default for a safe first boot. Enable it after the phone boots normally."
}

remove_integrated_thermal_overlay() {
  rm -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" \
        "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" \
        "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_charge.json" 2>/dev/null || true
  rmdir "$INTEGRATED_THERMAL_ACTIVE_DIR" "$MODDIR/system/vendor" "$MODDIR/system" 2>/dev/null || true
}

apply_integrated_thermal_profile() {
  profile="$1"
  source="${2:-integrated}"
  fail_message=""
  valid_integrated_thermal_profile "$profile" || {
    echo "Invalid thermal profile: $profile"
    echo "Available thermal profiles: balanced, gaming, charge_cool"
    return 1
  }
  if ! integrated_thermal_available; then
    echo "Integrated Thermal Control profiles are not available."
    return 1
  fi

  srcdir="$INTEGRATED_THERMAL_PROFILES/$profile/vendor/etc"
  mkdir -p "$INTEGRATED_THERMAL_ACTIVE_DIR" 2>/dev/null || {
    echo "Could not prepare thermal overlay directory."
    return 1
  }

  fail_apply() {
    fail_message="$1"
    echo "$fail_message"
    remove_integrated_thermal_overlay
    write_integrated_thermal_state 0 "$profile" 1 "Thermal Control was turned off after a failed profile apply. Restart before trying again."
    return 1
  }

  cp -f "$srcdir/thermal_info_config.json" "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" 2>/dev/null || fail_apply "Could not copy thermal_info_config.json." || return 1
  cp -f "$srcdir/thermal_info_config_lpm.json" "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" 2>/dev/null || fail_apply "Could not copy thermal_info_config_lpm.json." || return 1
  rm -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_charge.json" 2>/dev/null || true
  chmod 0644 "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" 2>/dev/null || true

  if ! cmp -s "$srcdir/thermal_info_config.json" "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json"; then
    fail_apply "Thermal profile verification failed: thermal_info_config.json"
    return 1
  fi
  if ! cmp -s "$srcdir/thermal_info_config_lpm.json" "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json"; then
    fail_apply "Thermal profile verification failed: thermal_info_config_lpm.json"
    return 1
  fi

  if [ "$source" = "integrated" ]; then
    if mkdir -p "$THERMAL_REGISTRY_DIR" 2>/dev/null; then
      {
        write_env_pair "SUPERCHARGER_MODULE_ID" "p9pxl_supercharger"
        write_env_pair "SUPERCHARGER_THERMAL_PROFILE_REQUEST" "$profile"
        write_env_pair "THERMAL_REQUEST_SOURCE" "integrated"
        write_env_pair "LAST_UPDATED" "$(date)"
      } > "$THERMAL_REQUEST_ENV" 2>/dev/null
      chmod 0644 "$THERMAL_REQUEST_ENV" 2>/dev/null
    fi
  fi

  write_integrated_thermal_state 1 "$profile" 1 "Thermal Control enabled. Restart to apply the selected thermal profile."
  echo "Thermal Control: enabled"
  echo "Thermal profile: $(integrated_thermal_label_for "$profile")"
  echo "Restart required to apply the selected thermal profile."
}

disable_integrated_thermal_control() {
  profile="$(read_integrated_thermal_profile)"
  remove_integrated_thermal_overlay
  write_integrated_thermal_state 0 "$profile" 1 "Thermal Control disabled. Restart to return to ROM/vendor thermal behavior."
  echo "Thermal Control: disabled"
  echo "Thermal overlay files removed from the module."
  echo "Restart required to return to ROM/vendor thermal behavior."
}

integrated_thermal_status() {
  ensure_integrated_thermal_state
  profile="$(read_integrated_thermal_profile)"
  enabled=0
  integrated_thermal_enabled && enabled=1
  available=0
  integrated_thermal_available && available=1
  overlay=0
  integrated_thermal_overlay_active && overlay=1
  reboot="$(env_value THERMAL_CONTROL_REBOOT_REQUIRED "$INTEGRATED_THERMAL_STATE")"
  [ -z "$reboot" ] && reboot=0
  message="$(env_value THERMAL_CONTROL_MESSAGE "$INTEGRATED_THERMAL_STATE")"
  [ -z "$message" ] && message="Off by default for a safe first boot. Enable it after the phone boots normally."
  write_env_pair "THERMAL_CONTROL_MERGED" "1"
  write_env_pair "THERMAL_CONTROL_AVAILABLE" "$available"
  write_env_pair "THERMAL_CONTROL_ENABLED" "$enabled"
  write_env_pair "THERMAL_CONTROL_PROFILE" "$profile"
  write_env_pair "THERMAL_CONTROL_LABEL" "$(integrated_thermal_label_for "$profile")"
  write_env_pair "THERMAL_CONTROL_OVERLAY_ACTIVE" "$overlay"
  write_env_pair "THERMAL_CONTROL_REBOOT_REQUIRED" "$reboot"
  write_env_pair "THERMAL_CONTROL_MESSAGE" "$message"
}

adopt_thermal_control_selection() {
  local request_env="$THERMAL_REQUEST_ENV"
  local status_env="$THERMAL_REGISTRY_DIR/status.env"
  local source=""
  local requested=""
  local mapped=""

  [ -r "$request_env" ] && source="$(env_value THERMAL_REQUEST_SOURCE "$request_env")"
  [ -r "$request_env" ] && requested="$(env_value SUPERCHARGER_THERMAL_PROFILE_REQUEST "$request_env")"

  if [ "$source" = "thermal_control" ]; then
    case "$requested" in
      gaming) mapped="performance_gaming" ;;
      balanced) mapped="active_smooth" ;;
    esac
  fi

  [ -n "$mapped" ] || return 0
  if [ "$(read_selected_profile)" != "$mapped" ]; then
    save_selected_profile "$mapped" || return 0
  fi
}

performance_engine_for() {
  case "$1" in
    performance_gaming) echo "experimental" ;;
    *) echo "stable" ;;
  esac
}

get_profile_mode() {
  selected="$(read_selected_profile)"
  if [ "$selected" = "performance_gaming" ]; then
    echo "Performance / Gaming"
    return 0
  fi
  sdk="$(getprop ro.build.version.sdk)"
  case "$sdk" in
    37|3[7-9]|[4-9][0-9]) echo "Android 17 Active Smooth" ;;
    36) echo "Android 16 Active Smooth" ;;
    *) echo "Pixel 9 Active Smooth" ;;
  esac
}

thermal_module_bases() {
  echo "/data/adb/modules /data/adb/modules_update /data/adb/ksu/modules /data/adb/ksu/modules_update /data/adb/ap/modules /data/adb/ap/modules_update"
}

thermal_addon_dir() {
  if [ -r "$THERMAL_STATUS_ENV" ]; then
    reg_dir="$(env_value MODULE_DIR "$THERMAL_STATUS_ENV")"
    [ -n "$reg_dir" ] && [ -d "$reg_dir" ] && { echo "$reg_dir"; return 0; }
  fi

  known_ids="supercharger_thermal_control supercharger_thermal_control_addon supercharger_thermal supercharger_thermal_addon p9pxl_thermal_control pixel9_thermal_control thermal_control_supercharger"
  for base in $(thermal_module_bases); do
    [ -d "$base" ] || continue

    for id in $known_ids; do
      direct="$base/$id"
      if [ -d "$direct" ]; then
        echo "$direct"
        return 0
      fi
    done

    for dir in "$base"/*; do
      [ -d "$dir" ] || continue
      prop="$dir/module.prop"
      if [ -r "$prop" ]; then
        id_line="$(grep -im1 '^id=' "$prop" 2>/dev/null | cut -d= -f2-)"
        name_line="$(grep -im1 '^name=' "$prop" 2>/dev/null | cut -d= -f2-)"
        ident="$(printf '%s %s' "$id_line" "$name_line" | tr 'A-Z' 'a-z')"
        case "$ident" in
          *supercharger*thermal*control*|*supercharger*thermal*addon*|*pixel*thermal*control*|*thermal*control*supercharger*)
            echo "$dir"
            return 0
            ;;
        esac
      fi
      if [ -r "$dir/bin/switch_profile.sh" ] && [ -r "$dir/bin/profile_lib.sh" ]; then
        if grep -qi 'thermal' "$dir/bin/profile_lib.sh" "$dir/bin/switch_profile.sh" 2>/dev/null; then
          echo "$dir"
          return 0
        fi
      fi
    done
  done
  return 1
}

thermal_addon_state_label() {
  addon_dir="$1"
  case "$addon_dir" in
    /data/adb/modules_update/*|/data/adb/ksu/modules_update/*|/data/adb/ap/modules_update/*) echo "pending reboot"; return 0 ;;
  esac
  if [ -f "$addon_dir/remove" ]; then
    echo "pending removal"
  elif [ -f "$addon_dir/disable" ]; then
    echo "disabled"
  else
    echo "active"
  fi
}

write_thermal_request() {
  local target source current_target
  target="$1"
  if [ "${SUPERCHARGER_FORCE_THERMAL_REQUEST:-0}" != "1" ]; then
    source="$(env_value THERMAL_REQUEST_SOURCE "$THERMAL_REQUEST_ENV")"
    current_target="$(env_value SUPERCHARGER_THERMAL_PROFILE_REQUEST "$THERMAL_REQUEST_ENV")"
    case "$source" in
      thermal_control|integrated)
        [ "$current_target" = "charge_cool" ] && return 0
        ;;
    esac
  fi
  if mkdir -p "$THERMAL_REGISTRY_DIR" 2>/dev/null; then
    {
      write_env_pair "SUPERCHARGER_MODULE_ID" "p9pxl_supercharger"
      write_env_pair "SUPERCHARGER_THERMAL_PROFILE_REQUEST" "$target"
      write_env_pair "THERMAL_REQUEST_SOURCE" "supercharger"
      write_env_pair "LAST_UPDATED" "$(date)"
    } > "$THERMAL_REQUEST_ENV" 2>/dev/null
    chmod 0644 "$THERMAL_REQUEST_ENV" 2>/dev/null
  fi
}

sync_thermal_addon_profile() {
  target="$1"
  SUPERCHARGER_FORCE_THERMAL_REQUEST=1 write_thermal_request "$target"
  if integrated_thermal_available; then
    if integrated_thermal_enabled; then
      apply_integrated_thermal_profile "$target" "supercharger"
      return $?
    fi
    echo "Thermal Control: integrated but off. Enable it after confirming the phone boots normally."
    return 0
  fi

  addon_dir="$(thermal_addon_dir)"
  if [ -z "$addon_dir" ]; then
    echo "Thermal Control: not installed"
    return 0
  fi

  addon_state="$(thermal_addon_state_label "$addon_dir")"
  case "$addon_state" in
    active) : ;;
    *) echo "Thermal Control: installed ($addon_state), profile request queued"; return 0 ;;
  esac

  switcher="$addon_dir/bin/switch_profile.sh"
  if [ ! -r "$switcher" ]; then
    echo "Thermal Control: installed, switch tool unavailable"
    return 0
  fi

  MODDIR="$addon_dir" sh "$switcher" "$target"
  return $?
}

set_supercharger_profile() {
  target="$1"
  sync_output=""
  sync_status=0
  case "$target" in
    active_smooth|performance_gaming) : ;;
    *)
      echo "Invalid profile: $target"
      echo "Available profiles: active_smooth, performance_gaming"
      return 1
      ;;
  esac
  label="$(profile_label_for "$target")"
  thermal="$(thermal_profile_for "$target")"
  save_selected_profile "$target" || return 1
  echo "Selected profile: $label"
  echo "Supercharger profile ID: $target"
  echo "Thermal profile target: $thermal"
  sync_output="$(sync_thermal_addon_profile "$thermal" 2>&1)"
  sync_status=$?
  [ -n "$sync_output" ] && printf '%s\n' "$sync_output"
  STATUS_LOG_QUIET=1 write_status >/dev/null 2>&1
  if [ "$sync_status" -ne 0 ]; then
    echo "Thermal Control: sync warning (exit $sync_status)"
    echo "Supercharger profile was saved, but the thermal profile switch did not complete."
    log_maintenance "profile selected with thermal sync warning: $target thermal_target=$thermal rc=$sync_status"
  fi
  log_maintenance "profile selected: $target thermal_target=$thermal"
  echo "Profile saved. Restart before judging performance."
}

profile_status() {
  selected="$(read_selected_profile)"
  label="$(profile_label_for "$selected")"
  thermal="$(thermal_profile_for "$selected")"
  write_env_pair "SELECTED_PROFILE" "$selected"
  write_env_pair "PROFILE_LABEL" "$label"
  write_env_pair "PROFILE_MODE" "$(get_profile_mode)"
  write_env_pair "THERMAL_PROFILE_REQUEST" "$thermal"
  write_env_pair "PERFORMANCE_ENGINE_STATE" "$(performance_engine_for "$selected")"
}

list_profiles() {
  echo "active_smooth|Active Smooth|balanced|stable"
  echo "performance_gaming|Performance / Gaming|gaming|experimental"
}

has_active_swap() {
  [ -r /proc/swaps ] || return 1
  while read -r line; do
    case "$line" in
      Filename*|'') continue ;;
      *) return 0 ;;
    esac
  done < /proc/swaps
  return 1
}

detect_thermal_addon() {
  if integrated_thermal_available; then
    enabled="off"
    integrated_thermal_enabled && enabled="on"
    echo "1|integrated ($enabled)"
    return 0
  fi

  addon_dir="$(thermal_addon_dir)"
  if [ -n "$addon_dir" ]; then
    addon_version="$(grep -im1 '^version=' "$addon_dir/module.prop" 2>/dev/null | cut -d= -f2-)"
    [ -z "$addon_version" ] && addon_version="installed"
    addon_state="$(thermal_addon_state_label "$addon_dir")"
    case "$addon_state" in
      active) echo "1|$addon_version" ;;
      *) echo "1|$addon_version ($addon_state)" ;;
    esac
    return 0
  fi

  if [ -r "$THERMAL_STATUS_ENV" ]; then
    reg_installed="$(env_value THERMAL_CONTROL_INSTALLED "$THERMAL_STATUS_ENV")"
    reg_version="$(env_value THERMAL_CONTROL_VERSION "$THERMAL_STATUS_ENV")"
    reg_state="$(env_value THERMAL_CONTROL_STATE "$THERMAL_STATUS_ENV")"
    if [ "$reg_installed" = "1" ] || [ -n "$reg_version" ]; then
      [ -z "$reg_version" ] && reg_version="installed"
      case "$reg_state" in
        ''|active) echo "1|$reg_version" ;;
        *) echo "1|$reg_version ($reg_state)" ;;
      esac
      return 0
    fi
  fi

  echo "0|none"
}

current_boot_id() {
  [ -r /proc/sys/kernel/random/boot_id ] || return 0
  tr -d '\r\n' < /proc/sys/kernel/random/boot_id 2>/dev/null
}

read_updater_pid() {
  head -n 1 "$PIDFILE" 2>/dev/null | tr -d '\r\n'
}

updater_record_alive() {
  local pid="$1"
  local stamped
  local current

  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  stamped="$(sed -n '2p' "$PIDFILE" 2>/dev/null | tr -d '\r\n')"
  current="$(current_boot_id)"
  [ -n "$stamped" ] && [ -n "$current" ] && [ "$stamped" = "$current" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

updater_state() {
  if [ ! -f "$PIDFILE" ]; then
    echo "none|stopped"
    return 0
  fi
  pid="$(read_updater_pid)"
  case "$pid" in
    ''|*[!0-9]*) echo "invalid|stale" ;;
    *)
      if updater_record_alive "$pid"; then
        echo "$pid|running"
      else
        echo "$pid|stale"
      fi
      ;;
  esac
}

append_block_name() {
  name="$1"
  [ -n "$name" ] || return 0
  case "$name" in
    dm-*|loop*|ram*|zram*|md*|sr*|fd*|*[!A-Za-z0-9._-]*) return 0 ;;
  esac
  case ", $list, " in
    *", $name, "*) return 0 ;;
  esac
  if [ -z "$list" ]; then list="$name"; else list="$list, $name"; fi
}

parse_block_names_from_text() {
  list=""
  text="$1"
  words="$(printf '%s\n' "$text" | sed 's/[^A-Za-z0-9._-]/ /g')"
  for token in $words; do
    token="$(printf "%s" "$token" | sed 's/[^A-Za-z0-9._-]//g')"
    case "$token" in
      sd[a-z]|sd[a-z][a-z]|mmcblk[0-9]*|nvme[0-9]n[0-9]*) append_block_name "$token" ;;
    esac
  done
  printf "%s" "$list"
}
pixel_ufs_default_blocks() {
  devname="$(getprop ro.product.device 2>/dev/null)"
  [ -z "$devname" ] && devname="$(getprop ro.product.vendor.device 2>/dev/null)"
  [ -z "$devname" ] && devname="$(getprop ro.boot.hardware.sku 2>/dev/null)"
  case "$devname" in
    komodo|caiman|tokay|comet)
      echo "sda, sdb, sdc, sdd"
      return 0
      ;;
  esac
  return 1
}
physical_block_log_fallback() {
  for f in "$DEBUG_LOG" "$MODDIR/debug.previous.log" "$SNAPSHOT_FILE" "$STATUS_ENV"; do
    [ -r "$f" ] || continue
    text="$(grep -i -E 'physical block devices|audited block devices|block verify|block device|block io stats' "$f" 2>/dev/null | tail -n 120)"
    [ -n "$text" ] || continue
    parsed="$(parse_block_names_from_text "$text")"
    case "$parsed" in
      ''|'none'|'unknown'|'Not reported') continue ;;
      *) echo "$parsed"; return 0 ;;
    esac
  done
  pixel_ufs_default_blocks
}

physical_block_list() {
  list=""
  skipped=0

  for dev in /sys/block/*; do
    [ -d "$dev" ] || continue
    base="$(basename "$dev")"
    case "$base" in
      dm-*|loop*|ram*|zram*|md*|sr*|fd*) skipped=$((skipped + 1)); continue ;;
    esac
    [ -d "$dev/queue" ] || { skipped=$((skipped + 1)); continue; }

    case "$base" in
      sd[a-z]|sd[a-z][a-z]|mmcblk[0-9]*|nvme[0-9]n[0-9]*)
        append_block_name "$base"
        ;;
      *)
        if [ -e "$dev/device" ] || [ -L "$dev/device" ]; then
          append_block_name "$base"
        else
          skipped=$((skipped + 1))
        fi
        ;;
    esac
  done

  if [ -z "$list" ] || [ "$list" = "none" ]; then
    log_list="$(physical_block_log_fallback 2>/dev/null)"
    case "$log_list" in
      ''|'none'|'unknown') : ;;
      *) list="$log_list" ;;
    esac
  fi

  case "$list" in
    ''|'none'|'unknown'|'Not reported')
      pixel_default="$(pixel_ufs_default_blocks 2>/dev/null)"
      [ -n "$pixel_default" ] && list="$pixel_default"
      ;;
  esac
  [ -z "$list" ] && list="none"
  echo "$list|$skipped"
}

write_status() {
  ensure_integrated_thermal_state
  adopt_thermal_control_selection
  selected_profile="$(read_selected_profile)"
  profile_label="$(profile_label_for "$selected_profile")"
  thermal_request="$(thermal_profile_for "$selected_profile")"
  profile_mode="$(get_profile_mode)"
  performance_engine="$(performance_engine_for "$selected_profile")"
  root_env="$(detect_root_env)"
  battery_temp="$(get_battery_temp)"
  android_release="$(getprop ro.build.version.release)"
  android_sdk="$(getprop ro.build.version.sdk)"
  build_id="$(getprop ro.build.id)"
  build_incremental="$(getprop ro.build.version.incremental)"
  kernel_release="$(uname -r 2>/dev/null)"
  device="$(getprop ro.product.device 2>/dev/null)"
  [ -z "$device" ] && device="$(getprop ro.product.vendor.device 2>/dev/null)"
  [ -z "$device" ] && device="$(getprop ro.boot.hardware.sku 2>/dev/null)"
  model="$(getprop ro.product.model 2>/dev/null)"
  swap_active=0
  has_active_swap && swap_active=1
  page_cluster="$(safe_read /proc/sys/vm/page-cluster)"
  [ -z "$page_cluster" ] && page_cluster="Unavailable"
  block_info="$(physical_block_list)"
  block_list="${block_info%%|*}"
  skipped_blocks="${block_info#*|}"
  addon_info="$(detect_thermal_addon)"
  addon_installed="${addon_info%%|*}"
  addon_version="${addon_info#*|}"
  updater_info="$(updater_state)"
  updater_pid="${updater_info%%|*}"
  updater_status="${updater_info#*|}"

  # Status reads must never rewrite a worker's newer completion record.
  local maintenance_snapshot="$(maintenance_status)"
  local app_snapshot="$(app_opt_status)"
  maintenance_task_state="$(printf '%s\n' "$maintenance_snapshot" | env_value STATE -)"
  maintenance_task_label="$(printf '%s\n' "$maintenance_snapshot" | env_value LABEL -)"
  maintenance_task_pid="$(printf '%s\n' "$maintenance_snapshot" | env_value PID -)"
  app_opt_task_state="$(printf '%s\n' "$app_snapshot" | env_value STATE -)"
  app_opt_task_label="$(printf '%s\n' "$app_snapshot" | env_value LABEL -)"
  app_opt_task_pid="$(printf '%s\n' "$app_snapshot" | env_value PID -)"

  task_state="idle"
  task_label="No maintenance task running"
  if [ "$maintenance_task_state" = "running" ]; then
    task_state="running"
    task_label="$maintenance_task_label"
  elif [ "$app_opt_task_state" = "running" ]; then
    task_state="running"
    task_label="$app_opt_task_label"
  fi

  health="pass"
  if grep -q '\[FAIL\]' "$DEBUG_LOG" 2>/dev/null; then
    health="warn"
  fi

  status_tmp="$STATUS_ENV.tmp.$$"
  api_tmp="$ADDON_API_ENV.tmp.$$"

  {
    write_env_pair "BOOT_ID" "$(current_boot_id)"
    write_env_pair "MODULE_ID" "p9pxl_supercharger"
    write_env_pair "VERSION" "$PROFILE_VERSION"
    write_env_pair "STATUS" "Manual Refresh"
    write_env_pair "HEALTH" "$health"
    write_env_pair "PROFILE_MODE" "$profile_mode"
    write_env_pair "SELECTED_PROFILE" "$selected_profile"
    write_env_pair "PROFILE_LABEL" "$profile_label"
    write_env_pair "THERMAL_PROFILE_REQUEST" "$thermal_request"
    write_env_pair "PERFORMANCE_ENGINE_STATE" "$performance_engine"
    write_env_pair "ANDROID_RELEASE" "$android_release"
    write_env_pair "ANDROID_SDK" "$android_sdk"
    write_env_pair "BUILD_ID" "$build_id"
    write_env_pair "BUILD_INCREMENTAL" "$build_incremental"
    write_env_pair "KERNEL_RELEASE" "$kernel_release"
    write_env_pair "ROOT_ENV" "$root_env"
    write_env_pair "DEVICE" "$device"
    write_env_pair "MODEL" "$model"
    write_env_pair "BATTERY_TEMP" "$battery_temp"
    write_env_pair "SWAP_ACTIVE" "$swap_active"
    write_env_pair "PAGE_CLUSTER_STATUS" "$page_cluster"
    write_env_pair "BLOCK_AUDITED_LIST" "$block_list"
    write_env_pair "BLOCK_SKIPPED_COUNT" "$skipped_blocks"
    write_env_pair "NETWORK_CAPABILITY_SUMMARY" "qdisc=$(safe_read /proc/sys/net/core/default_qdisc), cc=$(safe_read /proc/sys/net/ipv4/tcp_congestion_control), fastopen=$(safe_read /proc/sys/net/ipv4/tcp_fastopen)"
    write_env_pair "THERMAL_ADDON_INSTALLED" "$addon_installed"
    write_env_pair "THERMAL_ADDON_VERSION" "$addon_version"
    integrated_thermal_status
    write_env_pair "DASHBOARD_UPDATER_PID" "$updater_pid"
    write_env_pair "DASHBOARD_UPDATER_STATE" "$updater_status"
    write_env_pair "TASK_STATE" "$task_state"
    write_env_pair "TASK_LABEL" "$task_label"
    write_env_pair "MAINTENANCE_TASK_STATE" "$maintenance_task_state"
    write_env_pair "MAINTENANCE_TASK_LABEL" "$maintenance_task_label"
    write_env_pair "MAINTENANCE_TASK_PID" "$maintenance_task_pid"
    write_env_pair "APP_OPT_TASK_STATE" "$app_opt_task_state"
    write_env_pair "APP_OPT_TASK_LABEL" "$app_opt_task_label"
    write_env_pair "APP_OPT_TASK_PID" "$app_opt_task_pid"
    write_env_pair "LOG_FILE" "$DEBUG_LOG"
    write_env_pair "SNAPSHOT_FILE" "$SNAPSHOT_FILE"
    write_env_pair "LAST_UPDATED" "$(date)"
  } > "$status_tmp"
  chmod 0644 "$status_tmp" 2>/dev/null
  mv -f "$status_tmp" "$STATUS_ENV" 2>/dev/null

  {
    write_env_pair "API_VERSION" "1"
    write_env_pair "SUPERCHARGER_VERSION" "$PROFILE_VERSION"
    write_env_pair "SUPERCHARGER_MODULE_ID" "p9pxl_supercharger"
    write_env_pair "SUPERCHARGER_MODULE_DIR" "$MODDIR"
    write_env_pair "SUPERCHARGER_PROFILE_MODE" "$profile_mode"
    write_env_pair "SUPERCHARGER_ACTIVE_PROFILE" "$selected_profile"
    write_env_pair "SUPERCHARGER_PROFILE_LABEL" "$profile_label"
    write_env_pair "SUPERCHARGER_THERMAL_PROFILE_REQUEST" "$thermal_request"
    write_env_pair "SUPERCHARGER_PERFORMANCE_ENGINE_STATE" "$performance_engine"
    write_env_pair "SUPERCHARGER_HEALTH" "$health"
    write_env_pair "ANDROID_RELEASE" "$android_release"
    write_env_pair "ANDROID_SDK" "$android_sdk"
    write_env_pair "DEVICE" "$device"
    write_env_pair "MODEL" "$model"
    write_env_pair "ROOT_ENV" "$root_env"
    write_env_pair "THERMAL_ADDON_INSTALLED" "$addon_installed"
    write_env_pair "THERMAL_ADDON_VERSION" "$addon_version"
    integrated_thermal_status
    write_env_pair "LAST_UPDATED" "$(date)"
  } > "$api_tmp"
  chmod 0644 "$api_tmp" 2>/dev/null
  mv -f "$api_tmp" "$ADDON_API_ENV" 2>/dev/null

  [ "$STATUS_LOG_QUIET" = "1" ] || log_maintenance "status refresh completed"
  cat "$STATUS_ENV" 2>/dev/null
}

make_snapshot() {
  selected_profile="$(read_selected_profile)"
  profile_label="$(profile_label_for "$selected_profile")"
  thermal_request="$(thermal_profile_for "$selected_profile")"
  write_status >/dev/null 2>&1
  block_info="$(physical_block_list)"
  block_list="${block_info%%|*}"
  case "$block_list" in
    ''|'none'|'unknown'|'Not reported')
      parsed_blocks="$(grep -ihE 'physical block devices|audited block devices|block verify|block io stats' "$DEBUG_LOG" "$MODDIR/debug.previous.log" 2>/dev/null | tail -n 160 | while IFS= read -r line; do parse_block_names_from_text "$line"; echo; done | sed '/^$/d' | tail -n 1)"
      [ -n "$parsed_blocks" ] && block_list="$parsed_blocks"
      ;;
  esac
  case "$block_list" in
    ''|'none'|'unknown'|'Not reported')
      pixel_default="$(pixel_ufs_default_blocks 2>/dev/null)"
      [ -n "$pixel_default" ] && block_list="$pixel_default"
      ;;
  esac
  [ -z "$block_list" ] && block_list="none"
  {
    echo "Supercharger Support Snapshot"
    echo "Generated: $(date)"
    echo "Version: $PROFILE_VERSION"
    echo "Selected Profile: $selected_profile"
    echo "Profile Label: $profile_label"
    echo "Thermal Profile Request: $thermal_request"
    echo "Performance Engine: $(performance_engine_for "$selected_profile")"
    echo "Android Release: $(getprop ro.build.version.release)"
    echo "SDK: $(getprop ro.build.version.sdk)"
    echo "Build ID: $(getprop ro.build.id)"
    echo "Incremental: $(getprop ro.build.version.incremental)"
    echo "Kernel: $(uname -r 2>/dev/null)"
    echo "Root Environment: $(detect_root_env)"
    echo "Model: $(getprop ro.product.model)"
    echo "Codename: $(getprop ro.product.device)"
    echo "Battery Temp: $(get_battery_temp)"
    echo "VM vfs_cache_pressure: $(safe_read /proc/sys/vm/vfs_cache_pressure)"
    echo "VM dirty_background_ratio: $(safe_read /proc/sys/vm/dirty_background_ratio)"
    echo "VM dirty_ratio: $(safe_read /proc/sys/vm/dirty_ratio)"
    echo "VM swappiness: $(safe_read /proc/sys/vm/swappiness)"
    echo "VM page-cluster: $(safe_read /proc/sys/vm/page-cluster)"
    echo "Network qdisc: $(safe_read /proc/sys/net/core/default_qdisc)"
    echo "TCP congestion: $(safe_read /proc/sys/net/ipv4/tcp_congestion_control)"
    echo "TCP fastopen: $(safe_read /proc/sys/net/ipv4/tcp_fastopen)"
    echo "Physical Block Devices: $block_list"
    echo "Dashboard Updater: $(updater_state)"
    echo "Thermal Addon: $(detect_thermal_addon)"
    echo ""
    echo "Recent Debug Log:"
    tail -n 120 "$DEBUG_LOG" 2>/dev/null
  } > "$SNAPSHOT_FILE"
  log_maintenance "support snapshot generated"
  echo "$SNAPSHOT_FILE"
}

check_processes() {
  updater_info="$(updater_state)"
  echo "Dashboard updater: $updater_info"
  echo ""
  echo "Matching Supercharger processes:"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -af 'supercharger|p9pxl' 2>/dev/null || true
  else
    ps -A 2>/dev/null | grep -iE 'supercharger|p9pxl' | grep -v grep || true
  fi
  log_maintenance "process check completed"
}

safe_write_node() {
  path="$1"
  value="$2"
  label="$3"
  if [ ! -e "$path" ]; then
    echo "[SKIP] $label: missing ($path)"
    return 2
  fi
  if printf "%s" "$value" > "$path" 2>/dev/null; then
    echo "[PASS] $label: applied $value"
    return 0
  fi
  echo "[SKIP] $label: write rejected; kept $(safe_read "$path")"
  return 1
}

boot_ready() {
  [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] || [ "$(getprop dev.bootcomplete 2>/dev/null)" = "1" ]
}

available_tcp_cc_has() {
  wanted="$1"
  available="$(safe_read /proc/sys/net/ipv4/tcp_available_congestion_control)"
  case " $available " in
    *" $wanted "*) return 0 ;;
    *) return 1 ;;
  esac
}

verify_active_tuning() {
  write_status >/dev/null 2>&1
  selected_profile="$(read_selected_profile)"
  profile_label="$(profile_label_for "$selected_profile")"
  if [ "$selected_profile" = "performance_gaming" ]; then
    vfs_target="70"
    dirty_bg_target="10"
    dirty_target="25"
    swappiness_policy="target: 40"
    writeback_policy="target: 1000"
    cc_policy="target: bbr when available, otherwise cubic"
    irq_policy="experimental mask f0 where accepted"
  else
    vfs_target="80"
    dirty_bg_target="5"
    dirty_target="15"
    swappiness_policy="policy: preserved"
    writeback_policy="policy: preserved"
    cc_policy="target: cubic when available"
    irq_policy="safe mask 70 where accepted"
  fi

  echo "Supercharger active tuning verification"
  echo "Generated: $(date)"
  echo "Profile: $profile_label"
  echo "Engine: $(performance_engine_for "$selected_profile")"
  echo ""
  echo "VM"
  echo "- vfs_cache_pressure: $(current_or_unavailable /proc/sys/vm/vfs_cache_pressure) | target: $vfs_target"
  echo "- dirty_background_ratio: $(current_or_unavailable /proc/sys/vm/dirty_background_ratio) | target: $dirty_bg_target"
  echo "- dirty_ratio: $(current_or_unavailable /proc/sys/vm/dirty_ratio) | target: $dirty_target"
  echo "- dirty_writeback_centisecs: $(current_or_unavailable /proc/sys/vm/dirty_writeback_centisecs) | $writeback_policy"
  echo "- swappiness: $(current_or_unavailable /proc/sys/vm/swappiness) | $swappiness_policy"
  echo "- page-cluster: $(current_or_unavailable /proc/sys/vm/page-cluster) | target: 0"
  echo ""
  echo "Network"
  echo "- default_qdisc: $(current_or_unavailable /proc/sys/net/core/default_qdisc) | policy: preserved"
  echo "- tcp_congestion_control: $(current_or_unavailable /proc/sys/net/ipv4/tcp_congestion_control) | $cc_policy"
  echo "- tcp_fastopen: $(current_or_unavailable /proc/sys/net/ipv4/tcp_fastopen) | target: 1"
  echo ""
  echo "CPU/GPU"
  if [ "$selected_profile" = "performance_gaming" ]; then
    echo "- top-app uclamp.min: $(current_or_unavailable /dev/cpuctl/top-app/cpu.uclamp.min) | target: 15 when supported"
    echo "- foreground uclamp.min: $(current_or_unavailable /dev/cpuctl/foreground/cpu.uclamp.min) | target: 5 when supported"
    echo "- GPU devfreq governor: performance when a supported GPU devfreq node exposes it"
  else
    echo "- policy: unchanged by Active Smooth"
  fi
  echo ""
  echo "Block I/O"
  block_info="$(physical_block_list)"
  block_list="${block_info%%|*}"
  if [ "$block_list" = "none" ]; then
    echo "- no physical block devices reported"
  else
    old_ifs="$IFS"
    IFS=','
    for dev in $block_list; do
      dev="$(echo "$dev" | sed 's/^ *//;s/ *$//')"
      [ -z "$dev" ] && continue
      if [ "$selected_profile" = "performance_gaming" ]; then
        read_policy="floor: 512 when current value is lower"
      else
        read_policy="policy: preserved"
      fi
      echo "- $dev: scheduler=$(current_or_unavailable /sys/block/$dev/queue/scheduler) | read_ahead=$(current_or_unavailable /sys/block/$dev/queue/read_ahead_kb) | $read_policy | iostats=$(current_or_unavailable /sys/block/$dev/queue/iostats)"
    done
    IFS="$old_ifs"
  fi
  echo ""
  echo "IRQ summary from last audit"
  echo "- policy: $irq_policy"
  grep -E 'Storage/UFS IRQ Summary|Wi-Fi/Network IRQ Summary|Touch/Input IRQ Summary' "$DEBUG_LOG" 2>/dev/null | tail -n 6 || true
  echo ""
  echo "Note: this verification does not change tuning. Restart after switching profiles before judging behavior."
  log_maintenance "active tuning verification completed"
}

reapply_safe_profile() {
  if ! boot_ready; then
    echo "[FAIL] System boot is not complete. Refusing to apply maintenance tuning."
    log_maintenance "safe profile reapply refused: boot not complete"
    return 1
  fi

  echo "Re-applying current safe smooth profile"
  echo "No CPU, GPU, thermal, scheduler, charging, or read-ahead changes are applied."
  echo ""

  safe_write_node /proc/sys/vm/vfs_cache_pressure 80 "VFS cache pressure"
  safe_write_node /proc/sys/vm/dirty_background_ratio 5 "VM dirty background ratio"
  safe_write_node /proc/sys/vm/dirty_ratio 15 "VM dirty ratio"
  safe_write_node /proc/sys/vm/page-cluster 0 "VM page-cluster"

  echo "[INFO] VM dirty writeback: preserved $(current_or_unavailable /proc/sys/vm/dirty_writeback_centisecs)"
  echo "[INFO] VM swappiness: preserved $(current_or_unavailable /proc/sys/vm/swappiness)"
  echo ""

  block_info="$(physical_block_list)"
  block_list="${block_info%%|*}"
  if [ "$block_list" = "none" ]; then
    echo "[SKIP] Block I/O: no physical block devices reported"
  else
    old_ifs="$IFS"
    IFS=','
    for dev in $block_list; do
      dev="$(echo "$dev" | sed 's/^ *//;s/ *$//')"
      [ -z "$dev" ] && continue
      echo "[INFO] Block Device ($dev): processing"
      safe_write_node "/sys/block/$dev/queue/iostats" 0 "Block IO Stats ($dev)"
      echo "[INFO] Block Scheduler ($dev): preserved $(current_or_unavailable /sys/block/$dev/queue/scheduler)"
      echo "[INFO] Block Read Ahead ($dev): preserved $(current_or_unavailable /sys/block/$dev/queue/read_ahead_kb)"
    done
    IFS="$old_ifs"
  fi
  echo ""

  echo "[INFO] Network qdisc: preserved $(current_or_unavailable /proc/sys/net/core/default_qdisc)"
  if available_tcp_cc_has cubic; then
    safe_write_node /proc/sys/net/ipv4/tcp_congestion_control cubic "TCP congestion control"
  else
    echo "[SKIP] TCP congestion control: cubic unavailable; kept $(current_or_unavailable /proc/sys/net/ipv4/tcp_congestion_control)"
  fi
  safe_write_node /proc/sys/net/ipv4/tcp_fastopen 1 "TCP Fast Open"

  write_status >/dev/null 2>&1
  log_maintenance "safe smooth profile reapplied manually"
  echo ""
  echo "Done. Status files refreshed."
}

module_health_check() {
  write_status >/dev/null 2>&1
  echo "Supercharger module health check"
  echo "Generated: $(date)"
  echo ""

  check_file() {
    path="$1"
    mode="$2"
    label="$3"
    if [ ! -e "$path" ]; then
      echo "[FAIL] $label: missing ($path)"
      return 1
    fi
    case "$mode" in
      x) [ -x "$path" ] && echo "[PASS] $label: executable" || echo "[WARN] $label: exists but is not executable" ;;
      w) [ -w "$path" ] && echo "[PASS] $label: writable" || echo "[WARN] $label: exists but may not be writable" ;;
      *) echo "[PASS] $label: present" ;;
    esac
  }

  check_file "$PROP_FILE" r "module.prop"
  check_file "$MODDIR/service.sh" x "service.sh"
  check_file "$CTL" x "control script"
  check_file "$STATUS_ENV" w "module_status.env"
  check_file "$ADDON_API_ENV" w "addon_api.env"
  check_file "$DEBUG_LOG" w "debug.log"
  check_file "$MAINTENANCE_LOG" w "maintenance.log"
  echo ""
  echo "Root: $(detect_root_env)"
  echo "Boot complete: $(getprop sys.boot_completed 2>/dev/null)"
  echo "Health: $(grep '^HEALTH=' "$STATUS_ENV" 2>/dev/null | cut -d= -f2- | tr -d "'")"
  echo "Thermal addon: $(detect_thermal_addon)"
  echo "Dashboard updater: $(updater_state)"
  echo ""
  echo "Duplicate process scan:"
  check_processes
  log_maintenance "module health check completed"
}

repair_dashboard_files() {
  touch "$STATUS_ENV" "$ADDON_API_ENV" "$SNAPSHOT_FILE" "$MAINTENANCE_LOG" "$DEBUG_LOG" "$MODDIR/debug.previous.log" 2>/dev/null
  chmod 0755 "$MODDIR/bin" "$CTL" "$MODDIR/service.sh" 2>/dev/null
  chmod 0644 "$STATUS_ENV" "$ADDON_API_ENV" "$SNAPSHOT_FILE" "$MAINTENANCE_LOG" "$DEBUG_LOG" "$MODDIR/debug.previous.log" "$PROP_FILE" 2>/dev/null
  write_status >/dev/null 2>&1

  health="$(grep '^HEALTH=' "$STATUS_ENV" 2>/dev/null | cut -d= -f2- | tr -d "'")"
  temp="$(grep '^BATTERY_TEMP=' "$STATUS_ENV" 2>/dev/null | cut -d= -f2- | tr -d "'")"
  [ -z "$health" ] && health="unknown"
  [ -z "$temp" ] && temp="Temp Unavailable"
  if [ "$health" = "pass" ]; then
    desc="🚀 Status: ${PROFILE_VERSION} | ${temp} | Profile Active"
  else
    desc="⚠️ Status: ${PROFILE_VERSION} | ${temp} | Audit Issue Detected"
  fi
  if set_module_description "$desc"; then
    echo "[PASS] module.prop description repaired"
  else
    echo "[WARN] module.prop description could not be updated"
  fi
  echo "[PASS] module_status.env refreshed"
  echo "[PASS] addon_api.env refreshed"
  echo "[PASS] file permissions normalized"
  log_maintenance "dashboard and API files repaired"
}

cleanup_updater_state() {
  state="$(updater_state)"
  status="${state#*|}"
  echo "Dashboard updater before cleanup: $state"
  case "$status" in
    running)
      echo "[PASS] updater is running; no cleanup needed"
      ;;
    *)
      rm -f "$PIDFILE" 2>/dev/null
      rm -rf "$LOCKDIR" 2>/dev/null
      echo "[PASS] stale/invalid updater state cleaned"
      ;;
  esac
  write_status >/dev/null 2>&1
  echo "Dashboard updater after cleanup: $(updater_state)"
  log_maintenance "dashboard updater state cleanup completed"
}


# The async wrappers run the job in a detached subshell, where $$ still expands
# to the parent's pid. Read the live pid from procfs instead: this shell performs
# the redirect, so /proc/self resolves here and not in a forked substitution.
set_lock_owner_pid() {
  local rest

  LOCK_OWNER_PID=""
  [ -r /proc/self/stat ] && read -r LOCK_OWNER_PID rest < /proc/self/stat 2>/dev/null
  case "$LOCK_OWNER_PID" in
    ''|*[!0-9]*) LOCK_OWNER_PID="$$" ;;
  esac
}

lock_holder_alive() {
  local lock_path="$1"
  local owner
  local stamped
  local current

  [ -r "$lock_path/pid" ] || return 1
  owner="$(head -n 1 "$lock_path/pid" 2>/dev/null | tr -d '\r\n')"
  case "$owner" in
    ''|*[!0-9]*) return 1 ;;
  esac
  stamped="$(sed -n '2p' "$lock_path/pid" 2>/dev/null | tr -d '\r\n')"
  current="$(current_boot_id)"
  [ -n "$stamped" ] && [ -n "$current" ] && [ "$stamped" = "$current" ] || return 1
  kill -0 "$owner" 2>/dev/null
}

acquire_lock_or_exit() {
  local lock_path="$1"
  local label="$2"
  if ! command -v flock >/dev/null 2>&1; then
    echo "[FAIL] $label: flock is unavailable; refusing unsafe lock recovery."
    return 1
  fi
  set_lock_owner_pid
  # Keep a stable guard inode. The kernel releases this short-lived lock even
  # after SIGKILL; there is no ownerless .reclaim directory to strand retries.
  if ! (
    flock -n 9 || {
      echo "[SKIP] $label lock recovery is in progress. Try again shortly."
      exit 1
    }
    if ! mkdir "$lock_path" 2>/dev/null; then
      # A missing/incomplete record can belong to a creator still publishing it.
      # Boot cleanup handles abandoned records whose ownership cannot be proven.
      if [ ! -s "$lock_path/pid" ] || [ -z "$(sed -n '2p' "$lock_path/pid" 2>/dev/null)" ] || lock_holder_alive "$lock_path"; then
        echo "[SKIP] $label is already running. Wait for it to finish before starting another action."
        exit 1
      fi
      rm -rf "$lock_path" 2>/dev/null
      mkdir "$lock_path" 2>/dev/null || exit 1
    fi
    if ! printf '%s\n%s\n' "$LOCK_OWNER_PID" "$(current_boot_id)" > "$lock_path/pid" 2>/dev/null; then
      rm -rf "$lock_path" 2>/dev/null
      exit 1
    fi
  ) 9> "$lock_path.guard"; then
    return 1
  fi
  ACQUIRED_LOCKS="${ACQUIRED_LOCKS}${ACQUIRED_LOCKS:+ }$lock_path"
  trap 'release_locks' EXIT
  trap 'release_locks; exit 129' HUP
  trap 'release_locks; exit 130' INT
  trap 'release_locks; exit 143' TERM
  return 0
}

release_locks() {
  for lock_path in $ACQUIRED_LOCKS; do
    [ -n "$lock_path" ] && rm -rf "$lock_path" 2>/dev/null
  done
  ACQUIRED_LOCKS=""
  trap - EXIT HUP INT TERM
}


run_full_maintenance() {
  acquire_lock_or_exit "$MAINT_LOCKDIR" "One-tap maintenance" || return 1
  echo "Supercharger one-tap maintenance"
  echo "Generated: $(date)"
  echo ""
  echo "This repairs dashboard/API state, cleans stale updater state, refreshes status, verifies current tuning, generates a support snapshot, and checks for duplicate Supercharger processes."
  echo "It does not clear logs or change CPU, GPU, thermal, scheduler, charging, or read-ahead behavior."
  echo ""

  echo "[1/6] Repair dashboard/API"
  repair_dashboard_files
  echo ""

  echo "[2/6] Clean stale updater state"
  cleanup_updater_state
  echo ""

  echo "[3/6] Refresh status"
  if write_status >/dev/null 2>&1; then
    echo "[PASS] module_status.env refreshed"
    echo "[PASS] addon_api.env refreshed"
  else
    echo "[WARN] status refresh returned a warning"
  fi
  echo ""

  echo "[4/6] Verify active tuning"
  verify_active_tuning
  echo ""

  echo "[5/6] Generate support snapshot"
  snapshot_path="$(make_snapshot 2>/dev/null)"
  if [ -n "$snapshot_path" ] && [ -f "$snapshot_path" ]; then
    echo "[PASS] support snapshot generated: $snapshot_path"
  else
    echo "[WARN] support snapshot could not be confirmed"
  fi
  echo ""

  echo "[6/6] Check running processes"
  check_processes
  echo ""
  echo "Done. One-tap maintenance completed."
  log_maintenance "one-tap maintenance completed"
  release_locks
}

package_inventory() {
  local output
  if command -v cmd >/dev/null 2>&1; then
    output="$(cmd package list packages "$@" 2>&1)" || { echo "[FAIL] Package inventory: $output" >&2; return 1; }
  elif command -v pm >/dev/null 2>&1; then
    output="$(pm list packages "$@" 2>&1)" || { echo "[FAIL] Package inventory: $output" >&2; return 1; }
  else
    echo "[FAIL] Package manager command unavailable" >&2
    return 1
  fi
  printf '%s\n' "$output" | awk '
    { sub(/\r$/, "") }
    /^package:[A-Za-z0-9_]+([.][A-Za-z0-9_]+)+$/ { sub(/^package:/, ""); print; next }
    NF { invalid=1 }
    END { if (invalid) { print "Invalid package inventory response" > "/dev/stderr"; exit 1 } }
  '
}

list_user_apps() {
  local apps
  apps="$(package_inventory -3)" || return 1
  printf '%s\n' "$apps" | sed '/^$/d' | LC_ALL=C sort -u
}


safe_system_package_candidates() {
  cat <<'EOF'
com.google.android.apps.nexuslauncher
com.android.launcher3
com.google.android.inputmethod.latin
com.google.android.apps.messaging
com.google.android.dialer
com.google.android.contacts
com.google.android.apps.photos
com.google.android.googlequicksearchbox
com.google.android.apps.maps
com.android.chrome
com.google.android.gm
com.google.android.youtube
com.google.android.apps.youtube.music
com.google.android.calendar
com.google.android.apps.docs
com.google.android.apps.walletnfcrel
com.google.android.apps.recorder
com.google.android.apps.pixel.weather
com.google.android.apps.weather
com.google.android.apps.turbo
com.google.android.apps.wellbeing
com.google.android.apps.safetycenter
EOF
}

is_blocked_core_package() {
  case "$1" in
    android|com.android.systemui|com.google.android.gms|com.google.android.gsf|com.android.phone|com.android.shell|com.android.providers.*|com.android.permissioncontroller|com.google.android.permissioncontroller|com.google.android.networkstack|com.android.networkstack.*|com.android.se|com.android.nfc|com.android.bluetooth|com.android.server.telecom)
      return 0
      ;;
  esac
  return 1
}

list_safe_system_apps() {
  local apps
  apps="$(package_inventory --user 0)" || return 1
  { safe_system_package_candidates; echo __INSTALLED__; printf '%s\n' "$apps"; } | awk '
    $0 == "__INSTALLED__" { installed=1; next }
    !installed { allowed[$0]=1; next }
    NF && allowed[$0] && !seen[$0]++ { print }
  ' | LC_ALL=C sort -u
}

list_optimizable_apps() {
  local user_apps system_apps
  # Retain the existing scope: third-party inventory across users, safe names
  # installed for user 0 (the previous pm path default). Never emit a partial list.
  user_apps="$(list_user_apps)" || return 1
  system_apps="$(list_safe_system_apps)" || return 1
  {
    printf '%s\n' "$user_apps"
    echo __SYSTEM__
    printf '%s\n' "$system_apps"
  } | awk '
    BEGIN { type="user" }
    $0 == "__SYSTEM__" { type="system"; next }
    NF && !seen[$0]++ { print type "|" $0 }
  ' | while IFS='|' read -r type pkg; do
    is_blocked_core_package "$pkg" || printf '%s|%s\n' "$type" "$pkg"
  done
}

is_installed_package() {
  pkg="$1"
  [ -n "$pkg" ] || return 1
  case "$pkg" in
    *[!A-Za-z0-9._-]*|.*|*..*|*.) return 1 ;;
  esac
  pm path "$pkg" >/dev/null 2>&1
}

prepare_art_compile() {
  [ "${ART_HELP_READY:-0}" = 1 ] && return 0
  ART_HELP_READY=1
  ART_BACKGROUND=0
  ART_VERBOSE=0
  ART_FORCE_SUPPORTED=0
  local help compile_help
  help="$(cmd package help 2>/dev/null)" || help=""
  compile_help="$(printf '%s\n' "$help" | awk '
    /^  compile([[:space:]]|$)/ { active=1; next }
    active && /^  [a-z][a-z-]*([[:space:]]|$)/ { exit }
    active { print }
  ')"
  if printf '%s\n' "$compile_help" | grep -q 'PRIORITY_BACKGROUND' &&
     printf '%s\n' "$compile_help" | grep -Eq '^[[:space:]]+-p[[:space:]]'; then ART_BACKGROUND=1; fi
  printf '%s\n' "$compile_help" | grep -Eq '^[[:space:]]+-v[[:space:]]' && ART_VERBOSE=1
  printf '%s\n' "$compile_help" | grep -Eq '^[[:space:]]+-f[[:space:]]' && ART_FORCE_SUPPORTED=1
  return 0
}

compile_art_package() {
  local pkg="$1"
  local policy="${2:-incremental}"
  local output rc
  ART_RESULT=failed
  case "$policy" in
    incremental|force) ;;
    *) echo "[FAIL] Unknown ART policy: $policy"; return 1 ;;
  esac
  prepare_art_compile
  set -- package compile -m speed-profile
  [ "$ART_BACKGROUND" = 1 ] && set -- "$@" -p PRIORITY_BACKGROUND
  [ "$ART_VERBOSE" = 1 ] && set -- "$@" -v
  if [ "$policy" = force ]; then
    [ "$ART_FORCE_SUPPORTED" = 1 ] || { echo "[FAIL] Forced compilation is not advertised by this platform."; return 1; }
    set -- "$@" -f
  fi
  output="$(cmd "$@" "$pkg" 2>&1)"
  rc="$?"
  printf '%s\n' "$output" | tail -n 40
  if [ "$rc" -ne 0 ] || printf '%s\n' "$output" | grep -Eq '^[[:space:]]*(Failure([[:space:]:]|$)|Error:|Final Status: (FAILED|CANCELLED))'; then
    echo "[FAIL] ART request failed for $pkg; no verification fallback was attempted."
    return 1
  fi
  case "$output" in
    *'Final Status: PERFORMED'*) ART_RESULT=performed ;;
    *'Final Status: SKIPPED'*) ART_RESULT=skipped ;;
    *) ART_RESULT=accepted ;;
  esac
  echo "[PASS] ART $ART_RESULT: $pkg"
  [ "$ART_RESULT" = accepted ] && echo "The platform did not report whether compilation was needed."
  return 0
}

optimize_one_app() {
  local pkg="$1"
  local policy="${2:-incremental}"
  local rc
  acquire_lock_or_exit "$APP_LOCKDIR" "App optimization" || return 1
  if ! is_installed_package "$pkg" || is_blocked_core_package "$pkg"; then
    echo "[FAIL] Invalid, unavailable, or protected package: $pkg"
    release_locks
    return 1
  fi
  echo "ART $policy request: $pkg"
  compile_art_package "$pkg" "$policy"
  rc="$?"
  log_maintenance "ART $policy: package=$pkg result=$ART_RESULT"
  release_locks
  return "$rc"
}

optimize_package_list() {
  local label="$1"
  local apps="$2"
  local pkg total=0 performed=0 skipped=0 accepted=0 failed=0 protected=0
  acquire_lock_or_exit "$APP_LOCKDIR" "App optimization" || return 1
  echo "Optimizing $label"
  echo "Mode: incremental ART speed-profile; Android can skip unnecessary work."
  prepare_art_compile
  [ "$ART_BACKGROUND" = 1 ] && echo "Priority: background"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    total=$((total + 1))
    if is_blocked_core_package "$pkg"; then
      protected=$((protected + 1))
      echo "[SKIP] Protected core package: $pkg"
    elif compile_art_package "$pkg" incremental; then
      case "$ART_RESULT" in
        performed) performed=$((performed + 1)) ;;
        skipped) skipped=$((skipped + 1)) ;;
        *) accepted=$((accepted + 1)) ;;
      esac
    else
      failed=$((failed + 1))
    fi
  done <<EOF_APPS
$apps
EOF_APPS
  echo "Finished. Packages: $total | performed: $performed | skipped: $skipped | accepted (detail unavailable): $accepted | failed: $failed | protected: $protected"
  log_maintenance "ART batch: label=$label performed=$performed skipped=$skipped accepted=$accepted failed=$failed protected=$protected"
  release_locks
  [ "$failed" -eq 0 ]
}

optimize_user_apps() {
  local apps
  apps="$(list_user_apps)" || return 1
  optimize_package_list "third-party user apps" "$apps"
}

optimize_safe_system_apps() {
  local apps
  apps="$(list_safe_system_apps)" || return 1
  optimize_package_list "safe system apps" "$apps"
}

optimize_all_listed_apps() {
  local apps
  apps="$(list_optimizable_apps)" || return 1
  apps="$(printf '%s\n' "$apps" | cut -d'|' -f2- | LC_ALL=C sort -u)"
  optimize_package_list "listed apps and safe system apps" "$apps"
}

run_system_dexopt_job() {
  acquire_lock_or_exit "$APP_LOCKDIR" "System dexopt job" || return 1
  echo "Running Android system dexopt job"
  echo "Mode: package manager bg-dexopt-job"
  echo "This does not change CPU, GPU, thermal, scheduler, charging, or kernel tuning."
  echo ""

  if ! command -v cmd >/dev/null 2>&1; then
    echo "[FAIL] Android cmd package service is unavailable."
    log_maintenance "system dexopt job failed: cmd unavailable"
    release_locks
    return 1
  fi

  cmd package bg-dexopt-job 2>&1
  rc="$?"
  if [ "$rc" -eq 0 ]; then
    echo "[PASS] Android system dexopt job completed."
    log_maintenance "system dexopt job completed"
    release_locks
    return 0
  fi

  echo "[WARN] Android system dexopt job returned rc=$rc"
  echo "Some Android builds refuse this job outside their normal idle maintenance window."
  log_maintenance "system dexopt job returned warning: rc=$rc"
  release_locks
  return "$rc"
}

read_task_status() {
  local state_file="$1"
  local pid_file="$2"
  local idle_label="$3"
  local task_log="$4"
  local snapshot state pid recorded_pid
  snapshot="$(cat "$state_file" 2>/dev/null)"
  if [ -z "$snapshot" ]; then
    write_env_pair STATE idle
    write_env_pair LABEL "$idle_label"
    write_env_pair PID ""
    write_env_pair LOG "$task_log"
    return 0
  fi
  state="$(printf '%s\n' "$snapshot" | env_value STATE -)"
  pid="$(printf '%s\n' "$snapshot" | env_value PID -)"
  if [ "$state" = running ]; then
    recorded_pid="$(cat "$pid_file" 2>/dev/null)"
    case "$pid" in
      ''|0|1|*[!0-9]*) state=interrupted ;;
      *) [ "$pid" = "$recorded_pid" ] && kill -0 "$pid" 2>/dev/null || state=interrupted ;;
    esac
  fi
  if [ "$state" = interrupted ]; then
    # Report an interruption without racing the worker's atomic state rename.
    printf '%s\n' "$snapshot" | sed 's/^STATE=.*/STATE="interrupted"/;s/^PID=.*/PID=""/'
  else
    printf '%s\n' "$snapshot"
  fi
}

start_background_task() {
  local task_lock="$1"
  local task_pidfile="$2"
  local task_log="$3"
  local task_writer="$4"
  local task_label="$5"
  local task_pid task_rc task_launcher
  shift 5

  # Reserve the entire lifecycle before touching shared logs or state. The
  # operation keeps its separate lock so synchronous CLI calls remain protected.
  acquire_lock_or_exit "$task_lock" "$task_label" || return 1
  task_launcher="$LOCK_OWNER_PID"
  (
    set_lock_owner_pid
    task_pid="$LOCK_OWNER_PID"
    trap 'rm -f "$task_pidfile" 2>/dev/null; release_locks' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n%s\n' "$task_pid" "$(current_boot_id)" > "$task_lock/pid.$task_pid" &&
      mv -f "$task_lock/pid.$task_pid" "$task_lock/pid" || exit 1
    echo "$task_pid" > "$task_pidfile" || exit 1
    {
      echo "Supercharger background task"
      echo "Started: $(date)"
      echo "Job: $task_label"
      echo ""
    } > "$task_log" || exit 1
    "$task_writer" running "$task_label" "$task_pid" || exit 1
    : > "$task_lock/ready" || exit 1
    while [ ! -f "$task_lock/accepted" ]; do
      kill -0 "$task_launcher" 2>/dev/null || exit 1
      sleep 0.05
    done

    # Isolate the operation's variables and lock traps from lifecycle ownership.
    (
      ACQUIRED_LOCKS=""
      trap - EXIT HUP INT TERM
      "$@"
    ) >> "$task_log" 2>&1
    task_rc="$?"
    echo "Finished: $(date)" >> "$task_log"
    if [ "$task_rc" -eq 0 ]; then
      echo "Result: completed" >> "$task_log"
      "$task_writer" done "$task_label" ""
    else
      echo "Result: completed with warnings or failure" >> "$task_log"
      "$task_writer" failed "$task_label" ""
    fi
    log_maintenance "background task finished: $task_label (rc=$task_rc)"
    STATUS_LOG_QUIET=1 write_status >/dev/null 2>&1
    exit "$task_rc"
  ) >/dev/null 2>&1 &
  task_pid="$!"

  # Ownership now belongs to the worker; the launcher must never publish state
  # after it, or remove its lock when the WebUI command exits.
  ACQUIRED_LOCKS=""
  trap - EXIT HUP INT TERM
  while [ -d "$task_lock" ] && [ ! -f "$task_lock/ready" ]; do
    kill -0 "$task_pid" 2>/dev/null || { echo "[FAIL] Background task could not start."; return 1; }
    sleep 0.05
  done
  [ -f "$task_lock/ready" ] && touch "$task_lock/accepted" || {
    echo "[FAIL] Background task could not initialize its state."
    return 1
  }
  echo "Started background task."
  echo "Job: $task_label"
  echo "PID: $task_pid"
  echo "The WebUI will poll progress without freezing."
}

write_maintenance_state() {
  local state="$1"
  local label="$2"
  local pid="$3"
  local tmp="$MAINT_STATE.tmp.$$"
  {
    write_env_pair "STATE" "$state"
    write_env_pair "LABEL" "$label"
    write_env_pair "PID" "$pid"
    write_env_pair "UPDATED" "$(date)"
    write_env_pair "LOG" "$MAINT_TASK_LOG"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$MAINT_STATE" 2>/dev/null
}

maintenance_status() {
  read_task_status "$MAINT_STATE" "$MAINT_PIDFILE" "No maintenance task running" "$MAINT_TASK_LOG"
}

task_progress() {
  local log_file
  case "$1" in
    apps) app_opt_status || return 1; log_file="$APP_OPT_LOG" ;;
    maintenance) maintenance_status || return 1; log_file="$MAINT_TASK_LOG" ;;
    *) echo "Unknown task type" >&2; return 1 ;;
  esac
  printf '\n__SUPERCHARGER_LOG__\n'
  if [ -s "$log_file" ]; then
    tail -c 16384 "$log_file" | tail -n 70
  else
    echo "No task output yet."
  fi
}

maintenance_task_log() {
  if [ -s "$MAINT_TASK_LOG" ]; then
    tail -n 70 "$MAINT_TASK_LOG" 2>/dev/null
  else
    echo "No maintenance task log yet."
  fi
}

run_maintenance_background() {
  start_background_task "$MAINT_ASYNC_LOCKDIR" "$MAINT_PIDFILE" "$MAINT_TASK_LOG" \
    write_maintenance_state "One-tap maintenance" run_full_maintenance
}

write_app_opt_state() {
  local state="$1"
  local label="$2"
  local pid="$3"
  local tmp="$APP_OPT_STATE.tmp.$$"
  {
    write_env_pair "STATE" "$state"
    write_env_pair "LABEL" "$label"
    write_env_pair "PID" "$pid"
    write_env_pair "UPDATED" "$(date)"
    write_env_pair "LOG" "$APP_OPT_LOG"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$APP_OPT_STATE" 2>/dev/null
}

app_opt_status() {
  read_task_status "$APP_OPT_STATE" "$APP_OPT_PIDFILE" "No app optimization running" "$APP_OPT_LOG"
}

app_opt_log() {
  if [ -s "$APP_OPT_LOG" ]; then
    tail -n 70 "$APP_OPT_LOG" 2>/dev/null
  else
    echo "No app optimization log yet."
  fi
}

run_app_opt_background() {
  local mode="$1"
  local target="$2"
  case "$mode" in
    all)
      start_background_task "$APP_ASYNC_LOCKDIR" "$APP_OPT_PIDFILE" "$APP_OPT_LOG" \
        write_app_opt_state "Optimizing listed apps" optimize_all_listed_apps ;;
    system)
      start_background_task "$APP_ASYNC_LOCKDIR" "$APP_OPT_PIDFILE" "$APP_OPT_LOG" \
        write_app_opt_state "Optimizing safe system apps" optimize_safe_system_apps ;;
    selected)
      start_background_task "$APP_ASYNC_LOCKDIR" "$APP_OPT_PIDFILE" "$APP_OPT_LOG" \
        write_app_opt_state "Optimizing selected app: $target" optimize_one_app "$target" ;;
    selected-force)
      start_background_task "$APP_ASYNC_LOCKDIR" "$APP_OPT_PIDFILE" "$APP_OPT_LOG" \
        write_app_opt_state "Recompiling selected app: $target" optimize_one_app "$target" force ;;
    dexopt)
      start_background_task "$APP_ASYNC_LOCKDIR" "$APP_OPT_PIDFILE" "$APP_OPT_LOG" \
        write_app_opt_state "Android system dexopt job" run_system_dexopt_job ;;
    *) echo "[FAIL] Unknown app optimization mode: $mode"; return 1 ;;
  esac
}

clear_maintenance_log() {
  : > "$MAINTENANCE_LOG"
  echo "maintenance log cleared"
}

thermal_debug() {
  echo "Thermal Control detection"
  echo "Registry: $THERMAL_STATUS_ENV"
  if [ -r "$THERMAL_STATUS_ENV" ]; then
    cat "$THERMAL_STATUS_ENV"
  else
    echo "Registry: not found"
  fi
  echo "Detected: $(detect_thermal_addon)"
  echo "Module dir: $(thermal_addon_dir 2>/dev/null)"
  echo "Scanned module bases:"
  for base in $(thermal_module_bases); do
    [ -d "$base" ] || continue
    echo "- $base"
    for prop in "$base"/*/module.prop; do
      [ -r "$prop" ] || continue
      id_line="$(grep -im1 '^id=' "$prop" 2>/dev/null | cut -d= -f2-)"
      name_line="$(grep -im1 '^name=' "$prop" 2>/dev/null | cut -d= -f2-)"
      case "$(printf '%s %s' "$id_line" "$name_line" | tr 'A-Z' 'a-z')" in
        *thermal*|*supercharger*) echo "  $(dirname "$prop"): id=$id_line name=$name_line" ;;
      esac
    done
  done
}

thermal_status_command() {
  integrated_thermal_status
}

thermal_enable_command() {
  profile="$1"
  if [ -z "$profile" ]; then
    profile="$(read_integrated_thermal_profile)"
    valid_integrated_thermal_profile "$profile" || profile="$(thermal_profile_for "$(read_selected_profile)")"
    valid_integrated_thermal_profile "$profile" || profile="balanced"
  fi
  apply_integrated_thermal_profile "$profile" "integrated"
}

thermal_set_profile_command() {
  profile="$1"
  if ! integrated_thermal_enabled; then
    echo "Thermal Control is off."
    echo "Enable it before changing thermal profiles."
    return 1
  fi
  apply_integrated_thermal_profile "$profile" "integrated"
}

thermal_disable_command() {
  disable_integrated_thermal_control
}

thermal_profiles_command() {
  echo "balanced|Balanced|Daily thermal behavior"
  echo "gaming|Gaming|Sustained gaming thermal behavior"
  echo "charge_cool|Charge Cool|Charging-focused thermal behavior"
}

gpu_scan() {
  echo "GPU/devfreq scan"
  echo "Kernel: $(uname -r 2>/dev/null)"
  echo "Device: $(getprop ro.product.device 2>/dev/null)"
  echo ""
  found=0
  for gov_path in /sys/class/devfreq/*/governor; do
    [ -e "$gov_path" ] || continue
    found=$((found + 1))
    dir="${gov_path%/governor}"
    real="$(readlink -f "$dir" 2>/dev/null)"
    echo "[$found] $(basename "$dir")"
    echo "  path: $dir"
    [ -n "$real" ] && echo "  realpath: $real"
    echo "  governor: $(safe_read "$gov_path")"
    echo "  available_governors: $(safe_read "$dir/available_governors")"
    echo "  min_freq: $(safe_read "$dir/min_freq")"
    echo "  max_freq: $(safe_read "$dir/max_freq")"
    echo "  available_frequencies: $(safe_read "$dir/available_frequencies")"
    [ -r "$dir/name" ] && echo "  name: $(safe_read "$dir/name")"
    [ -r "$dir/device/uevent" ] && echo "  uevent: $(tr '\n' ' ' < "$dir/device/uevent" 2>/dev/null)"
    echo ""
  done
  [ "$found" -eq 0 ] && echo "No /sys/class/devfreq governor nodes found."
}

case "$1" in
  status|refresh|'') write_status ;;
  status-quiet) STATUS_LOG_QUIET=1 write_status ;;
  snapshot) make_snapshot ;;
  processes) check_processes ;;
  verify) verify_active_tuning ;;
  reapply-safe) reapply_safe_profile ;;
  health) module_health_check ;;
  repair-dashboard) repair_dashboard_files ;;
  cleanup-updater) cleanup_updater_state ;;
  maintenance-all) run_full_maintenance ;;
  maintenance-all-async) run_maintenance_background ;;
  maintenance-status) maintenance_status ;;
  maintenance-log) maintenance_task_log ;;
  storage) block_info="$(physical_block_list)"; echo "${block_info%%|*}" ;;
  profiles) list_profiles ;;
  profile-status) profile_status ;;
  thermal-detect) thermal_debug ;;
  thermal-status) thermal_status_command ;;
  thermal-enable) thermal_enable_command "$2" ;;
  thermal-disable) thermal_disable_command ;;
  thermal-set-profile) thermal_set_profile_command "$2" ;;
  thermal-profiles) thermal_profiles_command ;;
  gpu-scan) gpu_scan ;;
  set-profile) set_supercharger_profile "$2" ;;
  list-apps) list_optimizable_apps ;;
  list-user-apps) list_user_apps ;;
  list-system-apps) list_safe_system_apps ;;
  optimize-app) optimize_one_app "$2" ;;
  optimize-user-apps) optimize_user_apps ;;
  optimize-system-apps) optimize_safe_system_apps ;;
  optimize-apps) optimize_all_listed_apps ;;
  dexopt-job) run_system_dexopt_job ;;
  optimize-app-async) run_app_opt_background selected "$2" ;;
  optimize-system-apps-async) run_app_opt_background system ;;
  optimize-apps-async) run_app_opt_background all ;;
  dexopt-job-async) run_app_opt_background dexopt ;;
  app-opt-status) app_opt_status ;;
  app-opt-progress) task_progress apps ;;
  maintenance-progress) task_progress maintenance ;;
  optimize-app-force-async) run_app_opt_background selected-force "$2" ;;
  app-opt-log) app_opt_log ;;
  clear-maintenance) clear_maintenance_log ;;
  *)
    echo "Usage: $0 {status|snapshot|processes|verify|reapply-safe|health|repair-dashboard|cleanup-updater|maintenance-all|storage|profiles|profile-status|thermal-detect|thermal-status|thermal-enable|thermal-disable|thermal-set-profile|thermal-profiles|set-profile|list-apps|list-user-apps|list-system-apps|optimize-app|optimize-user-apps|optimize-system-apps|optimize-apps|dexopt-job|optimize-app-async|optimize-system-apps-async|optimize-apps-async|dexopt-job-async|app-opt-status|app-opt-log|app-opt-progress|maintenance-progress|optimize-app-force-async|clear-maintenance|maintenance-all-async|maintenance-status|maintenance-log|gpu-scan}"
    exit 1
    ;;
esac
