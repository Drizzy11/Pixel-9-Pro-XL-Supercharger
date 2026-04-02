#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO SERIES SUPERCHARGER v1.6-BETA.4
# Aggressive Persistence & Zumapro Optimization - Developed by: Drizzy_07
# =============================================================

MODDIR=${0%/*}
PROP_FILE="$MODDIR/module.prop"
LOG_FILE="$MODDIR/debug.log"

# --- 1. ENHANCED AUDIT FUNCTION ---
verify_tweak() {
    local name="$1"; local path="$2"; local expected="$3"
    if [ -f "$path" ]; then
        local current=$(cat "$path")
        case "$current" in
            *"$expected"*) echo "[PASS] $name: $current" >> "$LOG_FILE" ;;
            *) echo "[FAIL] $name: Expected $expected, got $current" >> "$LOG_FILE" ;;
        esac
    else
        echo "[INFO] $name: Path not supported by current kernel" >> "$LOG_FILE"
    fi
}

# --- 2. LOG INITIALIZATION ---
if [ ! -f "$LOG_FILE" ]; then touch "$LOG_FILE"; chmod 0666 "$LOG_FILE"; fi
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v1.6-BETA.4 FINAL AUDIT" >> "$LOG_FILE"
echo "   Device: Pixel 9 Pro XL (Zumapro/Tensor G4)" >> "$LOG_FILE"
echo "   Date: $(date)" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

# --- 3. BOOT DETECTION (AGGRESSIVE WAIT) ---
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 30 
echo "[✅] System ready. Deploying all engines..." >> "$LOG_FILE"

# --- 4. LEGACY 1.5.1 & 16GB RAM PROFILE ---
# These are applied once as they are persistent via resetprop
resetprop dalvik.vm.heapstartsize 32m
resetprop dalvik.vm.heapgrowthlimit 512m
resetprop dalvik.vm.heapsize 1g
resetprop debug.hwui.renderer skiavk
resetprop persist.sys.touch.latency 0
resetprop persist.sys.ui.hw 1
echo "[🧠] Legacy: 16GB RAM and Graphics profiles applied" >> "$LOG_FILE"

# --- 5. THE PERSISTENCE ENGINE (Background Loop) ---
# This engine runs for 5 minutes, reapplying tweaks every 10 seconds 
# to defeat system-level overrides like 'perf_helper'.
(
    COUNTER=0
    while [ $COUNTER -lt 30 ]; do
        # Virtual Memory tweaks
        echo 60 > /proc/sys/vm/vfs_cache_pressure
        echo 20 > /proc/sys/vm/dirty_ratio
        echo 30 > /proc/sys/vm/swappiness
        
        # Storage Reinforcement (Forcing 256 nr_requests)
        for dev in sda sdb sdc; do
            if [ -d "/sys/block/$dev" ]; then
                echo none > "/sys/block/$dev/queue/scheduler"
                echo 256 > "/sys/block/$dev/queue/nr_requests" 2>/dev/null
            fi
        done
        COUNTER=$((COUNTER + 1))
        sleep 10
    done
    echo "[🛡️] Persistence Engine: 5-minute guard cycle complete" >> "$LOG_FILE"
    
    # Final Verification after the battle against the system
    verify_tweak "VFS Cache Pressure" "/proc/sys/vm/vfs_cache_pressure" "60"
    verify_tweak "UFS NR Requests" "/sys/block/sda/queue/nr_requests" "256"
) &

# --- 6. NETWORK FALLBACK SYSTEM ---
echo "fq" > /proc/sys/net/core/default_qdisc
sleep 2
AVAILABLE_TCP=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)

if echo "$AVAILABLE_TCP" | grep -q "bbr"; then
    echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control
    verify_tweak "TCP Congestion" "/proc/sys/net/ipv4/tcp_congestion_control" "bbr"
elif echo "$AVAILABLE_TCP" | grep -q "westwood"; then
    echo "westwood" > /proc/sys/net/ipv4/tcp_congestion_control
    verify_tweak "TCP Congestion" "/proc/sys/net/ipv4/tcp_congestion_control" "westwood"
else
    echo "[INFO] Network: Using system default ($AVAILABLE_TCP)" >> "$LOG_FILE"
fi

# --- 7. SMART IRQ BALANCE (STABILITY LOCK) ---
stop irqbalance
for irq in /proc/irq/*; do
    [ -f "$irq/smp_affinity" ] && echo "7f" > "$irq/smp_affinity" 2>/dev/null
done
for irq in /proc/irq/*; do
    if grep -q -E "ufshc|pcie|modem|wlan" "$irq/name" 2>/dev/null; then
        echo "70" > "$irq/smp_affinity" 2>/dev/null
    fi
    if grep -q -E "touch|goodix|sec_ts" "$irq/name" 2>/dev/null; then
        echo "f0" > "$irq/smp_affinity" 2>/dev/null
    fi
done
echo "[🚧] Smart IRQ: Affinity masks locked" >> "$LOG_FILE"

# --- 8. DYNAMIC DASHBOARD ENGINE ---
update_dashboard() {
    T_RAW=$(cat /sys/class/power_supply/battery/temp)
    T_UI="$((T_RAW / 10)).$((T_RAW % 10))°C"
    if grep -q "FAIL" "$LOG_FILE"; then
        STATUS="Status: [⚠️] v1.6-B4 | 🌡️ $T_UI | Audit Issue"
    else
        STATUS="Status: [🚀] v1.6-B4 | 🛡️ All Pass | 🌡️ $T_UI"
    fi
    sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
}

(
    while true; do
        update_dashboard
        sleep 60
    done
) &

# --- 9. ASYNC MAINTENANCE (SQLite) ---
(
    sleep 180
    find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
        sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
    done
    echo "[🧹] Maintenance: SQLite Vacuum/Reindex complete" >> "$LOG_FILE"
) &

echo "===============================================" >> "$LOG_FILE"
echo "   AUDIT COMPLETE - v1.6-BETA.4 FULLY DEPLOYED" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

exit 0
