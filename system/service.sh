#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Service Script
# Based on UM982 template - runs after boot, optimizes usbgps process
##########################################################################################

LOGFILE=/data/local/tmp/gnssdrv.log

logprint() {
  echo "[SERVICE] $(date) $1" >> $LOGFILE
}

logprint "USB GPS Switcher service starting..."

# 等待 boot 完成
wait_for_prop dev.bootcomplete 1 60
BOOT_COMPLETE=$?

if [ "$BOOT_COMPLETE" != "0" ]; then
  logprint "WARNING: Boot complete timeout"
fi

# 如果 USB GPS 启用状态存在，设置进程优先级
if [ -f /data/local/tmp/usb_gps_enabled ]; then
  PID=$(pidof usbgps 2>/dev/null)
  if [ -n "$PID" ]; then
    logprint "Optimizing usbgps process (PID: $PID)..."
    echo -1000 > /proc/$PID/oom_score_adj 2>/dev/null
    echo -17 > /proc/$PID/oom_adj 2>/dev/null
    renice -n -17 -p $PID 2>/dev/null
    logprint "usbgps process optimized"
  else
    logprint "usbgps not running, will start via usbgps.rc"
  fi
fi

logprint "Service complete"
