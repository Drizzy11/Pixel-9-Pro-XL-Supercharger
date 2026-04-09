#!/system/bin/sh

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/debug.log"
DEVICE="$(getprop ro.product.device)"
MODEL="$(getprop ro.product.model)"

TEMP_UPDATE_INTERVAL=300
TEMP_DELTA_THRESHOLD=10

STORAGE_IRQ_PATTERNS="ufshcd|ufs"
NETWORK_IRQ_PATTERNS="wlan|wifi|wcnss|bcmdhd|dhd|rmnet|ipa"
TOUCH_IRQ_PATTERNS="synaptics|touch|goodix|fts|sec_touch|input"

log_line() {
    echo "$1" >> "$LOG_FILE"
}

safe_read() {
    [ -r "$1" ] && cat "$1" 2>/dev/null
}

safe_write_if_needed() {
    local path="$1"
    local value="$2"
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

get_dashboard_status() {
    local temp_decic="$1"
    local temp_ui

    temp_ui="$(format_temp_label "$temp_decic")"
    if grep -q "FAIL" "$LOG_FILE" 2>/dev/null; then
        echo "⚠️ Status: v2.2-STABLE | $temp_ui | Critical issue detected"
    else
        echo "🚀 Status: v2.2-STABLE | $temp_ui | All critical checks passed"
    fi
}

abs_diff_decic() {
    local a="$1"
    local b="$2"
    local diff

    diff=$((a - b))
    if [ "$diff" -lt 0 ]; then
        diff=$((diff * -1))
    fi
    echo "$diff"
}

update_dashboard() {
    local force_log="$1"
    local temp_decic="$2"
    local status
    local current_line

    status="$(get_dashboard_status "$temp_decic")"
    current_line="$(grep '^description=' "$PROP_FILE" 2>/dev/null)"

    if [ "$current_line" = "description=$status" ]; then
        return 0
    fi

    if sed -i "s/^description=.*/description=$status/" "$PROP_FILE" 2>/dev/null; then
        if [ "$force_log" = "1" ]; then
            log_line "[PASS] Dashboard: description updated"
        fi
        return 0
    fi

    log_line "[FAIL] Dashboard: unable to update module.prop"
    return 1
}

start_temp_dashboard_updater() {
    (
        local last_temp_decic
        local current_temp_decic
        local delta

        last_temp_decic="$1"

        while true; do
            sleep "$TEMP_UPDATE_INTERVAL"

            current_temp_decic="$(get_battery_temp_decic)"
            if [ -z "$current_temp_decic" ]; then
                continue
            fi

            if [ -n "$last_temp_decic" ]; then
                delta="$(abs_diff_decic "$current_temp_decic" "$last_temp_decic")"
                if [ "$delta" -lt "$TEMP_DELTA_THRESHOLD" ]; then
                    continue
                fi
            fi

            if update_dashboard "0" "$current_temp_decic"; then
                last_temp_decic="$current_temp_decic"
            fi
        done
    ) &
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

has_active_swap() {
    local line

    if [ ! -r /proc/swaps ]; then
        return 1
    fi

    while read -r line; do
        case "$line" in
            Filename*|'')
                continue
                ;;
            *)
                return 0
                ;;
        esac
    done < /proc/swaps

    return 1
}

apply_page_cluster() {
    log_line ""
    log_line "[INFO] PAGE CLUSTER AUDIT:"

    if has_active_swap; then
        safe_write_if_needed "/proc/sys/vm/page-cluster" "0" "VM Page Cluster"
    else
        log_line "[SKIP] VM Page Cluster: no active swap or zram detected"
    fi
}

set_irq_affinity_value() {
    local path="$1"
    local mask="$2"
    local label="$3"
    local current

    if [ ! -e "$path" ]; then
        log_line "[SKIP] $label: affinity node missing"
        return 2
    fi

    if [ ! -w "$path" ]; then
        log_line "[SKIP] $label: affinity node not writable"
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

    log_line "[SKIP] $label: kernel rejected affinity change; leaving default routing"
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

    for irq_num in $(grep -iE "$patterns" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
        found=$((found + 1))
        set_irq_affinity_value "/proc/irq/$irq_num/smp_affinity" "$mask" "$label IRQ $irq_num"
        rc=$?
        case "$rc" in
            0) applied=$((applied + 1)) ;;
            1) rejected=$((rejected + 1)) ;;
            *) omitted=$((omitted + 1)) ;;
        esac
    done

    if [ "$found" -eq 0 ]; then
        log_line "[SKIP] $label: no matching IRQs found"
    fi

    log_line "[PASS] $label Summary: found $found | applied $applied | rejected $rejected | omitted $omitted"
}

apply_selective_irq_affinity() {
    log_line ""
    log_line "[INFO] SELECTIVE IRQ AFFINITY AUDIT:"

    apply_irq_affinity "$STORAGE_IRQ_PATTERNS" "70" "Storage/UFS IRQ"
    apply_irq_affinity "$NETWORK_IRQ_PATTERNS" "70" "Wi-Fi/Network IRQ"
    apply_irq_affinity "$TOUCH_IRQ_PATTERNS" "f0" "Touch/Input IRQ"
}

apply_uclamp_latency_sensitive() {
    local group_name="$1"
    local path=""
    local candidate

    for candidate in \
        "/dev/cpuctl/$group_name/cpu.uclamp.latency_sensitive" \
        "/dev/stune/$group_name/cpu.uclamp.latency_sensitive" \
        "/sys/fs/cgroup/$group_name/cpu.uclamp.latency_sensitive"
    do
        if [ -e "$candidate" ]; then
            path="$candidate"
            break
        fi
    done

    if [ -z "$path" ]; then
        log_line "[SKIP] Uclamp Latency Sensitive ($group_name): path not found"
        return 1
    fi

    if ! safe_write_if_needed "$path" "1" "Uclamp Latency Sensitive ($group_name)"; then
        log_line "[SKIP] Uclamp Latency Sensitive ($group_name): kernel rejected or path unavailable"
        return 1
    fi

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
    update_dashboard "1" ""
    exit 0
fi

log_line "[OK] System ready. Deploying v2.2-STABLE profile..."

TEMP_DECIC="$(get_battery_temp_decic)"
if [ -n "$TEMP_DECIC" ]; then
    log_line "[INFO] Battery Temp: $(format_temp_label "$TEMP_DECIC")"
else
    log_line "[SKIP] Battery Temp: sensor unavailable or invalid"
fi

apply_page_cluster
apply_selective_irq_affinity

log_line ""
log_line "[INFO] UCLAMP LATENCY SENSITIVE AUDIT:"
apply_uclamp_latency_sensitive "foreground_window"
apply_uclamp_latency_sensitive "top-app"

echo "" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "   AUDIT COMPLETE - PROFILE ACTIVE" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

sleep 10
update_dashboard "1" "$TEMP_DECIC"
start_temp_dashboard_updater "$TEMP_DECIC"

exit 0
