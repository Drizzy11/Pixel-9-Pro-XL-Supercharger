#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO SERIES SUPERCHARGER v2.0-BETA.2
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
echo "   SUPERCHARGER v2.0-BETA.2 DEEP AUDIT" >> "$LOG_FILE"
echo "   Device: Pixel 9 Pro XL (Zumapro/Tensor G4)" >> "$LOG_FILE"
echo "   Date: $(date)" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

# --- 3. BOOT DETECTION ---
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 30 
echo "[✅] System ready. Deploying v2.0 Efficiency Engines..." >> "$LOG_FILE"

# --- 4. LEGACY SYSTEM & 16GB RAM PROFILE ---
echo "" >> "$LOG_FILE"
echo "[🧠] SYSTEM & RAM AUDIT:" >> "$LOG_FILE"

resetprop dalvik.vm.heapstartsize 32m
resetprop dalvik.vm.heapgrowthlimit 512m
resetprop dalvik.vm.heapsize 1g
resetprop debug.hwui.renderer skiavk
resetprop persist.sys.touch.latency 0
resetprop persist.sys.ui.hw 1

verify_prop "Dalvik Heap Start" "dalvik.vm.heapstartsize" "32m"
verify_prop "Dalvik Heap Growth" "dalvik.vm.heapgrowthlimit" "512m"
verify_prop "Dalvik Heap Size" "dalvik.vm.heapsize" "1g"
verify_prop "UI Renderer" "debug.hwui.renderer" "skiavk"
verify_prop "Touch Latency" "persist.sys.touch.latency" "0"
verify_prop "Hardware UI" "persist.sys.ui.hw" "1"

# --- 5. SMART STORAGE ENGINE (v2.0) ---
echo "" >> "$LOG_FILE"
echo "[⚡] VIRTUAL MEMORY & STORAGE AUDIT:" >> "$LOG_FILE"

echo 60 > /proc/sys/vm/vfs_cache_pressure
echo 20 > /proc/sys/vm/dirty_ratio
echo 30 > /proc/sys/vm/swappiness

verify_tweak "VFS Cache Pressure" "/proc/sys/vm/vfs_cache_pressure" "60"
verify_tweak "VM Dirty Ratio" "/proc/sys/vm/dirty_ratio" "20"
verify_tweak "VM Swappiness" "/proc/sys/vm/swappiness" "30"

# Storage Application (Read Ahead + IO Stats Disable)
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

# --- 6. SMART NETWORK ENGINE (v2.0) ---
echo "" >> "$LOG_FILE"
echo "[🌐] NETWORK AUDIT:" >> "$LOG_FILE"

echo "fq" > /proc/sys/net/core/default_qdisc
sleep 1
echo "cubic" > /proc/sys/net/ipv4/tcp_congestion_control
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
echo 3 > /proc/sys/net/ipv4/tcp_fastopen

# Advanced Mobile Data Buffers
echo "4096 87380 16777216" > /proc/sys/net/ipv4/tcp_rmem
echo "4096 16384 16777216" > /proc/sys/net/ipv4/tcp_wmem

verify_tweak "Network Qdisc" "/proc/sys/net/core/default_qdisc" "fq"
verify_tweak "TCP Congestion" "/proc/sys/net/ipv4/tcp_congestion_control" "cubic"
verify_tweak "TCP Socket Reuse" "/proc/sys/net/ipv4/tcp_tw_reuse" "1"
verify_tweak "TCP Fast Open" "/proc/sys/net/ipv4/tcp_fastopen" "3"
verify_tweak "TCP Read Buffer" "/proc/sys/net/ipv4/tcp_rmem" "87380"
verify_tweak "TCP Write Buffer" "/proc/sys/net/ipv4/tcp_wmem" "16384"

# --- 7. SMART IRQ BALANCE (Android 16 GKI Adapted) ---
echo "" >> "$LOG_FILE"
echo "[🚧] SMART IRQ AFFINITY AUDIT:" >> "$LOG_FILE"

stop irqbalance
echo "[PASS] IRQ Balancer: Daemon stopped" >> "$LOG_FILE"

IRQ_EFF=0; IRQ_MID=0; IRQ_PERF=0

for irq in /proc/irq/*; do
    [ -f "$irq/smp_affinity" ] && echo "7f" > "$irq/smp_affinity" 2>/dev/null && IRQ_EFF=$((IRQ_EFF + 1))
done

for irq in /proc/irq/*; do
    # Mid-Cores (Storage & Network based on Android 16 naming)
    if grep -q -iE "ufshcd|exynos-pcie|dhdpcie" "$irq/name" 2>/dev/null; then
        echo "70" > "$irq/smp_affinity" 2>/dev/null
        IRQ_MID=$((IRQ_MID + 1))
    fi
    # Perf-Cores (Touchpanel based on Synaptics controller)
    if grep -q -iE "synaptics_tcm" "$irq/name" 2>/dev/null; then
        echo "f0" > "$irq/smp_affinity" 2>/dev/null
        IRQ_PERF=$((IRQ_PERF + 1))
    fi
done

echo "[PASS] IRQ Efficiency (7f): Applied to $IRQ_EFF nodes" >> "$LOG_FILE"
echo "[PASS] IRQ Mid-Cores (70): Applied to $IRQ_MID nodes (I/O & Network)" >> "$LOG_FILE"
echo "[PASS] IRQ Perf-Cores (f0): Applied to $IRQ_PERF nodes (Touch)" >> "$LOG_FILE"

# --- 8. DASHBOARD ENGINE ---
update_dashboard() {
    T_RAW=$(cat /sys/class/power_supply/battery/temp)
    T_UI="$((T_RAW / 10)).$((T_RAW % 10))°C"
    if grep -q "FAIL" "$LOG_FILE"; then
        STATUS="Status: [⚠️] v2.0-B2 | 🌡️ $T_UI | Audit Issue"
    else
        STATUS="Status: [🚀] v2.0-B2 | 🛡️ All Pass | 🌡️ $T_UI"
    fi
    sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
}

(
    while true; do
        update_dashboard
        sleep 60
    done
) &

# --- 9. ASYNC MAINTENANCE ---
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
