#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO XL SUPERCHARGER v1.5 [STABLE]
# Developed by: Drizzy_07
# Target Device: komodo (Google Pixel 9 Pro XL)
# Architecture: Tensor G4 | 16GB LPDDR5X | UFS 4.0
# =============================================================

# --- 0. INITIALIZATION & LOGGING ENGINE ---
# Wait for SystemUI and ROM services to stabilize
sleep 90

MOD_DIR="/data/adb/modules/p9pxl_supercharger"
LOG_FILE="$MOD_DIR/debug.log"
PROP_FILE="$MOD_DIR/module.prop"

# Initialize fresh log for every boot (Privacy-friendly)
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v1.5 HARDWARE DIAGNOSTIC" >> "$LOG_FILE"
echo "   Developer: Drizzy_07 | Device: komodo" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "BOOT_TIME: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

# Hardware Metric: SoC Temperature
TEMP_RAW=$(cat /sys/class/power_supply/battery/temp)
echo "🌡️ SOC_TEMP: $((TEMP_RAW / 10)).$((TEMP_RAW % 10))°C" >> "$LOG_FILE"

# Hardware Metric: RAM Snapshot (16GB LPDDR5X)
echo "💾 INITIAL_RAM_STATUS:" >> "$LOG_FILE"
free -m >> "$LOG_FILE"

# Task Execution Wrapper for Debugging
run_tweak() {
    $2 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        echo "[✅] SUCCESS: $1" >> "$LOG_FILE"
    else
        echo "[❌] FAILED: $1 | Error Code: $?" >> "$LOG_FILE"
    fi
}

echo "--- DEPLOYING OPTIMIZATIONS ---" >> "$LOG_FILE"

# --- 1. MEMORY & DALVIK (16GB RAM TUNING) ---
# Optimizing for high-capacity multitasking
run_tweak "Dalvik HeapStartSize (32M)" "resetprop dalvik.vm.heapstartsize 32m"
run_tweak "Dalvik GrowthLimit (512M)" "resetprop dalvik.vm.heapgrowthlimit 512m"
run_tweak "Dalvik HeapSize (1G)" "resetprop dalvik.vm.heapsize 1g"
run_tweak "Swappiness (60)" "echo 60 > /proc/sys/vm/swappiness"

# --- 2. THERMAL & POWER MANAGEMENT ---
# Balancing performance with hardware longevity
run_tweak "Power Bias Policy 0" "echo 1 > /sys/devices/system/cpu/cpufreq/policy0/powersave_bias"
run_tweak "Power Bias Policy 4" "echo 1 > /sys/devices/system/cpu/cpufreq/policy4/powersave_bias"
run_tweak "Power Bias Policy 7" "echo 1 > /sys/devices/system/cpu/cpufreq/policy7/powersave_bias"

# --- 3. UI FLUIDITY & GRAPHICS ---
# Enhancing 120Hz LTPO response and SkiaVK rendering
run_tweak "Disable Dithering" "resetprop persist.sys.use_dithering 0"
run_tweak "Force HW UI" "resetprop persist.sys.ui.hw 1"
run_tweak "Renderer SkiaVK" "resetprop debug.hwui.renderer skiavk"
run_tweak "Touch Responsiveness" "settings put system touch_responsiveness 1"

# --- 4. STORAGE I/O (UFS 4.0 OPTIMIZATION) ---
# Leveraging high-speed storage for zero-lag loading
for queue in /sys/block/sd*/queue; do
    run_tweak "I/O Scheduler (none) for $queue" "echo none > $queue/scheduler"
    run_tweak "Read-Ahead (512KB) for $queue" "echo 512 > $queue/read_ahead_kb"
    echo "0" > "$queue/add_random"
    echo "0" > "$queue/iostats"
done

# --- 5. SYSTEM CLEANUP & NETWORK ---
# Reducing idle drain and background telemetry
settings put global wifi_scan_interval_ms 300000
settings put global mobile_data_always_on 0
run_tweak "Disable Statsd" "resetprop ro.statsd.enable false"
run_tweak "Disable Live Logcat" "resetprop logcat.live disable"

# --- 6. AUTOMATED MAINTENANCE ---
# Performing database VACUUM and triggering ART compiler
# Note: Background DexOpt can take time; executed as sub-process
(
    for db in $(find /data/data -name "*.db"); do
        sqlite3 "$db" "VACUUM; REINDEX;" 2>/dev/null
    done
    cmd package bg-dexopt-job
    echo "[🛠️] MAINTENANCE: SQLite & ART Job Completed" >> "$LOG_FILE"
) &

# --- 7. DYNAMIC MAGISK DASHBOARD ---
# Real-time status update for the Magisk UI
VAL_HEAP=$(getprop dalvik.vm.heapgrowthlimit)
VAL_SWAP=$(cat /proc/sys/vm/swappiness)

if [ "$VAL_HEAP" = "512m" ] && [ "$VAL_SWAP" = "60" ]; then
    STATUS="Status: [RUNNING] - System Optimized ✅ Efficiency Active"
else
    STATUS="Status: [WARNING] - Tweaks bypassed ❌ Check debug.log"
fi

# Update description in module.prop
sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"

echo "===============================================" >> "$LOG_FILE"
echo "   DEPLOYMENT COMPLETE - ENJOY THE SPEED" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

exit 0
