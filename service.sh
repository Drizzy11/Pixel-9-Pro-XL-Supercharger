 
#!/system/bin/sh
# Ultimate Optimization Script by Drizzy_07
# Wait 90 seconds for ROM and SystemUI to stabilize
sleep 90

MOD_DIR="/data/adb/modules/p9pxl_supercharger"
PROP_FILE="$MOD_DIR/module.prop"

# --- 1. MEMORY & DALVIK (16GB RAM Tuning) ---
# Keeps apps in memory and prevents multitasking hangs
resetprop dalvik.vm.heapstartsize 32m
resetprop dalvik.vm.heapgrowthlimit 512m
resetprop dalvik.vm.heapsize 1g
resetprop dalvik.vm.heapmaxfree 64m
resetprop dalvik.vm.heaptargetutilization 0.5
echo "60" > /proc/sys/vm/swappiness

# --- 2. THERMAL & POWER MANAGEMENT ---
# Maintains long-term hardware stability
echo "1" > /sys/devices/system/cpu/cpufreq/policy0/powersave_bias
echo "1" > /sys/devices/system/cpu/cpufreq/policy4/powersave_bias
echo "1" > /sys/devices/system/cpu/cpufreq/policy7/powersave_bias

# --- 3. UI FLUIDITY & GRAPHICS ---
# Enhances 120Hz smoothness and touch sampling
resetprop persist.sys.use_dithering 0
resetprop persist.sys.ui.hw 1
resetprop debug.hwui.renderer skiavk
resetprop ro.config.freetypemaxcached 512
settings put system touch_responsiveness 1

# --- 4. STORAGE I/O (UFS 4.0 Optimization) ---
# Faster loading for games and heavy applications
for queue in /sys/block/sd*/queue
do
    echo "512" > $queue/read_ahead_kb
    echo "0" > $queue/add_random
    echo "0" > $queue/iostats
    echo "none" > $queue/scheduler
done

# --- 5. SYSTEM CLEANUP & LOGS ---
settings put global wifi_scan_interval_ms 300000
settings put global mobile_data_always_on 0
resetprop ro.statsd.enable false
resetprop logcat.live disable

# --- 6. AUTOMATED MAINTENANCE ---
# Optimizes databases and triggers the ART compiler on boot
for db in $(find /data/data -name "*.db"); do
    sqlite3 "$db" "VACUUM;"
    sqlite3 "$db" "REINDEX;"
done
cmd package bg-dexopt-job

# --- 7. DYNAMIC MAGISK DASHBOARD ---
# Updates the UI to show the optimizations are active
VAL_HEAP=$(getprop dalvik.vm.heapgrowthlimit)
VAL_SWAP=$(cat /proc/sys/vm/swappiness)

if [ "$VAL_HEAP" = "512m" ] && [ "$VAL_SWAP" = "60" ]; then
    STATUS="Status: [RUNNING] - System Optimized | Efficiency Profile Active ✅"
else
    STATUS="Status: [ERROR] - Optimization bypassed by system ❌"
fi

# Update the module description in the Magisk app
sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"

exit 0
