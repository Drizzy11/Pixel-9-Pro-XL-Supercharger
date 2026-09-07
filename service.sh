#!/system/bin/sh

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/debug.log"
PREVIOUS_LOG_FILE="$MODDIR/debug.previous.log"
MAINTENANCE_LOG_FILE="$MODDIR/maintenance.log"
SNAPSHOT_FILE="$MODDIR/support_snapshot.txt"
STATUS_ENV="$MODDIR/module_status.env"
ADDON_API_ENV="$MODDIR/addon_api.env"
THERMAL_REGISTRY_DIR="/data/adb/supercharger_thermal_control"
THERMAL_STATUS_ENV="$THERMAL_REGISTRY_DIR/status.env"
THERMAL_REQUEST_ENV="$THERMAL_REGISTRY_DIR/profile_request.env"
INTEGRATED_THERMAL_PROFILES="$MODDIR/thermal_profiles"
INTEGRATED_THERMAL_STATE="$MODDIR/thermal_control.env"
INTEGRATED_THERMAL_PROFILE_FILE="$MODDIR/thermal_current_profile"
INTEGRATED_THERMAL_ACTIVE_DIR="$MODDIR/system/vendor/etc"
PIDFILE="$MODDIR/dashboard_updater.pid"
LOCKDIR="$MODDIR/.dashboard_updater.lock"
MAINT_LOCKDIR="$MODDIR/.maintenance.lock"
APP_LOCKDIR="$MODDIR/.app_optimization.lock"
MAINT_PIDFILE="$MODDIR/maintenance_task.pid"
APP_OPT_PIDFILE="$MODDIR/app_optimization.pid"

PROFILE_VERSION="v2.6.8-beta.1"
PROFILE_MODE="Unknown"
PROFILE_FILE="$MODDIR/current_profile"
PERSIST_STATE_DIR="/data/adb/supercharger_state"
PERSIST_PROFILE_FILE="$PERSIST_STATE_DIR/current_profile"
SELECTED_PROFILE="active_smooth"
PROFILE_LABEL="Active Smooth"
THERMAL_PROFILE_REQUEST="balanced"
PERFORMANCE_ENGINE_STATE="stable"
TEMP_UPDATE_INTERVAL=300
TEMP_DELTA_THRESHOLD=10
GPU_STATE_FILE="$MODDIR/gpu_policy_state.env"

STORAGE_IRQ_PATTERNS="ufshcd|ufs"
NETWORK_IRQ_PATTERNS="wlan|wifi|wcnss|bcmdhd|dhd|rmnet|ipa"
TOUCH_IRQ_PATTERNS="synaptics|touch|goodix|fts|sec_touch|input"

ANDROID_RELEASE=""
ANDROID_SDK=""
BUILD_ID=""
BUILD_INCREMENTAL=""
KERNEL_RELEASE=""
ROOT_ENV="Unknown"
DEVICE="$(getprop ro.product.device 2>/dev/null)"
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.product.vendor.device 2>/dev/null)"
[ -z "$DEVICE" ] && DEVICE="$(getprop ro.boot.hardware.sku 2>/dev/null)"
MODEL="$(getprop ro.product.model 2>/dev/null)"

BATTERY_TEMP_DECIC=""
BATTERY_TEMP_LABEL="Temp Unavailable"
SWAP_ACTIVE=0
PAGE_CLUSTER_STATUS="Unavailable"

SUPPORTED_CAPABILITIES=""
UNSUPPORTED_CAPABILITIES=""
SKIPPED_CAPABILITIES=""
APPLIED_CAPABILITIES=""
PRESERVED_CAPABILITIES=""

BLOCK_AUDITED_COUNT=0
BLOCK_SKIPPED_COUNT=0
BLOCK_AUDITED_LIST="none"

NETWORK_CAPABILITY_SUMMARY=""
IRQ_SUMMARY_STORAGE=""
IRQ_SUMMARY_NETWORK=""
IRQ_SUMMARY_TOUCH=""
THERMAL_ADDON_INSTALLED=0
THERMAL_ADDON_VERSION="none"
HEALTH_STATE="pass"
STATUS_TEXT="Profile Active"

log_line() {
    echo "$1" >> "$LOG_FILE"
}

append_csv() {
    local var_name="$1"
    local value="$2"
    local current

    current="$(eval "printf '%s' \"\${$var_name}\"")"
    if [ -z "$current" ]; then
        eval "$var_name=\"\$value\""
    else
        eval "$var_name=\"\$current, \$value\""
    fi
}

record_supported() { append_csv SUPPORTED_CAPABILITIES "$1"; }
record_unsupported() { append_csv UNSUPPORTED_CAPABILITIES "$1"; }
record_skipped() { append_csv SKIPPED_CAPABILITIES "$1"; }
record_applied() { append_csv APPLIED_CAPABILITIES "$1"; }
record_preserved() { append_csv PRESERVED_CAPABILITIES "$1"; }

safe_read() {
    [ -r "$1" ] && cat "$1" 2>/dev/null
}

values_equivalent() {
    local current="$1"
    local target="$2"

    [ "$current" = "$target" ] && return 0

    case "$current:$target" in
        max:100|100:max) return 0 ;;
    esac

    awk -v a="$current" -v b="$target" '
        BEGIN {
            if (a ~ /^-?[0-9]+([.][0-9]+)?$/ && b ~ /^-?[0-9]+([.][0-9]+)?$/ && (a + 0) == (b + 0)) exit 0
            exit 1
        }
    ' 2>/dev/null
}

set_module_description() {
    local desc="$1"
    local tmp="${PROP_FILE}.tmp.$$"

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

safe_write_if_needed() {
    local path="$1"
    local value="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path unavailable ($path)"
        record_unsupported "$label"
        return 1
    fi

    if [ ! -w "$path" ]; then
        log_line "[SKIP] $label: path not writable"
        record_skipped "$label"
        return 1
    fi

    current="$(safe_read "$path")"
    if values_equivalent "$current" "$value"; then
        log_line "[PASS] $label: already at target ${current:-$value}"
        record_supported "$label"
        return 0
    fi

    if echo "$value" > "$path" 2>/dev/null; then
        current="$(safe_read "$path")"
        if values_equivalent "$current" "$value"; then
            log_line "[PASS] $label: applied ${current:-$value}"
            record_applied "$label"
            return 0
        fi
        log_line "[FAIL] $label: write did not persist (current=${current:-<empty>})"
        HEALTH_STATE="warn"
        return 1
    fi

    log_line "[FAIL] $label: write rejected by kernel"
    HEALTH_STATE="warn"
    return 1
}

experimental_write_if_needed() {
    local path="$1"
    local value="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path unavailable"
        record_unsupported "$label"
        return 1
    fi

    if [ ! -w "$path" ]; then
        log_line "[SKIP] $label: path not writable"
        record_skipped "$label"
        return 1
    fi

    current="$(safe_read "$path")"
    if values_equivalent "$current" "$value"; then
        log_line "[PASS] $label: already at target ${current:-$value}"
        record_supported "$label"
        return 0
    fi

    if echo "$value" > "$path" 2>/dev/null; then
        current="$(safe_read "$path")"
        if values_equivalent "$current" "$value"; then
            log_line "[PASS] $label: applied ${current:-$value}"
            record_applied "$label"
            return 0
        fi
    fi

    log_line "[SKIP] $label: write rejected by kernel; kept ${current:-unknown}"
    record_skipped "$label"
    return 1
}

preserve_value() {
    local path="$1"
    local label="$2"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path unavailable"
        record_unsupported "$label"
        return 1
    fi

    current="$(safe_read "$path")"
    log_line "[PASS] $label: preserved current value ${current:-unknown}"
    record_preserved "$label"
    return 0
}

verify_prop() {
    local label="$1"
    local prop="$2"
    local expected="$3"
    local current

    current="$(getprop "$prop")"
    if [ "$current" = "$expected" ]; then
        log_line "[PASS] $label: $current"
    else
        log_line "[FAIL] $label: expected $expected, got ${current:-<empty>}"
        HEALTH_STATE="warn"
    fi
}

get_battery_temp_decic() {
    local raw

    if [ ! -r /sys/class/power_supply/battery/temp ]; then
        return 1
    fi

    raw="$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
    case "$raw" in
        ''|*[!0-9-]*) return 1 ;;
        *) echo "$raw"; return 0 ;;
    esac
}

format_temp_label() {
    local decic="$1"
    local whole
    local frac

    if [ -z "$decic" ]; then
        echo "Temp Unavailable"
        return 0
    fi

    whole=$((decic / 10))
    frac=$((decic % 10))
    [ "$frac" -lt 0 ] && frac=$((frac * -1))
    echo "${whole}.${frac}C"
}

refresh_battery_temp_state() {
    BATTERY_TEMP_DECIC="$(get_battery_temp_decic)"
    BATTERY_TEMP_LABEL="$(format_temp_label "$BATTERY_TEMP_DECIC")"
}

abs_diff_decic() {
    local a="$1"
    local b="$2"
    local diff

    diff=$((a - b))
    [ "$diff" -lt 0 ] && diff=$((diff * -1))
    echo "$diff"
}

write_env_pair() {
  key="$1"
  value="$(printf "%s" "$2" | tr -d '
')"
  printf '%s="%s"
' "$key" "$value"
}


env_value() {
    local key="$1"
    local file="$2"
    local line=""
    local value=""
    [ -n "$key" ] && [ -r "$file" ] || return 0
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

detect_root_env() {
    if [ -d /data/adb/ksu ] || [ -n "$KSU" ] || [ -n "$KSU_VER" ]; then
        ROOT_ENV="KernelSU"
    elif [ -d /data/adb/ap ] || [ -n "$APATCH" ]; then
        ROOT_ENV="APatch"
    elif [ -d /data/adb/magisk ] || [ -n "$MAGISK_VER" ]; then
        ROOT_ENV="Magisk"
    else
        ROOT_ENV="Unknown"
    fi
}


read_selected_profile() {
    local value
    if [ -r "$PROFILE_FILE" ]; then
        value="$(tr -d '\r\n' < "$PROFILE_FILE" 2>/dev/null)"
    fi
    case "$value" in
        active_smooth|performance_gaming) echo "$value" ;;
        *) echo "active_smooth" ;;
    esac
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

save_selected_profile() {
    local value="$1"

    echo "$value" > "$PROFILE_FILE" 2>/dev/null || return 1
    chmod 0644 "$PROFILE_FILE" 2>/dev/null || true
    if mkdir -p "$PERSIST_STATE_DIR" 2>/dev/null; then
        chmod 0755 "$PERSIST_STATE_DIR" 2>/dev/null || true
        echo "$value" > "$PERSIST_PROFILE_FILE" 2>/dev/null || true
        chmod 0644 "$PERSIST_PROFILE_FILE" 2>/dev/null || true
    fi
    return 0
}

adopt_thermal_control_selection() {
    local request_env="$THERMAL_REQUEST_ENV"
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

profile_mode_for() {
    local profile="$1"
    if [ "$profile" = "performance_gaming" ]; then
        echo "Performance / Gaming"
        return 0
    fi
    case "$ANDROID_SDK" in
        37|3[7-9]|[4-9][0-9]) echo "Android 17 Active Smooth" ;;
        36) echo "Android 16 Active Smooth" ;;
        *) echo "Pixel 9 Active Smooth" ;;
    esac
}

parse_android_version_info() {
    ANDROID_RELEASE="$(getprop ro.build.version.release)"
    ANDROID_SDK="$(getprop ro.build.version.sdk)"
    BUILD_ID="$(getprop ro.build.id)"
    BUILD_INCREMENTAL="$(getprop ro.build.version.incremental)"
    KERNEL_RELEASE="$(uname -r 2>/dev/null)"
    detect_root_env
    adopt_thermal_control_selection

    SELECTED_PROFILE="$(read_selected_profile)"
    PROFILE_LABEL="$(profile_label_for "$SELECTED_PROFILE")"
    THERMAL_PROFILE_REQUEST="$(thermal_profile_for "$SELECTED_PROFILE")"
    PROFILE_MODE="$(profile_mode_for "$SELECTED_PROFILE")"
    case "$SELECTED_PROFILE" in
        performance_gaming) PERFORMANCE_ENGINE_STATE="experimental" ;;
        *) PERFORMANCE_ENGINE_STATE="stable" ;;
    esac
}

has_active_swap() {
    local line

    [ -r /proc/swaps ] || return 1
    while read -r line; do
        case "$line" in
            Filename*|'') continue ;;
            *) return 0 ;;
        esac
    done < /proc/swaps
    return 1
}

get_active_scheduler() {
    local content="$1"
    echo "$content" | sed -n 's/.*\[\([^]]*\)\].*/\1/p'
}

scheduler_supports_value() {
    local content="$1"
    local desired="$2"
    case "$content" in *"$desired"*) return 0 ;; esac
    return 1
}

kernel_supports_tcp_cc() {
    local desired="$1"
    local cc_available="/proc/sys/net/ipv4/tcp_available_congestion_control"
    local current_cc

    if [ -e "$cc_available" ]; then
        case "$(safe_read "$cc_available")" in *"$desired"*) return 0 ;; esac
        return 1
    fi

    if [ -e /proc/sys/net/ipv4/tcp_congestion_control ]; then
        current_cc="$(safe_read /proc/sys/net/ipv4/tcp_congestion_control)"
        [ "$current_cc" = "$desired" ] && return 0
    fi

    return 1
}

is_relevant_block_device() {
    local base="$1"
    local dev_path="$2"

    case "$base" in
        dm-*|loop*|ram*|zram*|md*|sr*|fd*) return 1 ;;
    esac

    [ -d "$dev_path/queue" ] || return 1

    case "$base" in
        sd[a-z]|sd[a-z][a-z]|mmcblk[0-9]*|nvme[0-9]n[0-9]*) return 0 ;;
    esac

    [ -e "$dev_path/device" ] || [ -L "$dev_path/device" ] || return 1
    return 0
}

append_status_block_name() {
    local name="$1"
    [ -n "$name" ] || return 0
    case "$name" in
        dm-*|loop*|ram*|zram*|md*|sr*|fd*|*[!A-Za-z0-9._-]*) return 0 ;;
    esac
    case ", $STATUS_BLOCK_PARSE_LIST, " in
        *", $name, "*) return 0 ;;
    esac
    if [ -z "$STATUS_BLOCK_PARSE_LIST" ]; then
        STATUS_BLOCK_PARSE_LIST="$name"
    else
        STATUS_BLOCK_PARSE_LIST="$STATUS_BLOCK_PARSE_LIST, $name"
    fi
}

parse_status_block_names_from_text() {
    local text="$1"
    local words
    local token

    STATUS_BLOCK_PARSE_LIST=""
    words="$(printf '%s\n' "$text" | tr ',|:;()[]' '        ')"
    for token in $words; do
        token="$(printf "%s" "$token" | sed 's/[^A-Za-z0-9._-]//g')"
        case "$token" in
            sd[a-z]|sd[a-z][a-z]|mmcblk[0-9]*|nvme[0-9]n[0-9]*) append_status_block_name "$token" ;;
        esac
    done
    printf "%s" "$STATUS_BLOCK_PARSE_LIST"
}

pixel_ufs_default_blocks() {
    case "$DEVICE" in
        komodo|caiman|tokay|comet)
            echo "sda, sdb, sdc, sdd"
            return 0
            ;;
    esac
    return 1
}

physical_block_status_fallback() {
    local f
    local text
    local parsed

    for f in "$LOG_FILE" "$PREVIOUS_LOG_FILE" "$SNAPSHOT_FILE" "$STATUS_ENV"; do
        [ -r "$f" ] || continue
        text="$(grep -i -E 'physical block devices|audited block devices|block verify|block device|block io stats' "$f" 2>/dev/null | tail -n 120)"
        [ -n "$text" ] || continue
        parsed="$(parse_status_block_names_from_text "$text")"
        case "$parsed" in
            ''|'none'|'unknown'|'Not reported') continue ;;
            *) echo "$parsed"; return 0 ;;
        esac
    done

    pixel_ufs_default_blocks
}

preserve_block_value() {
    local path="$1"
    local label="$2"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path unavailable"
        record_unsupported "$label"
        return 1
    fi

    current="$(safe_read "$path")"
    log_line "[PASS] $label: preserved ${current:-unknown}"
    record_preserved "$label"
    return 0
}

log_system_version_audit() {
    parse_android_version_info

    log_line ""
    log_line "[INFO] System Version Audit"
    log_line "[INFO] Android Release: ${ANDROID_RELEASE:-unknown}"
    log_line "[INFO] SDK Level: ${ANDROID_SDK:-unknown}"
    log_line "[INFO] Build ID: ${BUILD_ID:-unknown}"
    log_line "[INFO] Incremental Build: ${BUILD_INCREMENTAL:-unknown}"
    log_line "[INFO] Kernel Release: ${KERNEL_RELEASE:-unknown}"
    log_line "[INFO] Root Environment: ${ROOT_ENV:-Unknown}"
    log_line "[INFO] Device Model: ${MODEL:-unknown}"
    log_line "[INFO] Device Codename: ${DEVICE:-unknown}"
    log_line "[INFO] Profile Mode: ${PROFILE_MODE:-unknown}"
}

wait_for_full_boot() {
    local boot_wait=0

    log_line "[INFO] Waiting for full Android boot"
    until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$boot_wait" -ge 180 ]; do
        sleep 2
        boot_wait=$((boot_wait + 2))
    done

    if [ "$(getprop sys.boot_completed)" != "1" ]; then
        log_line "[FAIL] Boot detection timed out after ${boot_wait}s"
        HEALTH_STATE="warn"
        STATUS_TEXT="Boot Wait Timeout"
        return 1
    fi

    boot_wait=0
    until [ "$(getprop init.svc.bootanim)" = "stopped" ] || [ "$boot_wait" -ge 60 ]; do
        sleep 2
        boot_wait=$((boot_wait + 2))
    done

    if [ "$(getprop init.svc.bootanim)" = "stopped" ]; then
        log_line "[PASS] Boot animation finished"
    else
        log_line "[SKIP] Boot animation state unavailable; continuing safely"
    fi

    sleep 10
    log_line "[PASS] System ready: post-boot grace period complete"
    return 0
}

log_irq_path_capability() {
    local patterns="$1"
    local label="$2"
    local found=0
    local available=0
    local irq_num

    for irq_num in $(grep -iE "$patterns" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
        found=$((found + 1))
        [ -e "/proc/irq/$irq_num/smp_affinity" ] && available=$((available + 1))
    done

    if [ "$found" -eq 0 ]; then
        log_line "[SKIP] $label Compatibility: no matching IRQs found"
    else
        log_line "[INFO] $label Compatibility: found $found | affinity paths $available"
    fi
}

log_compatibility_audit() {
    local page_cluster_path="/proc/sys/vm/page-cluster"
    local battery_temp_path="/sys/class/power_supply/battery/temp"
    local cc_path="/proc/sys/net/ipv4/tcp_congestion_control"
    local qdisc_path="/proc/sys/net/core/default_qdisc"
    local fastopen_path="/proc/sys/net/ipv4/tcp_fastopen"
    local dev
    local base
    local scheduler_path
    local scheduler_content
    local physical_devices="none"

    log_line ""
    log_line "[INFO] Compatibility Audit"

    if has_active_swap; then
        SWAP_ACTIVE=1
        log_line "[PASS] Swap/ZRAM: active"
    else
        SWAP_ACTIVE=0
        log_line "[SKIP] Swap/ZRAM: not active"
    fi

    if [ -e "$page_cluster_path" ]; then
        log_line "[PASS] VM Page Cluster Path: available"
        record_supported "VM Page Cluster Path"
    else
        log_line "[SKIP] VM Page Cluster Path: unavailable"
        record_unsupported "VM Page Cluster Path"
    fi

    refresh_battery_temp_state
    if [ -r "$battery_temp_path" ] && [ -n "$BATTERY_TEMP_DECIC" ]; then
        log_line "[PASS] Battery Temp Sensor: valid (${BATTERY_TEMP_LABEL})"
        record_supported "Battery Temp Sensor"
    else
        log_line "[SKIP] Battery Temp Sensor: unavailable or invalid"
        record_unsupported "Battery Temp Sensor"
    fi

    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        base="$(basename "$dev")"
        is_relevant_block_device "$base" "$dev" || continue

        if [ "$physical_devices" = "none" ]; then
            physical_devices="$base"
        else
            physical_devices="$physical_devices, $base"
        fi

        scheduler_path="$dev/queue/scheduler"
        if [ -e "$scheduler_path" ]; then
            scheduler_content="$(safe_read "$scheduler_path")"
            log_line "[INFO] Block Device ($base) Schedulers: ${scheduler_content:-unknown}"
            if scheduler_supports_value "$scheduler_content" "mq-deadline" || scheduler_supports_value "$scheduler_content" "none"; then
                log_line "[PASS] Block Scheduler ($base): scheduler options detected"
            else
                log_line "[SKIP] Block Scheduler ($base): known scheduler options not detected"
            fi
        else
            log_line "[SKIP] Block Scheduler ($base): scheduler path unavailable"
        fi
    done
    log_line "[INFO] Physical Block Devices Detected: $physical_devices"

    if [ -e "$qdisc_path" ]; then
        log_line "[PASS] Network Qdisc Path: available"
        record_supported "Network Qdisc Path"
    else
        log_line "[SKIP] Network Qdisc Path: unavailable"
        record_unsupported "Network Qdisc Path"
    fi

    if kernel_supports_tcp_cc "cubic"; then
        log_line "[PASS] TCP Congestion Control: cubic available"
        record_supported "TCP Congestion Control"
    else
        if [ -e "$cc_path" ]; then
            log_line "[SKIP] TCP Congestion Control: cubic unavailable"
        else
            log_line "[SKIP] TCP Congestion Control Path: unavailable"
        fi
        record_unsupported "TCP Congestion Control"
    fi

    if [ -e "$fastopen_path" ]; then
        log_line "[PASS] TCP Fast Open Path: available"
        record_supported "TCP Fast Open Path"
    else
        log_line "[SKIP] TCP Fast Open Path: unavailable"
        record_unsupported "TCP Fast Open Path"
    fi

    log_irq_path_capability "$STORAGE_IRQ_PATTERNS" "Storage/UFS IRQ"
    log_irq_path_capability "$NETWORK_IRQ_PATTERNS" "Wi-Fi/Network IRQ"
    log_irq_path_capability "$TOUCH_IRQ_PATTERNS" "Touch/Input IRQ"
}

apply_vm_tuning() {
    log_line ""
    log_line "[INFO] Virtual Memory Audit"

    case "$SELECTED_PROFILE" in
        performance_gaming)
            log_line "[INFO] Applying Performance / Gaming experimental VM tuning"
            safe_write_if_needed "/proc/sys/vm/vfs_cache_pressure" "70" "VFS Cache Pressure"
            safe_write_if_needed "/proc/sys/vm/dirty_background_ratio" "10" "VM Dirty Background Ratio"
            safe_write_if_needed "/proc/sys/vm/dirty_ratio" "25" "VM Dirty Ratio"
            safe_write_if_needed "/proc/sys/vm/dirty_writeback_centisecs" "1000" "VM Dirty Writeback"
            safe_write_if_needed "/proc/sys/vm/swappiness" "40" "VM Swappiness"
            ;;
        *)
            log_line "[INFO] Applying Active Smooth VM tuning"
            safe_write_if_needed "/proc/sys/vm/vfs_cache_pressure" "80" "VFS Cache Pressure"
            safe_write_if_needed "/proc/sys/vm/dirty_background_ratio" "5" "VM Dirty Background Ratio"
            safe_write_if_needed "/proc/sys/vm/dirty_ratio" "15" "VM Dirty Ratio"
            preserve_value "/proc/sys/vm/dirty_writeback_centisecs" "VM Dirty Writeback"
            preserve_value "/proc/sys/vm/swappiness" "VM Swappiness"
            ;;
    esac
}

apply_page_cluster() {
    local current_status

    log_line ""
    log_line "[INFO] Page Cluster Audit"

    if has_active_swap; then
        safe_write_if_needed "/proc/sys/vm/page-cluster" "0" "VM Page Cluster"
        current_status="$(safe_read /proc/sys/vm/page-cluster)"
        PAGE_CLUSTER_STATUS="${current_status:-unknown}"
    else
        log_line "[SKIP] VM Page Cluster: no active swap or zram detected"
        PAGE_CLUSTER_STATUS="Skipped (no swap/zram)"
    fi
}

set_read_ahead_floor() {
    local path="$1"
    local floor="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path unavailable"
        record_unsupported "$label"
        return 1
    fi

    current="$(safe_read "$path")"
    case "$current" in
        ''|*[!0-9]*)
            log_line "[SKIP] $label: non-numeric current value ${current:-unknown}"
            record_skipped "$label"
            return 1
            ;;
    esac

    if [ "$current" -ge "$floor" ]; then
        log_line "[PASS] $label: preserved current value $current"
        record_preserved "$label"
        return 0
    fi

    safe_write_if_needed "$path" "$floor" "$label"
}

apply_block_tuning() {
    local dev
    local base
    local processed_devices=""

    BLOCK_AUDITED_COUNT=0
    BLOCK_SKIPPED_COUNT=0
    BLOCK_AUDITED_LIST="none"

    log_line ""
    log_line "[INFO] Block I/O Audit"

    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        base="$(basename "$dev")"
        if ! is_relevant_block_device "$base" "$dev"; then
            BLOCK_SKIPPED_COUNT=$((BLOCK_SKIPPED_COUNT + 1))
            continue
        fi
        if [ -z "$processed_devices" ]; then
            processed_devices="$base"
        else
            processed_devices="$processed_devices, $base"
        fi
    done

    if [ -n "$processed_devices" ]; then
        BLOCK_AUDITED_LIST="$processed_devices"
    else
        fallback_devices="$(physical_block_status_fallback 2>/dev/null)"
        [ -n "$fallback_devices" ] && BLOCK_AUDITED_LIST="$fallback_devices"
    fi

    log_line "[INFO] Skipped virtual/stacked block devices: $BLOCK_SKIPPED_COUNT"
    log_line "[INFO] Physical block devices detected: $BLOCK_AUDITED_LIST"

    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        base="$(basename "$dev")"
        is_relevant_block_device "$base" "$dev" || continue

        BLOCK_AUDITED_COUNT=$((BLOCK_AUDITED_COUNT + 1))
        log_line "[INFO] Block Device ($base): processing"
        preserve_block_value "$dev/queue/scheduler" "Block Scheduler ($base)"
        if [ "$SELECTED_PROFILE" = "performance_gaming" ]; then
            set_read_ahead_floor "$dev/queue/read_ahead_kb" "512" "Block Read Ahead Performance ($base)"
        else
            preserve_block_value "$dev/queue/read_ahead_kb" "Block Read Ahead ($base)"
        fi

        if [ -e "$dev/queue/iostats" ]; then
            safe_write_if_needed "$dev/queue/iostats" "0" "Block IO Stats ($base)"
        else
            log_line "[SKIP] Block IO Stats ($base): path unavailable"
            record_unsupported "Block IO Stats ($base)"
        fi
    done

    log_line "[PASS] Block Device Scan: audited $BLOCK_AUDITED_COUNT devices, skipped $BLOCK_SKIPPED_COUNT"
}

apply_network_tuning() {
    local cc_available="/proc/sys/net/ipv4/tcp_available_congestion_control"
    local current_cc
    local qdisc_current
    local qdisc_ok="preserved"
    local cc_ok="no"
    local fastopen_ok="no"
    local desired_cc="cubic"

    log_line ""
    log_line "[INFO] Network Audit"

    if [ -e /proc/sys/net/core/default_qdisc ]; then
        qdisc_current="$(safe_read /proc/sys/net/core/default_qdisc)"
        log_line "[PASS] Network Qdisc: preserved current value ${qdisc_current:-unknown}"
        record_preserved "Network Qdisc"
    else
        log_line "[SKIP] Network Qdisc: path unavailable"
        qdisc_ok="unavailable"
        record_unsupported "Network Qdisc"
    fi

    if [ "$SELECTED_PROFILE" = "performance_gaming" ] && kernel_supports_tcp_cc "bbr"; then
        desired_cc="bbr"
        log_line "[INFO] Performance / Gaming: BBR available, using experimental TCP congestion target"
    fi

    if [ -e "$cc_available" ]; then
        if kernel_supports_tcp_cc "$desired_cc"; then
            if safe_write_if_needed "/proc/sys/net/ipv4/tcp_congestion_control" "$desired_cc" "TCP Congestion Control"; then
                cc_ok="yes:$desired_cc"
            fi
        else
            log_line "[SKIP] TCP Congestion Control: $desired_cc not supported on this kernel"
            record_unsupported "TCP Congestion Control"
        fi
    elif [ -e /proc/sys/net/ipv4/tcp_congestion_control ]; then
        current_cc="$(safe_read /proc/sys/net/ipv4/tcp_congestion_control)"
        if [ "$current_cc" = "$desired_cc" ]; then
            log_line "[PASS] TCP Congestion Control: already set to $desired_cc"
            cc_ok="yes:$desired_cc"
            record_supported "TCP Congestion Control"
        else
            log_line "[SKIP] TCP Congestion Control: availability unknown on this kernel"
            record_skipped "TCP Congestion Control"
        fi
    else
        log_line "[SKIP] TCP Congestion Control: path unavailable"
        record_unsupported "TCP Congestion Control"
    fi

    if safe_write_if_needed "/proc/sys/net/ipv4/tcp_fastopen" "1" "TCP Fast Open"; then
        fastopen_ok="yes"
    fi

    NETWORK_CAPABILITY_SUMMARY="qdisc=$qdisc_ok, cc=$cc_ok, tcp_fastopen=$fastopen_ok"
}

set_irq_affinity_value() {
    local path="$1"
    local mask="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: affinity path unavailable"
        return 2
    fi

    if [ ! -w "$path" ]; then
        log_line "[SKIP] $label: affinity path not writable"
        return 3
    fi

    current="$(safe_read "$path")"
    if [ "$current" = "$mask" ]; then
        log_line "[PASS] $label: already set to $mask"
        return 0
    fi

    if echo "$mask" > "$path" 2>/dev/null; then
        current="$(safe_read "$path")"
        if [ "$current" = "$mask" ]; then
            log_line "[PASS] $label: applied $mask"
            return 0
        fi
    fi

    log_line "[SKIP] $label: write rejected by kernel; keeping default routing"
    return 1
}

apply_irq_affinity() {
    local patterns="$1"
    local mask="$2"
    local label="$3"
    local found=0
    local applied=0
    local rejected=0
    local omitted=0
    local irq_num
    local rc
    local summary

    for irq_num in $(grep -iE "$patterns" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
        found=$((found + 1))
        set_irq_affinity_value "/proc/irq/$irq_num/smp_affinity" "$mask" "$label IRQ $irq_num"
        rc=$?
        case "$rc" in
            0)
                applied=$((applied + 1))
                record_applied "$label IRQ $irq_num"
                ;;
            1) rejected=$((rejected + 1)) ;;
            *) omitted=$((omitted + 1)) ;;
        esac
    done

    [ "$found" -eq 0 ] && log_line "[SKIP] $label: no matching IRQs found"

    summary="found $found | applied $applied | rejected $rejected | omitted $omitted"
    log_line "[PASS] $label Summary: $summary"

    case "$label" in
        "Storage/UFS IRQ") IRQ_SUMMARY_STORAGE="$summary" ;;
        "Wi-Fi/Network IRQ") IRQ_SUMMARY_NETWORK="$summary" ;;
        "Touch/Input IRQ") IRQ_SUMMARY_TOUCH="$summary" ;;
    esac
}

apply_selective_irq_affinity() {
    local irq_mask="70"

    log_line ""
    log_line "[INFO] Selective IRQ Affinity Audit"

    if [ "$SELECTED_PROFILE" = "performance_gaming" ]; then
        irq_mask="f0"
        log_line "[INFO] Performance / Gaming: using experimental IRQ affinity mask $irq_mask"
    fi

    apply_irq_affinity "$STORAGE_IRQ_PATTERNS" "$irq_mask" "Storage/UFS IRQ"
    apply_irq_affinity "$NETWORK_IRQ_PATTERNS" "$irq_mask" "Wi-Fi/Network IRQ"
    apply_irq_affinity "$TOUCH_IRQ_PATTERNS" "$irq_mask" "Touch/Input IRQ"
}

number_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN { if ((a + 0) >= (b + 0)) exit 0; exit 1 }' 2>/dev/null
}

gpu_state_has() {
    local kind="$1"
    local path="$2"
    [ -r "$GPU_STATE_FILE" ] || return 1
    grep -F "${kind}|${path}|" "$GPU_STATE_FILE" >/dev/null 2>&1
}

gpu_state_save() {
    local kind="$1"
    local path="$2"
    local value="$3"
    [ -n "$kind" ] && [ -n "$path" ] || return 0
    gpu_state_has "$kind" "$path" && return 0
    printf '%s|%s|%s\n' "$kind" "$path" "$value" >> "$GPU_STATE_FILE" 2>/dev/null
    chmod 0644 "$GPU_STATE_FILE" 2>/dev/null
}

gpu_restore_policy() {
    local kind
    local path
    local value
    local restored=0

    [ -r "$GPU_STATE_FILE" ] || return 0

    while IFS='|' read -r kind path value; do
        [ -n "$kind" ] && [ -n "$path" ] || continue
        [ -e "$path" ] || continue
        [ -w "$path" ] || continue
        if printf '%s' "$value" > "$path" 2>/dev/null; then
            restored=$((restored + 1))
        fi
    done < "$GPU_STATE_FILE"

    if [ "$restored" -gt 0 ]; then
        log_line "[PASS] GPU Policy Restore: restored $restored saved GPU setting(s) for non-gaming profile"
        record_applied "GPU Policy Restore"
    fi
}

gpu_text_matches() {
    case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
        *gpu*|*mali*|*g3d*|*kgsl*|*adreno*|*bifrost*|*valhall*|*panfrost*) return 0 ;;
    esac
    return 1
}

gpu_devfreq_candidate() {
    local dir="$1"
    local text
    local link

    [ -d "$dir" ] || return 1

    text="$(basename "$dir")"
    [ -r "$dir/name" ] && text="$text $(safe_read "$dir/name")"
    [ -r "$dir/device/uevent" ] && text="$text $(safe_read "$dir/device/uevent")"
    link="$(readlink -f "$dir" 2>/dev/null)"
    [ -n "$link" ] && text="$text $link"
    link="$(readlink -f "$dir/device" 2>/dev/null)"
    [ -n "$link" ] && text="$text $link"

    gpu_text_matches "$text"
}

gpu_collect_governor_paths() {
    local path
    local dir
    local seen=""
    for path in \
        /sys/class/devfreq/*/governor \
        /sys/devices/platform/*mali*/devfreq/*/governor \
        /sys/devices/platform/*gpu*/devfreq/*/governor \
        /sys/devices/*/*mali*/devfreq/*/governor \
        /sys/devices/*/*gpu*/devfreq/*/governor \
        /sys/class/kgsl/kgsl-3d0/devfreq/governor \
        /sys/class/kgsl/kgsl-3d0/devfreq/*/governor \
        /sys/class/misc/mali*/device/devfreq/*/governor; do
        [ -e "$path" ] || continue
        dir="${path%/governor}"
        gpu_devfreq_candidate "$dir" || continue
        case "$seen" in
            *"|$path|"*) continue ;;
        esac
        seen="${seen}|${path}|"
        printf '%s\n' "$path"
    done
}

graphics_devfreq_candidate() {
    local dir="$1"
    local text

    [ -d "$dir" ] || return 1
    text="$(basename "$dir")"
    [ -r "$dir/name" ] && text="$text $(safe_read "$dir/name")"
    text="$(printf '%s' "$text" | tr 'A-Z' 'a-z')"

    case "$text" in
        *devfreq_mif*|*devfreq_int*|*devfreq_disp*) return 0 ;;
    esac

    return 1
}

graphics_collect_governor_paths() {
    local path
    local dir
    local seen=""

    for path in /sys/class/devfreq/*/governor; do
        [ -e "$path" ] || continue
        dir="${path%/governor}"
        graphics_devfreq_candidate "$dir" || continue
        case "$seen" in
            *"|$path|"*) continue ;;
        esac
        seen="${seen}|${path}|"
        printf '%s\n' "$path"
    done
}

choose_gpu_floor_freq() {
    awk '
        {
            for (i = 1; i <= NF; i++) {
                v = $i + 0
                if (v > 0) {
                    n++
                    a[n] = v
                    if (v > max) max = v
                }
            }
        }
        END {
            if (n == 0 || max <= 0) exit 1
            target = max * 0.35
            best = max
            for (i = 1; i <= n; i++) {
                if (a[i] >= target && a[i] < best) best = a[i]
            }
            printf "%.0f", best
        }
    ' 2>/dev/null
}

max_gpu_freq() {
    awk '{ for (i = 1; i <= NF; i++) if (($i + 0) > max) max = $i + 0 } END { if (max > 0) printf "%.0f", max }' 2>/dev/null
}

apply_gpu_devfreq_policy() {
    local gov_path="$1"
    local gov_dir
    local dev_name
    local avail_gov
    local avail_freq
    local max_avail
    local floor_freq
    local current

    [ -e "$gov_path" ] || return 1
    gov_dir="${gov_path%/governor}"
    dev_name="$(basename "$gov_dir")"

    log_line "[INFO] GPU Devfreq Node ($dev_name): $gov_dir"
    [ -r "$gov_dir/available_governors" ] && log_line "[INFO] GPU Available Governors ($dev_name): $(safe_read "$gov_dir/available_governors")"
    [ -r "$gov_dir/available_frequencies" ] && log_line "[INFO] GPU Available Frequencies ($dev_name): $(safe_read "$gov_dir/available_frequencies")"

    if [ -r "$gov_path" ]; then
        gpu_state_save "governor" "$gov_path" "$(safe_read "$gov_path")"
    fi

    avail_gov="$(safe_read "$gov_dir/available_governors")"
    if [ -n "$avail_gov" ]; then
        case " $avail_gov " in
            *" performance "*) experimental_write_if_needed "$gov_path" "performance" "GPU Devfreq Governor ($dev_name)" ;;
            *)
                log_line "[SKIP] GPU Devfreq Governor ($dev_name): performance governor unavailable; using frequency floor fallback"
                record_skipped "GPU Devfreq Governor ($dev_name)"
                ;;
        esac
    else
        log_line "[SKIP] GPU Devfreq Governor ($dev_name): available governors unavailable; using frequency floor fallback"
        record_skipped "GPU Devfreq Governor ($dev_name)"
    fi

    avail_freq="$(safe_read "$gov_dir/available_frequencies")"
    if [ -z "$avail_freq" ]; then
        log_line "[SKIP] GPU Frequency Floor ($dev_name): available frequencies unavailable"
        record_skipped "GPU Frequency Floor ($dev_name)"
        return 0
    fi

    floor_freq="$(printf '%s\n' "$avail_freq" | choose_gpu_floor_freq)"
    max_avail="$(printf '%s\n' "$avail_freq" | max_gpu_freq)"

    if [ -n "$max_avail" ] && [ -e "$gov_dir/max_freq" ] && [ -w "$gov_dir/max_freq" ]; then
        gpu_state_save "max_freq" "$gov_dir/max_freq" "$(safe_read "$gov_dir/max_freq")"
        current="$(safe_read "$gov_dir/max_freq")"
        if number_ge "$current" "$max_avail"; then
            log_line "[PASS] GPU Max Frequency ($dev_name): already at maximum ${current:-$max_avail}"
            record_supported "GPU Max Frequency ($dev_name)"
        else
            experimental_write_if_needed "$gov_dir/max_freq" "$max_avail" "GPU Max Frequency ($dev_name)"
        fi
    else
        log_line "[SKIP] GPU Max Frequency ($dev_name): max_freq unavailable or not writable"
        record_skipped "GPU Max Frequency ($dev_name)"
    fi

    if [ -n "$floor_freq" ] && [ -e "$gov_dir/min_freq" ] && [ -w "$gov_dir/min_freq" ]; then
        gpu_state_save "min_freq" "$gov_dir/min_freq" "$(safe_read "$gov_dir/min_freq")"
        current="$(safe_read "$gov_dir/min_freq")"
        if number_ge "$current" "$floor_freq"; then
            log_line "[PASS] GPU Frequency Floor ($dev_name): preserved current floor ${current:-$floor_freq}"
            record_preserved "GPU Frequency Floor ($dev_name)"
        else
            experimental_write_if_needed "$gov_dir/min_freq" "$floor_freq" "GPU Frequency Floor ($dev_name)"
        fi
    else
        log_line "[SKIP] GPU Frequency Floor ($dev_name): min_freq unavailable or not writable"
        record_skipped "GPU Frequency Floor ($dev_name)"
    fi
}

apply_graphics_pipeline_boost() {
    local gov_path
    local gov_dir
    local dev_name
    local avail_freq
    local floor_freq
    local current
    local boosted=0

    log_line "[INFO] Graphics Pipeline Boost: tuning Tensor graphics-related devfreq floors"

    while IFS= read -r gov_path; do
        [ -n "$gov_path" ] || continue
        [ -e "$gov_path" ] || continue
        gov_dir="${gov_path%/governor}"
        dev_name="$(basename "$gov_dir")"
        avail_freq="$(safe_read "$gov_dir/available_frequencies")"

        if [ -z "$avail_freq" ]; then
            log_line "[SKIP] Graphics Pipeline Floor ($dev_name): available frequencies unavailable"
            record_skipped "Graphics Pipeline Floor ($dev_name)"
            continue
        fi

        floor_freq="$(printf '%s\n' "$avail_freq" | choose_gpu_floor_freq)"
        if [ -z "$floor_freq" ]; then
            log_line "[SKIP] Graphics Pipeline Floor ($dev_name): unable to select safe floor"
            record_skipped "Graphics Pipeline Floor ($dev_name)"
            continue
        fi

        log_line "[INFO] Graphics Pipeline Node ($dev_name): $gov_dir"
        log_line "[INFO] Graphics Pipeline Frequencies ($dev_name): $avail_freq"

        if [ -e "$gov_dir/min_freq" ] && [ -w "$gov_dir/min_freq" ]; then
            gpu_state_save "graphics_min_freq" "$gov_dir/min_freq" "$(safe_read "$gov_dir/min_freq")"
            current="$(safe_read "$gov_dir/min_freq")"
            if number_ge "$current" "$floor_freq"; then
                log_line "[PASS] Graphics Pipeline Floor ($dev_name): preserved current floor ${current:-$floor_freq}"
                record_preserved "Graphics Pipeline Floor ($dev_name)"
            else
                if experimental_write_if_needed "$gov_dir/min_freq" "$floor_freq" "Graphics Pipeline Floor ($dev_name)"; then
                    boosted=$((boosted + 1))
                fi
            fi
        else
            log_line "[SKIP] Graphics Pipeline Floor ($dev_name): min_freq unavailable or not writable"
            record_skipped "Graphics Pipeline Floor ($dev_name)"
        fi
    done <<EOF_GRAPHICS_GOVS
$(graphics_collect_governor_paths)
EOF_GRAPHICS_GOVS

    if [ "$boosted" -gt 0 ]; then
        log_line "[PASS] Graphics Pipeline Boost: applied $boosted devfreq floor adjustment(s)"
        record_applied "Graphics Pipeline Boost"
    else
        log_line "[INFO] Graphics Pipeline Boost: no additional floor adjustment required"
    fi
}


apply_performance_experimental_tuning() {
    local gov_path
    local found_gpu=0

    log_line ""
    log_line "[INFO] Performance / Gaming Experimental Audit"

    if [ "$SELECTED_PROFILE" != "performance_gaming" ]; then
        gpu_restore_policy
        log_line "[SKIP] Performance / Gaming: inactive"
        return 0
    fi

    log_line "[INFO] Performance / Gaming: applying experimental CPU/GPU responsiveness tuning"

    experimental_write_if_needed "/dev/cpuctl/top-app/cpu.uclamp.min" "15" "Top-App UClamp Min"
    experimental_write_if_needed "/dev/cpuctl/top-app/cpu.uclamp.max" "100" "Top-App UClamp Max"
    experimental_write_if_needed "/dev/cpuctl/top-app/cpu.uclamp.latency_sensitive" "1" "Top-App Latency Sensitive"
    experimental_write_if_needed "/dev/cpuctl/foreground/cpu.uclamp.min" "5" "Foreground UClamp Min"
    experimental_write_if_needed "/dev/cpuctl/foreground/cpu.uclamp.max" "100" "Foreground UClamp Max"

    while IFS= read -r gov_path; do
        [ -n "$gov_path" ] || continue
        found_gpu=$((found_gpu + 1))
        apply_gpu_devfreq_policy "$gov_path"
    done <<EOF_GPU_GOVS
$(gpu_collect_governor_paths)
EOF_GPU_GOVS

    if [ "$found_gpu" -eq 0 ]; then
        log_line "[SKIP] Direct GPU Devfreq Policy: no supported direct GPU devfreq node found"
        log_line "[INFO] GPU Devfreq Discovery: available devfreq nodes follow"
        for gov_path in /sys/class/devfreq/*/governor; do
            [ -e "$gov_path" ] || continue
            log_line "[INFO] Devfreq Node: $(basename "${gov_path%/governor}") | governor=$(safe_read "$gov_path") | available=$(safe_read "${gov_path%/governor}/available_governors")"
        done
        record_skipped "Direct GPU Devfreq Policy"
    fi

    apply_graphics_pipeline_boost

    write_thermal_request "gaming"
    log_line "[PASS] Thermal Control Target: gaming request updated"
}

verify_post_apply() {
    local dev
    local base
    local scheduler
    local read_ahead
    local iostats
    local qdisc
    local cc
    local fastopen

    log_line ""
    log_line "[INFO] Post-Apply Verification"
    log_line "[INFO] VFS Cache Pressure: current=$(safe_read /proc/sys/vm/vfs_cache_pressure)"
    log_line "[INFO] VM Dirty Background Ratio: current=$(safe_read /proc/sys/vm/dirty_background_ratio)"
    log_line "[INFO] VM Dirty Ratio: current=$(safe_read /proc/sys/vm/dirty_ratio)"
    log_line "[INFO] VM Swappiness: current=$(safe_read /proc/sys/vm/swappiness)"
    log_line "[INFO] VM Page Cluster: current=$(safe_read /proc/sys/vm/page-cluster)"

    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        base="$(basename "$dev")"
        is_relevant_block_device "$base" "$dev" || continue
        scheduler="$(safe_read "$dev/queue/scheduler")"
        read_ahead="$(safe_read "$dev/queue/read_ahead_kb")"
        iostats="$(safe_read "$dev/queue/iostats")"
        log_line "[INFO] Block Verify ($base): scheduler=${scheduler:-unknown} | read_ahead=${read_ahead:-unknown} | iostats=${iostats:-unknown}"
    done

    qdisc="$(safe_read /proc/sys/net/core/default_qdisc)"
    cc="$(safe_read /proc/sys/net/ipv4/tcp_congestion_control)"
    fastopen="$(safe_read /proc/sys/net/ipv4/tcp_fastopen)"
    log_line "[INFO] Network Verify: qdisc=${qdisc:-unknown} | cc=${cc:-unknown} | fastopen=${fastopen:-unknown}"
    if [ "$SELECTED_PROFILE" = "performance_gaming" ]; then
        log_line "[INFO] Performance Verify: top_app_uclamp_min=$(safe_read /dev/cpuctl/top-app/cpu.uclamp.min) | foreground_uclamp_min=$(safe_read /dev/cpuctl/foreground/cpu.uclamp.min)"
        while IFS= read -r gov_path; do
            [ -n "$gov_path" ] || continue
            gov_dir="${gov_path%/governor}"
            log_line "[INFO] GPU Verify ($(basename "$gov_dir")): governor=$(safe_read "$gov_path") | min_freq=$(safe_read "$gov_dir/min_freq") | max_freq=$(safe_read "$gov_dir/max_freq")"
        done <<EOF_GPU_VERIFY
$(gpu_collect_governor_paths)
EOF_GPU_VERIFY
        while IFS= read -r gov_path; do
            [ -n "$gov_path" ] || continue
            [ -e "$gov_path" ] || continue
            gov_dir="${gov_path%/governor}"
            log_line "[INFO] Graphics Pipeline Verify ($(basename "$gov_dir")): governor=$(safe_read "$gov_path") | min_freq=$(safe_read "$gov_dir/min_freq") | max_freq=$(safe_read "$gov_dir/max_freq")"
        done <<EOF_GRAPHICS_VERIFY
$(graphics_collect_governor_paths)
EOF_GRAPHICS_VERIFY
    fi
}

thermal_module_bases() {
    echo "/data/adb/modules /data/adb/modules_update /data/adb/ksu/modules /data/adb/ksu/modules_update /data/adb/ap/modules /data/adb/ap/modules_update"
}

thermal_addon_dir() {
    local base direct dir prop known_ids id id_line name_line ident reg_dir

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
    local addon_dir
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

integrated_thermal_overlay_active() {
    [ -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config.json" ] || return 1
    [ -f "$INTEGRATED_THERMAL_ACTIVE_DIR/thermal_info_config_lpm.json" ] || return 1
    return 0
}

read_integrated_thermal_profile() {
    local value
    [ -r "$INTEGRATED_THERMAL_PROFILE_FILE" ] && value="$(tr -d '\r\n' < "$INTEGRATED_THERMAL_PROFILE_FILE" 2>/dev/null)"
    [ -z "$value" ] && value="$(env_value THERMAL_CONTROL_PROFILE "$INTEGRATED_THERMAL_STATE")"
    case "$value" in
        balanced|gaming|charge_cool) echo "$value" ;;
        *) echo "$THERMAL_PROFILE_REQUEST" ;;
    esac
}

emit_integrated_thermal_status() {
    local available enabled profile overlay reboot message
    available=0
    integrated_thermal_available && available=1
    enabled=0
    [ "$(env_value THERMAL_CONTROL_ENABLED "$INTEGRATED_THERMAL_STATE")" = "1" ] && enabled=1
    profile="$(read_integrated_thermal_profile)"
    [ -z "$profile" ] && profile="balanced"
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

detect_thermal_addon() {
    local addon_dir prop addon_state reg_installed reg_version reg_state

    if [ -d "$INTEGRATED_THERMAL_PROFILES" ]; then
        THERMAL_ADDON_INSTALLED=1
        if [ "$(env_value THERMAL_CONTROL_ENABLED "$INTEGRATED_THERMAL_STATE")" = "1" ]; then
            THERMAL_ADDON_VERSION="integrated (on)"
        else
            THERMAL_ADDON_VERSION="integrated (off)"
        fi
        return 0
    fi

    addon_dir="$(thermal_addon_dir)"
    if [ -n "$addon_dir" ]; then
        THERMAL_ADDON_INSTALLED=1
        prop="$(grep -im1 '^version=' "$addon_dir/module.prop" 2>/dev/null | cut -d= -f2-)"
        THERMAL_ADDON_VERSION="${prop:-installed}"
        addon_state="$(thermal_addon_state_label "$addon_dir")"
        case "$addon_state" in
            active) : ;;
            *) THERMAL_ADDON_VERSION="$THERMAL_ADDON_VERSION ($addon_state)" ;;
        esac
        return 0
    fi

    if [ -r "$THERMAL_STATUS_ENV" ]; then
        reg_installed="$(env_value THERMAL_CONTROL_INSTALLED "$THERMAL_STATUS_ENV")"
        reg_version="$(env_value THERMAL_CONTROL_VERSION "$THERMAL_STATUS_ENV")"
        reg_state="$(env_value THERMAL_CONTROL_STATE "$THERMAL_STATUS_ENV")"
        if [ "$reg_installed" = "1" ] || [ -n "$reg_version" ]; then
            THERMAL_ADDON_INSTALLED=1
            THERMAL_ADDON_VERSION="${reg_version:-installed}"
            case "$reg_state" in
                ''|active) : ;;
                *) THERMAL_ADDON_VERSION="$THERMAL_ADDON_VERSION ($reg_state)" ;;
            esac
            return 0
        fi
    fi

    THERMAL_ADDON_INSTALLED=0
    THERMAL_ADDON_VERSION="none"
}

write_addon_api() {
    local tmp="$ADDON_API_ENV.tmp.$$"

    detect_thermal_addon
    write_thermal_request "${THERMAL_PROFILE_REQUEST:-balanced}"
    {
        write_env_pair "API_VERSION" "1"
        write_env_pair "SUPERCHARGER_VERSION" "$PROFILE_VERSION"
        write_env_pair "SUPERCHARGER_MODULE_ID" "p9pxl_supercharger"
        write_env_pair "SUPERCHARGER_MODULE_DIR" "$MODDIR"
        write_env_pair "SUPERCHARGER_PROFILE_MODE" "$PROFILE_MODE"
        write_env_pair "SUPERCHARGER_ACTIVE_PROFILE" "$SELECTED_PROFILE"
        write_env_pair "SUPERCHARGER_PROFILE_LABEL" "$PROFILE_LABEL"
        write_env_pair "SUPERCHARGER_THERMAL_PROFILE_REQUEST" "$THERMAL_PROFILE_REQUEST"
        write_env_pair "SUPERCHARGER_PERFORMANCE_ENGINE_STATE" "$PERFORMANCE_ENGINE_STATE"
        write_env_pair "SUPERCHARGER_HEALTH" "$HEALTH_STATE"
        write_env_pair "ANDROID_RELEASE" "$ANDROID_RELEASE"
        write_env_pair "ANDROID_SDK" "$ANDROID_SDK"
        write_env_pair "DEVICE" "$DEVICE"
        write_env_pair "MODEL" "$MODEL"
        write_env_pair "ROOT_ENV" "$ROOT_ENV"
        write_env_pair "THERMAL_ADDON_INSTALLED" "$THERMAL_ADDON_INSTALLED"
        write_env_pair "THERMAL_ADDON_VERSION" "$THERMAL_ADDON_VERSION"
        emit_integrated_thermal_status
        write_env_pair "LAST_UPDATED" "$(date)"
    } > "$tmp"
    chmod 0644 "$tmp" 2>/dev/null
    mv -f "$tmp" "$ADDON_API_ENV" 2>/dev/null
}

get_dashboard_status() {
    local temp_decic="$1"
    local temp_ui

    temp_ui="$(format_temp_label "$temp_decic")"
    if [ "$HEALTH_STATE" = "warn" ] || grep -q "\[FAIL\]" "$LOG_FILE" 2>/dev/null; then
        echo "Status: ${PROFILE_VERSION} | ${temp_ui} | Check audit"
    else
        echo "Status: ${PROFILE_VERSION} | ${temp_ui} | ${PROFILE_LABEL}"
    fi
}

update_dashboard() {
    local force_log="$1"
    local temp_decic="$2"
    local status
    local current_line

    status="$(get_dashboard_status "$temp_decic")"
    current_line="$(grep '^description=' "$PROP_FILE" 2>/dev/null)"

    if [ "$current_line" = "description=$status" ]; then
        [ "$force_log" = "1" ] && log_line "[PASS] Dashboard: description already up to date"
        return 0
    fi

    if set_module_description "$status"; then
        log_line "[PASS] Dashboard: description updated"
        return 0
    fi

    log_line "[FAIL] Dashboard: unable to update module.prop"
    HEALTH_STATE="warn"
    return 1
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

write_updater_record() {
    printf '%s\n%s\n' "$1" "$(current_boot_id)" > "$PIDFILE"
}

write_module_status_env() {
    local tmp="$STATUS_ENV.tmp.$$"
    local updater_pid="none"
    local updater_state="stopped"
    local status_block_list="${BLOCK_AUDITED_LIST:-none}"

    if [ -z "$status_block_list" ] || [ "$status_block_list" = "none" ] || [ "$status_block_list" = "Not reported" ]; then
        status_block_list="$(physical_block_status_fallback 2>/dev/null)"
        [ -z "$status_block_list" ] && status_block_list="none"
    fi


    if [ -f "$PIDFILE" ]; then
        updater_pid="$(read_updater_pid)"
        case "$updater_pid" in
            ''|*[!0-9]*) updater_pid="invalid"; updater_state="stale" ;;
            *)
                if updater_record_alive "$updater_pid"; then
                    updater_state="running"
                else
                    updater_state="stale"
                fi
                ;;
        esac
    fi

    {
        write_env_pair "MODULE_ID" "p9pxl_supercharger"
        write_env_pair "VERSION" "$PROFILE_VERSION"
        write_env_pair "STATUS" "$STATUS_TEXT"
        write_env_pair "HEALTH" "$HEALTH_STATE"
        write_env_pair "PROFILE_MODE" "$PROFILE_MODE"
        write_env_pair "SELECTED_PROFILE" "$SELECTED_PROFILE"
        write_env_pair "PROFILE_LABEL" "$PROFILE_LABEL"
        write_env_pair "THERMAL_PROFILE_REQUEST" "$THERMAL_PROFILE_REQUEST"
        write_env_pair "PERFORMANCE_ENGINE_STATE" "$PERFORMANCE_ENGINE_STATE"
        write_env_pair "ANDROID_RELEASE" "$ANDROID_RELEASE"
        write_env_pair "ANDROID_SDK" "$ANDROID_SDK"
        write_env_pair "BUILD_ID" "$BUILD_ID"
        write_env_pair "BUILD_INCREMENTAL" "$BUILD_INCREMENTAL"
        write_env_pair "KERNEL_RELEASE" "$KERNEL_RELEASE"
        write_env_pair "ROOT_ENV" "$ROOT_ENV"
        write_env_pair "DEVICE" "$DEVICE"
        write_env_pair "MODEL" "$MODEL"
        write_env_pair "BATTERY_TEMP" "$BATTERY_TEMP_LABEL"
        write_env_pair "SWAP_ACTIVE" "$SWAP_ACTIVE"
        write_env_pair "PAGE_CLUSTER_STATUS" "$PAGE_CLUSTER_STATUS"
        write_env_pair "BLOCK_AUDITED_LIST" "$status_block_list"
        write_env_pair "BLOCK_SKIPPED_COUNT" "$BLOCK_SKIPPED_COUNT"
        write_env_pair "NETWORK_CAPABILITY_SUMMARY" "$NETWORK_CAPABILITY_SUMMARY"
        write_env_pair "IRQ_STORAGE_SUMMARY" "$IRQ_SUMMARY_STORAGE"
        write_env_pair "IRQ_NETWORK_SUMMARY" "$IRQ_SUMMARY_NETWORK"
        write_env_pair "IRQ_TOUCH_SUMMARY" "$IRQ_SUMMARY_TOUCH"
        write_env_pair "THERMAL_ADDON_INSTALLED" "$THERMAL_ADDON_INSTALLED"
        write_env_pair "THERMAL_ADDON_VERSION" "$THERMAL_ADDON_VERSION"
        emit_integrated_thermal_status
        write_env_pair "DASHBOARD_UPDATER_PID" "$updater_pid"
        write_env_pair "DASHBOARD_UPDATER_STATE" "$updater_state"
        write_env_pair "LOG_FILE" "$LOG_FILE"
        write_env_pair "SNAPSHOT_FILE" "$SNAPSHOT_FILE"
        write_env_pair "LAST_UPDATED" "$(date)"
    } > "$tmp"
    chmod 0644 "$tmp" 2>/dev/null
    mv -f "$tmp" "$STATUS_ENV" 2>/dev/null
}

write_support_snapshot() {
    {
        echo "Supercharger Support Snapshot"
        echo "Version: $PROFILE_VERSION"
        echo "Status: $STATUS_TEXT"
        echo "Health: $HEALTH_STATE"
        echo "Profile Mode: ${PROFILE_MODE:-unknown}"
        echo "Selected Profile: ${SELECTED_PROFILE:-active_smooth}"
        echo "Thermal Profile Request: ${THERMAL_PROFILE_REQUEST:-balanced}"
        echo "Performance Engine: ${PERFORMANCE_ENGINE_STATE:-stable}"
        echo "Android Release: ${ANDROID_RELEASE:-unknown}"
        echo "SDK: ${ANDROID_SDK:-unknown}"
        echo "Build ID: ${BUILD_ID:-unknown}"
        echo "Incremental: ${BUILD_INCREMENTAL:-unknown}"
        echo "Kernel: ${KERNEL_RELEASE:-unknown}"
        echo "Root Environment: ${ROOT_ENV:-Unknown}"
        echo "Model: ${MODEL:-unknown}"
        echo "Codename: ${DEVICE:-unknown}"
        echo "Battery Temp: ${BATTERY_TEMP_LABEL:-Temp Unavailable}"
        echo "Swap Active: ${SWAP_ACTIVE}"
        echo "Page Cluster Status: ${PAGE_CLUSTER_STATUS:-unknown}"
        echo "Audited Block Devices: ${BLOCK_AUDITED_LIST:-none}"
        echo "Skipped Block Devices: ${BLOCK_SKIPPED_COUNT:-0}"
        echo "Network Capability Summary: ${NETWORK_CAPABILITY_SUMMARY:-unknown}"
        echo "IRQ Storage Summary: ${IRQ_SUMMARY_STORAGE:-unknown}"
        echo "IRQ Network Summary: ${IRQ_SUMMARY_NETWORK:-unknown}"
        echo "IRQ Touch Summary: ${IRQ_SUMMARY_TOUCH:-unknown}"
        echo "Thermal Addon Installed: ${THERMAL_ADDON_INSTALLED}"
        echo "Thermal Addon Version: ${THERMAL_ADDON_VERSION:-none}"
        echo "GPU Policy State: ${GPU_STATE_FILE}"
        echo "Supported Capabilities: ${SUPPORTED_CAPABILITIES:-none}"
        echo "Unsupported Capabilities: ${UNSUPPORTED_CAPABILITIES:-none}"
        echo "Skipped Safely: ${SKIPPED_CAPABILITIES:-none}"
        echo "Preserved Successfully: ${PRESERVED_CAPABILITIES:-none}"
        echo "Applied Successfully: ${APPLIED_CAPABILITIES:-none}"
        echo "Generated: $(date)"
    } > "$SNAPSHOT_FILE"
}

log_thermal_addon_audit() {
    log_line ""
    log_line "[INFO] Thermal Addon Audit"
    detect_thermal_addon
    if [ "$THERMAL_ADDON_INSTALLED" = "1" ]; then
        log_line "[PASS] Thermal Control Addon: installed (${THERMAL_ADDON_VERSION})"
    else
        log_line "[SKIP] Thermal Control Addon: not installed"
    fi
    write_addon_api
    log_line "[PASS] Addon API: updated"
}

log_support_summary() {
    log_line ""
    log_line "[INFO] Dashboard Audit"
    log_line "[INFO] Support Snapshot: $SNAPSHOT_FILE"
    log_line "[INFO] Module Status Env: $STATUS_ENV"
    log_line "[INFO] Addon API: $ADDON_API_ENV"
    log_line "[INFO] Supported Capabilities: ${SUPPORTED_CAPABILITIES:-none}"
    log_line "[INFO] Unsupported Capabilities: ${UNSUPPORTED_CAPABILITIES:-none}"
    log_line "[INFO] Skipped Safely: ${SKIPPED_CAPABILITIES:-none}"
    log_line "[INFO] Preserved Successfully: ${PRESERVED_CAPABILITIES:-none}"
    log_line "[INFO] Applied Successfully: ${APPLIED_CAPABILITIES:-none}"
}

start_temp_dashboard_updater() {
    local initial_temp="$1"
    local old_pid
    local pid

    if [ -f "$PIDFILE" ]; then
        old_pid="$(read_updater_pid)"
        case "$old_pid" in
            ''|*[!0-9]*)
                rm -f "$PIDFILE" 2>/dev/null
                rm -rf "$LOCKDIR" 2>/dev/null
                ;;
            *)
                if updater_record_alive "$old_pid"; then
                    log_line "[PASS] Dashboard updater: already running (pid=$old_pid)"
                    return 0
                fi
                rm -f "$PIDFILE" 2>/dev/null
                rm -rf "$LOCKDIR" 2>/dev/null
                ;;
        esac
    fi

    if ! mkdir "$LOCKDIR" 2>/dev/null; then
        log_line "[SKIP] Dashboard updater: lock exists; not starting duplicate"
        return 0
    fi

    (
        last_temp_decic="$initial_temp"
        trap 'rm -f "$PIDFILE" 2>/dev/null; rm -rf "$LOCKDIR" 2>/dev/null' EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        while true; do
            sleep "$TEMP_UPDATE_INTERVAL"
            current_temp_decic="$(get_battery_temp_decic)"
            [ -z "$current_temp_decic" ] && continue

            if [ -n "$last_temp_decic" ]; then
                delta="$(abs_diff_decic "$current_temp_decic" "$last_temp_decic")"
                [ "$delta" -lt "$TEMP_DELTA_THRESHOLD" ] && continue
            fi

            if update_dashboard "0" "$current_temp_decic"; then
                last_temp_decic="$current_temp_decic"
                BATTERY_TEMP_DECIC="$current_temp_decic"
                BATTERY_TEMP_LABEL="$(format_temp_label "$current_temp_decic")"
                write_module_status_env
            fi
        done
    ) &

    pid="$!"
    write_updater_record "$pid"
    log_line "[PASS] Dashboard updater: started (pid=$pid)"
}

prepare_logs() {
    if [ -f "$LOG_FILE" ]; then
        cp -f "$LOG_FILE" "$PREVIOUS_LOG_FILE" 2>/dev/null
    fi
    touch "$LOG_FILE" "$MAINTENANCE_LOG_FILE" "$STATUS_ENV" "$ADDON_API_ENV" "$SNAPSHOT_FILE" 2>/dev/null
    chmod 0644 "$LOG_FILE" "$PREVIOUS_LOG_FILE" "$MAINTENANCE_LOG_FILE" "$STATUS_ENV" "$ADDON_API_ENV" "$SNAPSHOT_FILE" 2>/dev/null
}

clear_stale_task_state() {
    local task_lock
    for task_lock in "$MAINT_LOCKDIR" "$APP_LOCKDIR" "$MODDIR/.maintenance_task.lock" "$MODDIR/.app_optimization_task.lock"; do
        rm -rf "$task_lock" "$task_lock.reclaim" 2>/dev/null
    done
    rm -f "$MAINT_PIDFILE" "$APP_OPT_PIDFILE" 2>/dev/null
}

prepare_logs
clear_stale_task_state

{
    echo "==============================================="
    echo "   SUPERCHARGER ${PROFILE_VERSION} DEEP AUDIT"
    echo "   Device: $MODEL ($DEVICE)"
    echo "   Date: $(date)"
    echo "==============================================="
} > "$LOG_FILE"

log_system_version_audit

if ! wait_for_full_boot; then
    log_line ""
    log_line "[INFO] Dashboard Audit"
    refresh_battery_temp_state
    detect_thermal_addon
    write_addon_api
    write_module_status_env
    update_dashboard "1" "$BATTERY_TEMP_DECIC"
    exit 0
fi

log_compatibility_audit

log_line ""
log_line "[INFO] Battery Status"
if [ -n "$BATTERY_TEMP_DECIC" ]; then
    log_line "[PASS] Battery Temperature: $BATTERY_TEMP_LABEL"
else
    log_line "[SKIP] Battery Temperature: sensor unavailable"
fi

log_line ""
log_line "[INFO] System and RAM Audit"
verify_prop "Dalvik Heap Start" "dalvik.vm.heapstartsize" "32m"
verify_prop "Dalvik Heap Growth" "dalvik.vm.heapgrowthlimit" "512m"
verify_prop "Dalvik Heap Size" "dalvik.vm.heapsize" "1024m"
verify_prop "Touch Latency" "persist.sys.touch.latency" "0"

apply_vm_tuning
apply_page_cluster
apply_block_tuning
apply_network_tuning
apply_selective_irq_affinity
apply_performance_experimental_tuning
verify_post_apply
log_thermal_addon_audit

log_line ""
log_line "==============================================="
log_line "   AUDIT COMPLETE - PROFILE ACTIVE"
log_line "==============================================="

STATUS_TEXT="Profile Active"
write_support_snapshot
write_module_status_env
log_support_summary
sleep 10
update_dashboard "1" "$BATTERY_TEMP_DECIC"
start_temp_dashboard_updater "$BATTERY_TEMP_DECIC"
write_module_status_env

exit 0
