#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Post-FS-Data Script
# Runs before most services start - sets up early GPS configuration
##########################################################################################

LOGFILE=/data/local/tmp/gnssdrv.log

logprint() {
  echo "[POST-FS] $(date) $1" >> $LOGFILE
}

logprint "Post-FS-Data starting..."

# 创建日志目录
mkdir -p /data/local/tmp

# 如果 USB GPS 启用，配置早期属性
if [ -f /data/local/tmp/usb_gps_enabled ]; then
  logprint "USB GPS mode detected, configuring properties..."

  # 停止内置 GNSS 服务
  stop vendor.gnss_service_sprd 2>/dev/null
  stop android.hardware.gnss@1.0-service 2>/dev/null
  stop android.hardware.gnss@2.1-service 2>/dev/null
  stop vendor.qti.gnss-service 2>/dev/null
  stop gnss_service_unisoc 2>/dev/null

  # 设置 USB GPS 就绪属性
  setprop vendor.usb.gps.ready 1
  setprop persist.vendor.icoe.gps_mode external

  logprint "Internal GNSS stopped, USB GPS ready"
fi

logprint "Post-FS-Data complete"
