##########################################################################################
# USB GPS Switcher for Android 13 - Magisk Module Installer
# Based on UM982 template architecture
##########################################################################################

SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=true
LATESTARTSERVICE=true

# Replace overlay.d to inject rc file
REPLACE="/overlay.d"

##########################################################################################
# Module Info
##########################################################################################

print_modname() {
  ui_print "*******************************"
  ui_print "  USB GPS Switcher v2.0"
  ui_print "  UIS7870 / UNISOC / Android 13"
  ui_print "*******************************"
}

##########################################################################################
# Installation
##########################################################################################

install_main() {
  ui_print "[1/6] Setting file permissions..."

  # 可执行文件
  set_perm $MODPATH/system/vendor/bin/usbgps    0  0  0755
  set_perm $MODPATH/system/bin/enable_gps.sh    0  0  0755
  set_perm $MODPATH/system/bin/disable_gps.sh   0  0  0755
  set_perm $MODPATH/system/bin/gps_status.sh     0  0  0755

  # Shell 脚本
  set_perm $MODPATH/system/service.sh            0  0  0755
  set_perm $MODPATH/system/customize.sh          0  0  0755
  set_perm $MODPATH/system/post-fs-data.sh       0  0  0755

  # HAL 库
  set_perm $MODPATH/system/vendor/lib64/hw/gps.default.so  0  0  0644
  set_perm $MODPATH/system/vendor/lib64/android.hardware.gnss@1.0.so  0  0  0644
  set_perm $MODPATH/system/vendor/lib64/android.hardware.gnss@2.1.so  0  0  0644
  set_perm $MODPATH/system/vendor/lib64/android.hardware.gnss-V2-ndk.so  0  0  0644
  set_perm $MODPATH/system/lib64/android.hardware.gnss@1.0.so  0  0  0644
  set_perm $MODPATH/system/lib64/android.hardware.gnss@2.1.so  0  0  0644
  set_perm $MODPATH/system/lib64/libandroid_servers.so  0  0  0644

  ui_print "[2/6] Patching boot image (injecting usbgps.rc)..."
  patch_boot

  ui_print "[3/6] Creating GPS state files..."
  mkdir -p /data/local/tmp
  touch /data/local/tmp/usb_gps_enabled

  ui_print "[4/6] Configuring system properties..."
  # GPS 属性由 system.prop 设置

  ui_print "[5/6] Backup original gps.default.so..."
  if [ -f /vendor/lib64/hw/gps.default.so ]; then
    cp /vendor/lib64/hw/gps.default.so /data/local/tmp/gps.default.so.bak 2>/dev/null
  fi

  ui_print "[6/6] Installation complete!"
  ui_print ""
  ui_print "模块启用后请重启手机使 USB GPS 生效"
  ui_print "使用 'enable_gps.sh' 启用外置 GPS"
  ui_print "使用 'disable_gps.sh' 禁用并恢复内置 GPS"
}

##########################################################################################
# Permissions
##########################################################################################

set_permissions() {
  ui_print "[0/4] Setting permissions..."
  # 已在 install_main 中设置
}

##########################################################################################
# Boot Image Patching (Core - from UM982 template)
##########################################################################################

patch_boot() {
  get_flags
  SLOT=$(grep_cmdline androidboot.slot_suffix)
  if [ -z $SLOT ]; then
    SLOT=$(grep_cmdline androidboot.slot)
    [ -z $SLOT ] || SLOT=_${SLOT}
  fi
  [ "$SLOT" = "normal" ] && unset SLOT
  [ -z $SLOT ] || ui_print "- Current boot slot: $SLOT"

  BOOTIMAGE=$(readlink -f "/dev/block/by-name/boot$SLOT")
  find_manager_apk

  eval $BOOTSIGNER -verify < $BOOTIMAGE && BOOTSIGNED=true
  $BOOTSIGNED && ui_print "- Boot image is signed with AVB 1.0"

  [ -z $BOOTIMAGE ] && abort "! Unable to detect target image"
  ui_print "- Target image: $BOOTIMAGE"
  [ -e "$BOOTIMAGE" ] || abort "$BOOTIMAGE does not exist!"

  ui_print "- Unpacking boot image"
  /data/adb/magisk/magiskboot --unpack "$BOOTIMAGE"

  case $? in
    1) abort "! Unable to unpack boot image" ;;
    2) abort "! ChromeOS boot image detected - unsupported" ;;
    3) abort "! Sony ELF32 format detected - unsupported" ;;
    4) abort "! Sony ELF64 format detected - unsupported" ;;
  esac

  ui_print "- Checking ramdisk status"
  if [ -e ramdisk.cpio ]; then
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio test
    STATUS=$?
  else
    STATUS=0
  fi

  case $((STATUS & 3)) in
    0) abort "! Stock boot image - please install Magisk first" ;;
    1) ui_print "- Magisk patched boot image detected" ;;
    2) abort "! Boot image patched by unsupported programs" ;;
  esac

  if [ $((STATUS & 8)) -ne 0 ]; then
    export TWOSTAGEINIT=true
  fi

  ui_print "- Patching ramdisk (injecting usbgps.rc)..."
  /data/adb/magisk/magiskboot --cpio ramdisk.cpio \
    "mkdir 755 overlay.d" \
    "mkdir 755 overlay.d/sbin" \
    "add 644 overlay.d/usbgps.rc $MODPATH/common/usbgps.rc" 2>&1

  if [ $((STATUS & 4)) -ne 0 ]; then
    ui_print "- Compressing ramdisk"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
  fi

  ui_print "- Repacking boot image"
  /data/adb/magisk/magiskboot --repack "$BOOTIMAGE" || abort "! Unable to repack boot image!"

  ui_print "- Flashing new boot image"
  if ! flash_image new-boot.img "$BOOTIMAGE"; then
    ui_print "- Compressing ramdisk to fit in partition"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
    /data/adb/magisk/magiskboot --repack "$BOOTIMAGE"
    flash_image new-boot.img "$BOOTIMAGE" || abort "! Insufficient partition size"
  fi
  /data/adb/magisk/magiskboot --cleanup
  rm -f new-boot.img
}

install_main
