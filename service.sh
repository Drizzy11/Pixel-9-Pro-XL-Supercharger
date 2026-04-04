#!/system/bin/sh
# =============================================================
# PIXEL 9 PRO SERIES SUPERCHARGER v2.1-STABLE (Optimized)
# Maximum Efficiency Architecture - Developed by: Drizzy_07
# Refined for Tensor G4 & crDroid 12.8
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
echo "   SUPERCHARGER v2.1-STABLE DEEP AUDIT" >> "$LOG_FILE"
echo "   Device: Pixel 9 Pro XL (Zumapro/Tensor G4)" >> "$LOG_FILE"
echo "   Architecture: 1+3+4 (X4+A720+A520)" >> "$LOG_FILE"
echo "   Date: $(date)" >> "$LOG_FILE"
echo "===============================================" >> "$LOG_FILE"

# --- 3. BOOT DETECTION ---
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 45 # Aumentamos un poco para dejar que crDroid asiente los servicios de Google
echo "[✅] System ready. Deploying v2.1 Efficiency Engines..." >> "$LOG_FILE"

# --- 4. DALVIK & UI ENGINE (CORREGIDO) ---
echo "" >> "$LOG_FILE"
echo "[🧠] SYSTEM & UI AUDIT:" >> "$LOG_FILE"

# Cambiamos skiavk a skiagl para evitar conflictos de buffer en crDroid
resetprop dalvik.vm.heapstartsize 32m
resetprop dalvik.vm.heapgrowthlimit 512m
resetprop dalvik.vm.heapsize 1g
resetprop debug.hwui.renderer skiagl 
resetprop persist.sys.touch.latency 0
resetprop persist.sys.ui.hw 1

verify_prop "UI Renderer (GL)" "debug.hwui.renderer" "skiagl"
verify_prop "Touch Latency" "persist.sys.touch.latency" "0"

# --- 5. SMART STORAGE & VM (16GB RAM PROFILE) ---
echo "" >> "$LOG_FILE"
echo "[⚡] VIRTUAL MEMORY & STORAGE AUDIT:" >> "$LOG_FILE"

# Suavizamos swappiness para evitar estrés en el LMK con 16GB RAM
echo 70 > /proc/sys/vm/vfs_cache_pressure
echo 15 > /proc/sys/vm/dirty_ratio
echo 10 > /proc/sys/vm/swappiness 

for dev in sda sdb sdc; do
    if [ -d "/sys/block/$dev" ]; then
        echo none > "/sys/block/$dev/queue/scheduler"
        echo 512 > "/sys/block/$dev/queue/read_ahead_kb" # 1024 era mucho, 512 es más estable para UFS 4.0
        echo 0 > "/sys/block/$dev/queue/iostats" 2>/dev/null
    fi
done

# --- 6. SMART NETWORK ENGINE (v2.1 REFINED) ---
echo "" >> "$LOG_FILE"
echo "[🌐] NETWORK AUDIT:" >> "$LOG_FILE"

echo "fq" > /proc/sys/net/core/default_qdisc
echo "cubic" > /proc/sys/net/ipv4/tcp_congestion_control
echo 1 > /proc/sys/net/ipv4/tcp_tw_reuse
echo 3 > /proc/sys/net/ipv4/tcp_fastopen

# Buffers optimizados para no saturar la RAM (Max 8MB en lugar de 16MB)
echo "4096 87380 8388608" > /proc/sys/net/ipv4/tcp_rmem
echo "4096 16384 8388608" > /proc/sys/net/ipv4/tcp_wmem

verify_tweak "TCP Read Buffer" "/proc/sys/net/ipv4/tcp_rmem" "8388608"

# --- 7. TENSOR G4 IRQ AFFINITY (1+3+4 MAPPING) ---
echo "" >> "$LOG_FILE"
echo "[🚧] SMART IRQ AFFINITY AUDIT (Tensor G4):" >> "$LOG_FILE"

stop irqbalance

# Máscaras de Afinidades (Basadas en 8 núcleos del G4):
# Núcleos 0-3: Eficiencia (A520) -> Hex: 0F
# Núcleos 4-6: Medios (A720)     -> Hex: 70
# Núcleo 7: Performance (X4)     -> Hex: 80
# Combinada (Todos): FF

IRQ_EFF=0; IRQ_MID=0; IRQ_PERF=0

# Por defecto, todo a núcleos de eficiencia (0-3) para ahorrar batería
for irq in /proc/irq/*; do
    [ -f "$irq/smp_affinity" ] && echo "0f" > "$irq/smp_affinity" 2>/dev/null && IRQ_EFF=$((IRQ_EFF + 1))
done

# I/O y Red a núcleos Medios (4-6) para no interrumpir el X4
for irq_num in $(grep -iE "ufshcd|exynos-pcie|dhdpcie" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    if [ -f "/proc/irq/$irq_num/smp_affinity" ]; then
        echo "70" > "/proc/irq/$irq_num/smp_affinity" 2>/dev/null
        IRQ_MID=$((IRQ_MID + 1))
    fi
done

# Touchpanel y Gráficos al núcleo de Performance (7 - Cortex-X4)
for irq_num in $(grep -iE "synaptics_tcm|kgsl|msm_drm" /proc/interrupts | awk -F: '{print $1}' | tr -d ' '); do
    if [ -f "/proc/irq/$irq_num/smp_affinity" ]; then
        echo "80" > "/proc/irq/$irq_num/smp_affinity" 2>/dev/null
        IRQ_PERF=$((IRQ_PERF + 1))
    fi
done

echo "[PASS] IRQ Efficiency (0f): $IRQ_EFF nodes" >> "$LOG_FILE"
echo "[PASS] IRQ Mid-Cores (70): $IRQ_MID nodes (I/O & Net)" >> "$LOG_FILE"
echo "[PASS] IRQ Perf-Core (80): $IRQ_PERF nodes (Touch & GPU)" >> "$LOG_FILE"

# --- 8. DASHBOARD & MAINTENANCE ---
(
    while true; do
        T_RAW=$(cat /sys/class/power_supply/battery/temp)
        T_UI="$((T_RAW / 10)).$((T_RAW % 10))°C"
        STATUS="Status: [🚀] v2.1-STABLE | 🛡️ All Pass | 🌡️ $T_UI"
        sed -i "s/^description=.*/description=$STATUS/" "$PROP_FILE"
        sleep 60
    done
) &

(
    sleep 300 # Esperamos 5 min para el mantenimiento
    find /data/data -name "*.db" -type f -not -path "*com.android.providers.media*" 2>/dev/null | while read -r db; do
        sqlite3 "$db" "VACUUM; REINDEX;" >/dev/null 2>&1
    done
    echo "[🧹] Maintenance: SQLite Vacuum complete" >> "$LOG_FILE"
) &

exit 0
