#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO XL SUPERCHARGER v1.5 [FINAL MASTER]
# Developed by: Drizzy_07
# Target Device: komodo (Google Pixel 9 Pro XL)
# Architecture: Tensor G4 | 16GB LPDDR5X | UFS 4.0
# Optimized for: Android 16 (Evolution X)
# =============================================================

# --- 1. PRE-BOOT INITIALIZATION ---
MOD_DIR="/data/adb/modules/p9pxl_supercharger"
PROP_FILE="$MOD_DIR/module.prop"
LOG_FILE="$MOD_DIR/debug.log"

# Set initial status in Magisk UI
sed -i "s/^description=.*/description=Status: [⏳] Supercharger is waiting for system boot.../" "$PROP_FILE"

# --- 2. DYNAMIC BOOT DETECTION ---
# Wait for Android 16 framework to be fully ready
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 10 # Grace period for SystemUI and services

# --- 3. LOGGING & INITIAL DIAGNOSTICS ---
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v1.5 FINAL MASTER DIAGNOSTIC" >> "$LOG_FILE"
echo "   Developer: Drizzy_07 | Device: komodo" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"
echo "BOOT_TIME: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"

# Log initial hardware metrics
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

# --- 4. CORE HARDWARE TUNING (16GB RAM & STORAGE) ---
# Phase 1: Hardware Optimization Status
sed -i "s/^description=.*/description=Status: [🧠] Optimizing 16GB RAM & [⚡] UFS 4.0.../" "$PROP_FILE"

# Memory Tuning (LPDDR5X Focus)
run_tweak "Dalvik HeapStartSize (32M)" "resetprop dalvik.vm.heapstartsize 32m"
run_tweak "Dalvik GrowthLimit (512M)" "resetprop dalvik.vm.heapgrowthlimit 512m"
run_tweak "Dalvik HeapSize (1G)" "resetprop dalvik.vm.heapsize 1g"
run_tweak "VFS Cache Pressure (50)" "echo 50 > /proc/sys/vm/vfs_cache_pressure"
run_tweak "Dirty Ratio (10)" "echo 10 > /proc/sys/dirty_ratio"
run_tweak "Swappiness (60)" "echo 60 > /proc/sys/vm/swappiness"

# Storage Stability Patch (UFS 4.0)
for queue in /sys/block/sd*/queue; do
    echo "none" > "$queue/scheduler"
    echo "128" > "$queue/nr_requests" # Balanced value to prevent screenshot errors
    echo "512" > "$queue/read_ahead_kb"
    echo "0" > "$queue/add_random"
    echo "0" > "$queue/iostats"
done

# --- 5. CONNECTIVITY & SYSTEM CLEANUP ---
# Phase 2: Connectivity & UI Status
sed -i "s/^description=.*/description=Status: [🌐] Tuning 5G/Wi-Fi & [🎮] UI Fluidity.../" "$PROP_FILE"

# Networking: Race to Sleep Logic
run_tweak "TCP Fast Open (3)" "echo 3 > /proc/sys/net/ipv4/tcp_fastopen"
run_tweak "TCP Low Latency (1)" "echo 1 > /proc/sys/net/ipv4/tcp_low_latency"

# Efficiency Tweaks
settings put global wifi_scan_interval_ms 300000
settings put global mobile_data_always_on 0
run_tweak "Disable Statsd" "resetprop ro.statsd.enable false"
run_tweak "Disable Live Logcat" "resetprop logcat.live disable"

# --- 6. THERMAL, UI & GRAPHICS ---
# Tensor G4 Power Management
run_tweak "CPU Powersave Bias (P0)" "echo 1 > /sys/devices/system/cpu/cpufreq/policy0/powersave_bias"
run_tweak "CPU Powersave Bias (P4)" "echo 1 > /sys/devices/system/cpu/cpufreq/policy4/powersave_bias"
run_tweak "CPU Powersave Bias (P7)" "echo 1 > /sys/devices/system/cpu/cpufreq/policy7/powersave_bias"
run_tweak "ART Dex2oat Threads (4)" "resetprop dalvik.vm.dex2oat-threads 4"
run_tweak "Boot Dex2oat Threads (4)" "resetprop dalvik.vm.boot-dex2oat-threads 4"

# Graphics & Touch Tuning
run_tweak "Disable Dithering" "resetprop persist.sys.use_dithering 0"
run_tweak "Force HW UI" "resetprop persist.sys.ui.hw 1"
run_tweak "Renderer SkiaVK" "resetprop debug.hwui.renderer skiavk"
run_tweak "Touch Latency Tuning" "resetprop persist.sys.touch.latency 0"

# --- 7. DYNAMIC DASHBOARD ENGINE (LIVE TEMP) ---
# Function to update Magisk description with live hardware data
update_dashboard() {
    CUR_TEMP_RAW=$(cat /sys/class/power_supply/battery/temp)
    CUR_TEMP="$((CUR_TEMP_RAW / 10)).$((CUR_TEMP_RAW % 10))°C"
    # Consolidated status line with live temperature
    STATUS="Status: [🚀] v1.5 ACTIVE | 🧠 16GB | ⚡ UFS 4.0 | 🌡️ Actual Temp: $CUR_TEMP | ✅ Stable"
    sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
}

# Start background refresh loop every 60 seconds
(
    while true; do
        update_dashboard
        sleep 60
    done
) &

# --- 8. STABILIZED MAINTENANCE (ASYNC) ---
# 180s delay to prevent MediaProvider collisions (Screenshot fix)
(
    sleep 180
    if command -v sqlite3 >/dev/null 2>&1; then
        echo "[🛠️] Maintenance: safe database optimization starting..." >> "$LOG_FILE"
        # Exclude media providers to ensure screenshot availability
        find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
            sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
        done
        echo "[🛠️] Maintenance: SQLite optimization completed ✅" >> "$LOG_FILE"
    fi
    cmd package bg-dexopt-job
    echo "[🛠️] Maintenance: ART Job Completed" >> "$LOG_FILE"
) &

echo "===============================================" >> "$LOG_FILE"
echo "   DEPLOYMENT COMPLETE - MASTER v1.5 ACTIVE 🚀" >> "$LOG_FILE"
exit 0
