#!/system/bin/sh

# --- 1. HARDWARE GUARD ---
DEVICE=$(getprop ro.product.device)
MODEL=$(getprop ro.product.model)

ui_print "*********************************************************"
ui_print "  PIXEL 9 PRO SERIES SUPERCHARGER 🚀"
ui_print "  Build: v2.1 STABLE"
ui_print "*********************************************************"

if [ "$DEVICE" != "komodo" ] && [ "$DEVICE" != "caiman" ] && [ "$DEVICE" != "comet" ]; then
  ui_print " [❌] ERROR: INCOMPATIBLE DEVICE"
  abort " ! Aborting installation !"
fi

ui_print " [✅] TARGET HARDWARE VERIFIED: $MODEL"

ui_print " "
ui_print "  ____  _           _    ___  "
ui_print " |  _ \(_)_  _____| |  / _ \ "
ui_print " | |_) | \ \/ / _ \ | | (_) |"
ui_print " |  __/| |>  <  __/ |  \__, |"
ui_print " |_|   |_/_/\_\___|_|    /_/ "
ui_print "  S U P E R C H A R G E R  v2.1 STABLE"
ui_print " "

ui_print "========================================================="
ui_print " ✦ Applying CPU & 16GB Performance Fix..."
sleep 0.2
ui_print " ✦ Injecting TCP 'Race to Sleep' Tweaks..."
sleep 0.2
ui_print " ✦ Initializing Diagnostic Engine..."
ui_print "========================================================="

# --- 2. LOG ENGINE SETUP ---
# Pre-create the log file to ensure it exists regardless of root manager
rm -f $MODPATH/debug.log
touch $MODPATH/debug.log

# --- 3. PERMISSIONS ---
# Set universal write permissions for the log file
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/service.sh 0 0 0755
set_perm $MODPATH/debug.log 0 0 0666
[ -d "$MODPATH/webroot" ] && set_perm_recursive $MODPATH/webroot 0 0 0755 0644
