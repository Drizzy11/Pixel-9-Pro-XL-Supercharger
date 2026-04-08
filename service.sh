#!/system/bin/sh

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/debug.log"
DEVICE="$(getprop ro.product.device)"
MODEL="$(getprop ro.product.model)"

ENABLE_IOSTATS_DISABLE=1
THERMAL_GUARD_DECIC=390

STORAGE_IRQ_PATTERNS="ufshcd|ufs|scpufreq-uclamp"
NETWORK_IRQ_PATTERNS="wlan|wifi|wcnss|bcmdhd|dhd|rmnet|ipa"
TOUCH_IRQ_PATTERNS="synaptics|touch|goodix|fts|sec_touch|input"

log_line() {
    echo "$1" >> "$LOG_FILE"
}

safe_read() {
    [ -r "$1" ] && cat "$1" 2>/dev/null
}

safe_write() {
    local value="$1"
    local path="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: path not found ($path)"
        return 1
    fi

    if [ ! -w "$path" ]; then
        log_line "[SKIP] $label: path not writable"
        return 1
    fi

    current="$(safe_read "$path")"
    if [ "$current" = "$value" ]; then
        log_line "[PASS] $label: already set to $value"
        return 0
    fi

    if echo "$value" > "$path" 2>/dev/null; then
        current="$(safe_read "$path")"
        if [ "$current" = "$value" ]; then
            log_line "[PASS] $label: applied $value"
            return 0
        fi
        log_line "[FAIL] $label: write did not persist (current=${current:-<empty>})"
        return 1
    fi

    log_line "[FAIL] $label: write rejected"
    return 1
}

verify_prop() {
    local name="$1"
    local prop="$2"
    local expected="$3"
    local current

    current="$(getprop "$prop")"
    if [ "$current" = "$expected" ]; then
        log_line "[PASS] $name: $current"
    else
        log_line "[FAIL] $name: Expected $expected, got ${current:-<empty>}"
    fi
}

get_battery_temp_decic() {
    local raw

    if [ ! -r /sys/class/power_supply/battery/temp ]; then
        return 1
    fi

    raw="$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
    case "$raw" in
        ''|*[!0-9-]*)
            return 1
            ;;
        *)
            echo "$raw"
            return 0
            ;;
    esac
}

format_temp_label() {
    local decic="$1"
    local whole
    local frac

    if [ -z "$decic" ]; then
        echo "🌡️ temp unavailable"
        return 0
    fi

    whole=$((decic / 10))
    frac=$((decic % 10))
    if [ "$frac" -lt 0 ]; then
        frac=$((frac * -1))
    fi
    echo "🌡️ ${whole}.${frac}C"
}

is_swap_active() {
    local line
    local used

    if [ ! -r /proc/swaps ]; then
        return 1
    fi

    while read -r line; do
        case "$line" in
            Filename*|'')
                continue
                ;;
        esac

        used="$(echo "$line" | awk '{print $4}')"
        if [ -n "$used" ]; then
            return 0
        fi
    done < /proc/swaps

    return 1
}

set_scheduler_if_available() {
    local scheduler_path="$1"
    local desired="$2"
    local label="$3"
    local current
    local selected

    if [ ! -e "$scheduler_path" ]; then
        log_line "[SKIP] $label: scheduler node missing"
        return 1
    fi

    current="$(safe_read "$scheduler_path")"
    case "$current" in
        *"$desired"*)
            selected="$(echo "$current" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')"
            if [ "$selected" = "$desired" ]; then
                log_line "[PASS] $label: already set to $desired"
                return 0
            fi
            safe_write "$desired" "$scheduler_path" "$label"
            return $?
            ;;
        *)
            log_line "[SKIP] $label: '$desired' scheduler not available"
            return 1
            ;;
    esac
}

apply_vm_tuning() {
    log_line ""
    log_line "[INFO] VIRTUAL MEMORY AUDIT:"

    safe_write "60" "/proc/sys/vm/vfs_cache_pressure" "VFS Cache Pressure"
    safe_write "5" "/proc/sys/vm/dirty_background_ratio" "VM Dirty Background Ratio"
    safe_write "12" "/proc/sys/vm/dirty_ratio" "VM Dirty Ratio"

    if is_swap_active; then
        safe_write "30" "/proc/sys/vm/swappiness" "VM Swappiness"
    else
        log_line "[SKIP] VM Swappiness: no active swap or zram detected"
    fi
}

apply_block_tuning() {
    local dev
    local base
    local tuned=0

    log_line ""
    log_line "[INFO] BLOCK I/O AUDIT:"

    for dev in /sys/block/*; do
        [ -d "$dev" ] || continue
        base="$(basename "$dev")"

        if [ ! -d "$dev/queue" ]; then
            log_line "[SKIP] Block Device ($base): queue interface missing"
            continue
        fi

        set_scheduler_if_available "$dev/queue/scheduler" "none" "Block Scheduler ($base)"
        safe_write "256" "$dev/queue/read_ahead_kb" "Block Read Ahead ($base)"

        if [ "$ENABLE_IOSTATS_DISABLE" = "1" ]; then
            if [ -e "$dev/queue/iostats" ]; then
                safe_write "0" "$dev/queue/iostats" "Block IO Stats ($base)"
            else
                log_line "[SKIP] Block IO Stats ($base): node missing"
            fi
        else
            log_line "[SKIP] Block IO Stats ($base): feature disabled"
        fi

        tuned=$((tuned + 1))
    done

    log_line "[PASS] Block Device Scan: processed $tuned block devices"
}

network_value_available() {
    local path="$1"
    local token="$2"
    local current

    current="$(safe_read "$path")"
    case "$current" in
        *"$token"*)
            return 0
            ;;
    esac
    return 1
}

apply_network_tuning() {
    local cc_available

    log_line ""
    log_line "[INFO] NETWORK AUDIT:"

    safe_write "fq" "/proc/sys/net/core/default_qdisc" "Network Qdisc"

    cc_available="/proc/sys/net/ipv4/tcp_available_congestion_control"
    if [ -e "$cc_available" ]; then
        if network_value_available "$cc_available" "cubic"; then
            safe_write "cubic" "/proc/sys/net/ipv4/tcp_congestion_control" "TCP Congestion"
        else
            log_line "[SKIP] TCP Congestion: cubic not available"
        fi
    elif [ -e "/proc/sys/net/ipv4/tcp_congestion_control" ]; then
        current_cc="$(safe_read /proc/sys/net/ipv4/tcp_congestion_control)"
        if [ "$current_cc" = "cubic" ]; then
            log_line "[PASS] TCP Congestion: already set to cubic"
        else
            log_line "[SKIP] TCP Congestion: availability unknown on this kernel"
        fi
    else
        log_line "[SKIP] TCP Congestion: node missing"
    fi

    safe_write "1" "/proc/sys/net/ipv4/tcp_fastopen" "TCP Fast Open"
}

set_irq_affinity_if_present() {
    local patterns="$1"
    local mask="$2"
    local label="$3"
    local count=0
    local irq_num

    for irq_num in $(grep -iE "$patterns" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
        if [ -f "/proc/irq/$irq_num/smp_affinity" ]; then
            safe_write "$mask" "/proc/irq/$irq_num/smp_affinity" "$label IRQ $irq_num"
            count=$((count + 1))
        else
            log_line "[SKIP] $label IRQ $irq_num: affinity node missing"
        fi
    done

    if [ "$count" -eq 0 ]; then
        log_line "[SKIP] $label: no matching IRQs found"
    else
        log_line "[PASS] $label: processed $count IRQs"
    fi
}

apply_irq_tuning() {
    log_line ""
    log_line "[INFO] SELECTIVE IRQ AFFINITY AUDIT:"

    set_irq_affinity_if_present "$STORAGE_IRQ_PATTERNS" "70" "Storage IRQ"
    set_irq_affinity_if_present "$NETWORK_IRQ_PATTERNS" "70" "Network IRQ"
    set_irq_affinity_if_present "$TOUCH_IRQ_PATTERNS" "f0" "Touch IRQ"
}

update_dashboard() {
    local temp_decic
    local temp_ui
    local status
    local current_line

    temp_decic="$(get_battery_temp_decic)"
    temp_ui="$(format_temp_label "$temp_decic")"

    if grep -q "FAIL" "$LOG_FILE" 2>/dev/null; then
        status="⚠️ Status: v2.2-STABLE | $temp_ui | Audit issue detected"
    else
        status="🚀 Status: v2.2-STABLE | $temp_ui | All checks passed"
    fi

    current_line="$(grep '^description=' "$PROP_FILE" 2>/dev/null)"
    if [ "$current_line" = "description=$status" ]; then
        log_line "[PASS] Dashboard: description already up to date"
        return 0
    fi

    if sed -i "s/^description=.*/description=$status/" "$PROP_FILE" 2>/dev/null; then
        log_line "[PASS] Dashboard: description updated"
    else
        log_line "[FAIL] Dashboard: unable to update module.prop"
    fi
}

wait_for_full_boot() {
    local boot_wait=0

    until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$boot_wait" -ge 180 ]; do
        sleep 2
        boot_wait=$((boot_wait + 2))
    done

    if [ "$(getprop sys.boot_completed)" != "1" ]; then
        log_line "[FAIL] Boot detection timed out after ${boot_wait}s"
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
        log_line "[SKIP] Boot animation state unavailable; continuing"
    fi

    sleep 10
    return 0
}

[ -f "$LOG_FILE" ] || touch "$LOG_FILE"
chmod 0644 "$LOG_FILE" 2>/dev/null

echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v2.2-STABLE DEEP AUDIT" >> "$LOG_FILE"
echo "   Device: $MODEL ($DEVICE)" >> "$LOG_FILE"
echo "   Date: $(date)" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

log_line "[INFO] Waiting for full Android boot..."
if ! wait_for_full_boot; then
    update_dashboard
    exit 0
fi

log_line "[OK] System ready. Deploying v2.2-STABLE profile..."

log_line ""
log_line "[INFO] SYSTEM AND RAM AUDIT (read-only):"
verify_prop "Dalvik Heap Start" "dalvik.vm.heapstartsize" "32m"
verify_prop "Dalvik Heap Growth" "dalvik.vm.heapgrowthlimit" "512m"
verify_prop "Dalvik Heap Size" "dalvik.vm.heapsize" "1024m"
verify_prop "Touch Latency" "persist.sys.touch.latency" "0"

TEMP_DECIC="$(get_battery_temp_decic)"
if [ -n "$TEMP_DECIC" ]; then
    log_line "[INFO] Battery Temp: $(format_temp_label "$TEMP_DECIC")"
else
    log_line "[SKIP] Battery Temp: sensor unavailable or invalid"
fi

THERMAL_GUARD_ACTIVE=0
if [ -n "$TEMP_DECIC" ] && [ "$TEMP_DECIC" -ge "$THERMAL_GUARD_DECIC" ]; then
    THERMAL_GUARD_ACTIVE=1
    log_line "[SKIP] Thermal Guard: active at $(format_temp_label "$TEMP_DECIC"), skipping aggressive I/O and IRQ tuning"
fi

apply_vm_tuning
apply_network_tuning

if [ "$THERMAL_GUARD_ACTIVE" -eq 0 ]; then
    apply_block_tuning
    apply_irq_tuning
else
    log_line ""
    log_line "[SKIP] BLOCK I/O AUDIT: skipped by thermal guard"
    log_line ""
    log_line "[SKIP] SELECTIVE IRQ AFFINITY AUDIT: skipped by thermal guard"
fi

echo "" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "   AUDIT COMPLETE - PROFILE ACTIVE" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

(
    sleep 10
    log_line "[INFO] Updating Magisk dashboard after post-boot grace period"
    update_dashboard
) &

exit 0
