#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO XL SUPERCHARGER v1.5 [FINAL STABLE]
# Developed by: Drizzy_07
# Target Device: komodo (Google Pixel 9 Pro XL)
# Architecture: Tensor G4 | 16GB LPDDR5X | UFS 4.0
# Optimized for: Android 16 (Evolution X)
# =============================================================

# --- 1. PRE-BOOT INITIALIZATION ---
MOD_DIR="/data/adb/modules/p9pxl_supercharger"
PROP_FILE="$MOD_DIR/module.prop"
LOG_FILE="$MOD_DIR/debug.log"

# Status inicial mientras el sistema termina de cargar
sed -i "s/^description=.*/description=Status: [⏳] Supercharger is waiting for system boot.../" "$PROP_FILE"

# --- 2. DYNAMIC BOOT DETECTION ---
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 10 # Tiempo de gracia para SystemUI

# --- 3. LOGGING & CORE TUNING ---
echo "===============================================" > "$LOG_FILE"
echo "   SUPERCHARGER v1.5 FINAL DIAGNOSTIC" >> "$LOG_FILE"
echo "   Developer: Drizzy_07 | Device: komodo" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

run_tweak() {
    $2 2>>"$LOG_FILE"
    if [ $? -eq 0 ]; then
        echo "[✅] SUCCESS: $1" >> "$LOG_FILE"
    else
        echo "[❌] FAILED: $1 | Error Code: $?" >> "$LOG_FILE"
    fi
}

# 🧠 Memory & ⚡ Storage (UFS 4.0 Stability)
run_tweak "Dalvik GrowthLimit (512M)" "resetprop dalvik.vm.heapgrowthlimit 512m"
run_tweak "VFS Cache Pressure (50)" "echo 50 > /proc/sys/vm/vfs_cache_pressure"

for queue in /sys/block/sd*/queue; do
    echo 128 > "$queue/nr_requests" # Parche para evitar errores de captura
    echo 512 > "$queue/read_ahead_kb"
done

# 🌐 Network & 🎮 UI Logic
run_tweak "TCP Fast Open (3)" "echo 3 > /proc/sys/net/ipv4/tcp_fastopen"
run_tweak "Renderer SkiaVK" "resetprop debug.hwui.renderer skiavk"
run_tweak "Touch Latency Tuning" "resetprop persist.sys.touch.latency 0"

# --- 4. DYNAMIC DASHBOARD ENGINE (LIVE TEMP) ---
# Esta función aclara que la temperatura es en tiempo real
update_dashboard() {
    CUR_TEMP_RAW=$(cat /sys/class/power_supply/battery/temp)
    CUR_TEMP="$((CUR_TEMP_RAW / 10)).$((CUR_TEMP_RAW % 10))°C"
    
    # Texto explícito: "Actual Temp" para informar al usuario
    STATUS="Status: [🚀] v1.5 ACTIVE | 🧠 16GB | ⚡ UFS 4.0 | 🌡️ Actual Temp: $CUR_TEMP | ✅ Stable"
    sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
}

# Bucle de actualización cada 60 segundos
(
    while true; do
        update_dashboard
        sleep 60
    done
) &

# --- 5. STABILIZED MAINTENANCE (ASYNC) ---
(
    sleep 180
    if command -v sqlite3 >/dev/null 2>&1; then
        # Excluir MediaProvider para evitar bloqueos en screenshots
        find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
            sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
        done
    fi
    cmd package bg-dexopt-job
) &

echo "===============================================" >> "$LOG_FILE"
echo "   DEPLOYMENT COMPLETE - ENJOY THE SPEED 🚀" >> "$LOG_FILE"
exit 0
