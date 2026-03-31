#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO XL SUPERCHARGER v1.5 [STABLE]
# Developed by: Drizzy_07
# Target Device: komodo (Google Pixel 9 Pro XL)
# Architecture: Tensor G4 | 16GB LPDDR5X | UFS 4.0
# Optimized for: Android 16 (Evolution X)
# =============================================================

# --- 0. DYNAMIC BOOT DETECTION ---
# Wait until the system reports boot is 100% complete
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

# Extra 10s grace period for SystemUI and services to settle
sleep 10

# --- 1. INITIALIZATION & LOGGING ENGINE ---
MOD_DIR="/data/adb/modules/p9pxl_supercharger"
LOG_FILE="$MOD_DIR/debug.log"
PROP_FILE="$MOD_DIR/module.prop"

# Initialize fresh log for every boot
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v1.5.1 HARDWARE DIAGNOSTIC" >> "$LOG_FILE"
echo "   Developer: Drizzy_07 | Device: komodo" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "BOOT_TIME: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

# Hardware Metrics (Pixel 9 Pro XL Specs)
TEMP_RAW=$(cat /sys/class/power_supply/battery/temp)
echo "🌡️ SOC_TEMP: $((TEMP_RAW / 10)).$((TEMP_RAW % 10))°C" >> "$LOG_FILE"
echo "💾 INITIAL_RAM_STATUS:" >> "$LOG_FILE"
free -m >> "$LOG_FILE"

run_tweak() {
    $2 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        echo "[✅] SUCCESS: $1" >> "$LOG_FILE"
    else
        echo "[❌] FAILED: $1 | Error Code: $?" >> "$LOG_FILE"
    fi
}

echo "--- DEPLOYING OPTIMIZATIONS ---" >> "$LOG_FILE"

# --- 2. KERNEL & NETWORK EFFICIENCY ---
# Race to Sleep: Reduce modem active time on 5G/Wi-Fi 7
run_tweak "TCP Fast Open (3)" "echo 3 > /proc/sys/net/ipv4/tcp_fastopen"
run_tweak "TCP Low Latency (1)" "echo 1 > /proc/sys/net/ipv4/tcp_low_latency"

# VFS Management: Leverage 16GB RAM to reduce physical UFS 4.0 I/O
run_tweak "VFS Cache Pressure (50)" "echo 50 > /proc/sys/vm/vfs_cache_pressure"
run_tweak "Dirty Ratio (10)" "echo 10 > /proc/sys/vm/dirty_ratio"

# --- 3. MEMORY & DALVIK (16GB RAM TUNING) ---
run_tweak "Dalvik HeapStartSize (32M)" "resetprop dalvik.vm.heapstartsize 32m"
run_tweak "Dalvik GrowthLimit (512M)" "resetprop dalvik.vm.heapgrowthlimit 512m"
run_tweak "Dalvik HeapSize (1G)" "resetprop dalvik.vm.heapsize 1g"
run_tweak "Swappiness (60)" "echo 60 > /proc/sys/vm/swappiness"

# --- 4. THERMAL & POWER MANAGEMENT ---
run_tweak "CPU Powersave Bias" "echo 1 > /sys/devices/system/cpu/cpufreq/policy0/powersave_bias"
run_tweak "CPU Powersave Bias (Cluster 4)" "echo 1 > /sys/devices/system/cpu/cpufreq/policy4/powersave_bias"
run_tweak "CPU Powersave Bias (Cluster 7)" "echo 1 > /sys/devices/system/cpu/cpufreq/policy7/powersave_bias"

# Limit background compilation threads to prevent heat spikes
run_tweak "ART Dex2oat Threads (4)" "resetprop dalvik.vm.dex2oat-threads 4"
run_tweak "Boot Dex2oat Threads (4)" "resetprop dalvik.vm.boot-dex2oat-threads 4"

# --- 5. UI FLUIDITY & GRAPHICS ---
run_tweak "Disable Dithering" "resetprop persist.sys.use_dithering 0"
run_tweak "Force HW UI" "resetprop persist.sys.ui.hw 1"
run_tweak "Renderer SkiaVK" "resetprop debug.hwui.renderer skiavk"
# Stability Fix: Using resetprop for touch latency
run_tweak "Touch Latency Tuning" "resetprop persist.sys.touch.latency 0"

# --- 6. STORAGE I/O (STABILITY TUNING) ---
# Reduced 'nr_requests' from 256 to 128 to prevent I/O hangs
for queue in /sys/block/sd*/queue; do
    run_tweak "I/O Scheduler (none) for $queue" "echo none > $queue/scheduler"
    run_tweak "Read-Ahead (512KB) for $queue" "echo 512 > $queue/read_ahead_kb"
    echo "128" > "$queue/nr_requests"
    echo "0" > "$queue/add_random"
    echo "0" > "$queue/iostats"
done

# --- 7. SYSTEM CLEANUP & NETWORK ---
settings put global wifi_scan_interval_ms 300000
settings put global mobile_data_always_on 0
run_tweak "Disable Statsd" "resetprop ro.statsd.enable false"
run_tweak "Disable Live Logcat" "resetprop logcat.live disable"

# --- 8. AUTOMATED MAINTENANCE (STABILIZED) ---
# Runs 3 minutes after boot to avoid I/O collisions with MediaProvider
(
    sleep 180 
    if command -v sqlite3 >/dev/null 2>&1; then
        echo "[🛠️] Maintenance: Starting safe optimization..." >> "$LOG_FILE"
        # Excluded 'com.android.providers.media' to prevent screenshot/delete errors
        find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
            sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
        done
        echo "[🛠️] Maintenance: SQLite optimization completed ✅" >> "$LOG_FILE"
    else
        echo "[⚠️] Maintenance: sqlite3 not found, skipping" >> "$LOG_FILE"
    fi

    cmd package bg-dexopt-job
    echo "[🛠️] Maintenance: ART Job Completed" >> "$LOG_FILE"
) &

# --- 9. DYNAMIC MAGISK DASHBOARD ---
STATUS="Status: [RUNNING] - System Optimized ✅ Efficiency Active"
sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"

echo "===============================================" >> "$LOG_FILE"
echo "   DEPLOYMENT COMPLETE - ENJOY THE SPEED" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

exit 0
