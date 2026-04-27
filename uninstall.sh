#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Uninstall Handler
##########################################################################################

MODPATH=${0%/*}
LOGFILE=/data/local/tmp/usb_gps_uninstall.log

logprint() {
  echo "[UNINSTALL] $1" >> $LOGFILE
}

##########################################################################################
# Unpatch boot image
##########################################################################################

unpatch_boot() {
  get_flags
  SLOT=$(grep_cmdline androidboot.slot_suffix)
  if [ -z $SLOT ]; then
    SLOT=$(grep_cmdline androidboot.slot)
    [ -z $SLOT ] || SLOT=_${SLOT}
  fi
  [ "$SLOT" = "normal" ] && unset SLOT
  [ -z $SLOT ] || logprint "- Current boot slot: $SLOT"

  BOOTIMAGE=$(readlink -f "/dev/block/by-name/boot$SLOT")
  find_manager_apk

  eval $BOOTSIGNER -verify < $BOOTIMAGE && BOOTSIGNED=true
  $BOOTSIGNED && logprint "- Boot image is signed with AVB 1.0"

  [ -z $BOOTIMAGE ] && abort "! Unable to detect target image"
  logprint "- Target image: $BOOTIMAGE"

  [ -z $TMPDIR ] && TMPDIR=/dev/tmp
  mkdir -p $TMPDIR
  cd $TMPDIR

  logprint "- Unpacking boot image"
  /data/adb/magisk/magiskboot --unpack "$BOOTIMAGE"

  case $? in
    1) abort "! Unable to unpack boot image" ;;
    2) abort "! ChromeOS boot image detected" ;;
    3) abort "! Sony ELF32 format detected" ;;
    4) abort "! Sony ELF64 format detected" ;;
  esac

  logprint "- Checking ramdisk status"
  if [ -e ramdisk.cpio ]; then
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio test
    STATUS=$?
  else
    STATUS=0
  fi

  case $((STATUS & 3)) in
    0) abort "! Stock boot image" ;;
    1) logprint "- Magisk patched boot image detected" ;;
    2) abort "! Boot image patched by unsupported programs" ;;
  esac

  logprint "- Removing usbgps.rc from ramdisk..."
  /data/adb/magisk/magiskboot --cpio ramdisk.cpio \
    "rm overlay.d/usbgps.rc" 2>&1

  if [ $((STATUS & 4)) -ne 0 ]; then
    logprint "- Compressing ramdisk"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
  fi

  logprint "- Repacking boot image"
  /data/adb/magisk/magiskboot --repack "$BOOTIMAGE" || abort "! Unable to repack boot image!"

  logprint "- Flashing new boot image"
  if ! flash_image new-boot.img "$BOOTIMAGE"; then
    logprint "- Compressing ramdisk to fit in partition"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
    /data/adb/magisk/magiskboot --repack "$BOOTIMAGE"
    flash_image new-boot.img "$BOOTIMAGE" || abort "! Insufficient partition size"
  fi
  /data/adb/magisk/magiskboot --cleanup
  rm -f new-boot.img
}

##########################################################################################
# Restore backup
##########################################################################################

restore_backup() {
  logprint "Restoring original gps.default.so..."
  if [ -f /data/local/tmp/gps.default.so.bak ]; then
    cp /data/local/tmp/gps.default.so.bak /vendor/lib64/hw/gps.default.so 2>/dev/null
    logprint "Restored original gps.default.so"
  fi

  # 清理状态文件
  rm -f /data/local/tmp/usb_gps_enabled
  rm -f /data/local/tmp/usb_gps_disabled
  rm -f /data/local/tmp/gnssdrv.log
}

##########################################################################################
# Main
##########################################################################################

logprint "=== USB GPS Switcher Uninstall ==="
logprint "MODPATH: $MODPATH"

restore_backup
unpatch_boot

logprint "=== Uninstall Complete ==="
echo "USB GPS Switcher 已卸载，请重启手机"
