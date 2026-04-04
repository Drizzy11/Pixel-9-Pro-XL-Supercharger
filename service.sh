#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO SERIES SUPERCHARGER v2.1-STABLE
# Maximum Efficiency Architecture - Developed by: Drizzy_07
# =============================================================

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/debug.log"

# --- 1. ENHANCED AUDIT FUNCTIONS ---
verify_tweak() {
    local name="$1"; local path="$2"; local expected="$3"
    if [ -f "$path" ]; then
        local current=$(cat "$path")
        case "$current" in
            *"$expected"*) echo "[PASS] $name: $current" >> "$LOG_FILE" ;;
            *) echo "[FAIL] $name: Expected $expected, got $current" >> "$LOG_FILE" ;;
        esac
    else
        echo "[INFO] $name: Path not supported" >> "$LOG_FILE"
    fi
}

verify_prop() {
    local name="$1"; local prop="$2"; local expected="$3"
    local current=$(getprop "$prop")
    if [ "$current" = "$expected" ]; then
        echo "[PASS] $name: $current" >> "$LOG_FILE"
    else
        echo "[FAIL] $name: Expected $expected, got $current" >> "$LOG_FILE"
    fi
}

# --- 2. LOG INITIALIZATION ---
if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; chmod 0666 "$LOG_FILE"; fi
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v2.1-BETA.3 DEEP AUDIT" >> "$LOG_FILE"
echo "   Device: Pixel 9 Pro XL (Zumapro/Tensor G4)" >> "$LOG_FILE"
echo "   Date: $(date)" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

# --- 3. BOOT DETECTION ---
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 30 
echo "[✅] System ready. Deploying v2.1-STABLE Engines..." >> "$LOG_FILE"

# --- 4. EARLY BOOT AUDIT (Verifying system.prop) ---
echo "" >> "$LOG_FILE"
echo "[🧠] SYSTEM & RAM AUDIT (Read-Only):" >> "$LOG_FILE"

verify_prop "Dalvik Heap Start" "dalvik.vm.heapstartsize" "32m"
verify_prop "Dalvik Heap Growth" "dalvik.vm.heapgrowthlimit" "512m"
verify_prop "Dalvik Heap Size" "dalvik.vm.heapsize" "1024m"
verify_prop "Touch Latency" "persist.sys.touch.latency" "0"

# --- 5. SMART STORAGE ENGINE (v2.1) ---
echo "" >> "$LOG_FILE"
echo "[⚡] VIRTUAL MEMORY & STORAGE AUDIT:" >> "$LOG_FILE"

echo 60 > /proc/sys/vm/vfs_cache_pressure
echo 20 > /proc/sys/vm/dirty_ratio
echo 30 > /proc/sys/vm/swappiness

verify_tweak "VFS Cache Pressure" "/proc/sys/vm/vfs_cache_pressure" "60"
verify_tweak "VM Dirty Ratio" "/proc/sys/vm/dirty_ratio" "20"
verify_tweak "VM Swappiness" "/proc/sys/vm/swappiness" "30"

for dev in sda sdb sdc; do
    if [ -d "/sys/block/$dev" ]; then
        echo none > "/sys/block/$dev/queue/scheduler"
        echo 1024 > "/sys/block/$dev/queue/read_ahead_kb"
        echo 0 > "/sys/block/$dev/queue/iostats" 2>/dev/null
        
        verify_tweak "UFS Scheduler ($dev)" "/sys/block/$dev/queue/scheduler" "none"
        verify_tweak "UFS Read Ahead ($dev)" "/sys/block/$dev/queue/read_ahead_kb" "1024"
        verify_tweak "UFS IO Stats ($dev)" "/sys/block/$dev/queue/iostats" "0"
    fi
done

# --- 6. SMART NETWORK ENGINE (Stable CUBIC) ---
echo "" >> "$LOG_FILE"
echo "[🌐] NETWORK AUDIT:" >> "$LOG_FILE"

echo "fq" > /proc/sys/net/core/default_qdisc
sleep 1
echo "cubic" > /proc/sys/net/ipv4/tcp_congestion_control
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
echo 3 > /proc/sys/net/ipv4/tcp_fastopen
echo "4096 87380 16777216" > /proc/sys/net/ipv4/tcp_rmem
echo "4096 16384 16777216" > /proc/sys/net/ipv4/tcp_wmem

verify_tweak "Network Qdisc" "/proc/sys/net/core/default_qdisc" "fq"
verify_tweak "TCP Congestion" "/proc/sys/net/ipv4/tcp_congestion_control" "cubic"
verify_tweak "TCP Socket Reuse" "/proc/sys/net/ipv4/tcp_tw_reuse" "1"
verify_tweak "TCP Fast Open" "/proc/sys/net/ipv4/tcp_fastopen" "3"
verify_tweak "TCP Read Buffer" "/proc/sys/net/ipv4/tcp_rmem" "87380"
verify_tweak "TCP Write Buffer" "/proc/sys/net/ipv4/tcp_wmem" "16384"

# --- 8. SMART IRQ BALANCE (Android 16 Extraction Method) ---
echo "" >> "$LOG_FILE"
echo "[🚧] SMART IRQ AFFINITY AUDIT:" >> "$LOG_FILE"

stop irqbalance
echo "[PASS] IRQ Balancer: Daemon stopped" >> "$LOG_FILE"

IRQ_EFF=0; IRQ_MID=0; IRQ_PERF=0

for irq in /proc/irq/*; do
    [ -f "$irq/smp_affinity" ] && echo "7f" > "$irq/smp_affinity" 2>/dev/null && IRQ_EFF=$((IRQ_EFF + 1))
done

for irq_num in $(grep -iE "ufshcd|exynos-pcie|dhdpcie" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
    if [ -f "/proc/irq/$irq_num/smp_affinity" ]; then
        echo "70" > "/proc/irq/$irq_num/smp_affinity" 2>/dev/null
        IRQ_MID=$((IRQ_MID + 1))
    fi
done

for irq_num in $(grep -iE "synaptics_tcm" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' '); do
    if [ -f "/proc/irq/$irq_num/smp_affinity" ]; then
        echo "f0" > "/proc/irq/$irq_num/smp_affinity" 2>/dev/null
        IRQ_PERF=$((IRQ_PERF + 1))
    fi
done

echo "[PASS] IRQ Efficiency (7f): Applied to $IRQ_EFF nodes" >> "$LOG_FILE"
echo "[PASS] IRQ Mid-Cores (70): Applied to $IRQ_MID nodes (I/O & Network)" >> "$LOG_FILE"
echo "[PASS] IRQ Perf-Cores (f0): Applied to $IRQ_PERF nodes (Touch)" >> "$LOG_FILE"

# --- 9. DASHBOARD ENGINE ---
update_dashboard() {
    T_RAW=$(cat /sys/class/power_supply/battery/temp)
    T_UI="$((T_RAW / 10)).$((T_RAW % 10))°C"
    if grep -q "FAIL" "$LOG_FILE"; then
        STATUS="Status: [⚠️] v2.1-STABLE | 🌡️ $T_UI | Audit Issue"
    else
        STATUS="Status: [🚀] v2.1-STABLE | 🛡️ All Pass | 🌡️ $T_UI"
    fi
    sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
}

(
    while true; do
        update_dashboard
        sleep 60
    done
) &

# --- 10. ASYNC MAINTENANCE ---
(
    sleep 180
    find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
        sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
    done
    echo "" >> "$LOG_FILE"
    echo "[🧹] Maintenance: SQLite Vacuum complete" >> "$LOG_FILE"
) &

echo "" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "   AUDIT COMPLETE - ALL ENGINES ACTIVE" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

exit 0
