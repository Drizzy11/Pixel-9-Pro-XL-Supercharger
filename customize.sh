#!/system/bin/sh

DEVICE="$(getprop ro.product.device)"
MODEL="$(getprop ro.product.model)"

ui_print "*********************************************************"
ui_print "  PIXEL 9 PRO SERIES SUPERCHARGER 🚀"
ui_print "  Build: v2.3 BETA.1 ⚡"
ui_print "*********************************************************"

if [ "$DEVICE" != "komodo" ] && [ "$DEVICE" != "caiman" ] && [ "$DEVICE" != "comet" ]; then
  ui_print " [❌] Incompatible device: $DEVICE"
  abort " ! Aborting installation !"
fi

ui_print " [✅] Target hardware verified: $MODEL ($DEVICE)"

ui_print " "
ui_print "  ____  _           _    ___  "
ui_print " |  _ \(_)_  _____| |  / _ \ "
ui_print " | |_) | \ \/ / _ \ | | (_) |"
ui_print " |  __/| |>  <  __/ |  \__, |"
ui_print " |_|   |_/_/\_\___|_|    /_/ "
ui_print "  S U P E R C H A R G E R  v2.3 BETA.1"
ui_print " "

ui_print "========================================================="
ui_print " ✨ Preparing CPU and memory profile..."
sleep 0.2
ui_print " 🌐 Preparing network tuning..."
sleep 0.2
ui_print " 📝 Initializing audit log..."
ui_print "========================================================="

rm -f "$MODPATH/debug.log"
touch "$MODPATH/debug.log"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/debug.log" 0 0 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
