#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Enable External GPS
# Switches from built-in GPS to USB GPS (HAL replacement mode)
##########################################################################################

LOGFILE=/data/local/tmp/usb_gps_enable.log
CONFIG_FILE="/data/local/tmp/usb_gps_config.sh"

logprint() {
  echo "[ENABLE] $(date) $1" | tee -a $LOGFILE
}

##########################################################################################
# GPS Configuration (customize for your module)
##########################################################################################

GPS_MODE="um982"                    # GPS module type: um982, ch343, auto
GPS_BAUD="460800"                   # Baud rate
GPS_TTY_AUTO="true"                 # Auto-detect TTY device
GPS_TTY_DEVICE="/dev/ttyUSB0"       # Default TTY device
GPS_PROTOCOL="nmea"                 # Protocol: nmea, ubx, rtcm
GPS_LOGGING="true"                  # Enable NMEA logging
GPS_SOCKET="/dev/socket/gps"        # GPS socket path

##########################################################################################
# Main
##########################################################################################

main() {
  logprint "========================================="
  logprint "USB GPS Switcher - Enable External GPS"
  logprint "========================================="

  # 保存配置
  cat > $CONFIG_FILE << 'CONFIG_EOF'
GPS_MODE="um982"
GPS_BAUD="460800"
GPS_TTY_AUTO="true"
GPS_TTY_DEVICE="/dev/ttyUSB0"
GPS_PROTOCOL="nmea"
GPS_LOGGING="true"
CONFIG_EOF

  # 创建启用状态标记
  touch /data/local/tmp/usb_gps_enabled
  rm -f /data/local/tmp/usb_gps_disabled 2>/dev/null

  # 设置系统属性
  logprint "Setting system properties..."
  setprop vendor.usb.gps.mode external 2>/dev/null
  setprop persist.vendor.icoe.gps_mode external 2>/dev/null
  setprop persist.sys.gnss.mode external 2>/dev/null
  setprop vendor.usb.gps.ready 1 2>/dev/null

  # 停止内置 GNSS 服务
  logprint "Stopping internal GNSS services..."
  stop vendor.gnss_service_sprd 2>/dev/null
  stop android.hardware.gnss@1.0-service 2>/dev/null
  stop android.hardware.gnss@2.1-service 2>/dev/null
  stop android.hardware.gnss@2.1-impl 2>/dev/null
  stop vendor.qti.gnss-service 2>/dev/null
  stop gnss_service_unisoc 2>/dev/null
  stop sprd_gps 2>/dev/null

  # 禁用内置 GPS 属性
  logprint "Disabling internal GPS..."
  setprop ctl.stop vendor.gnss_service_sprd 2>/dev/null

  # 等待服务停止
  sleep 2

  # 启动 USB GPS 服务
  logprint "Starting USB GPS service (myusbgps)..."
  start myusbgps 2>/dev/null
  setprop ctl.start myusbgps 2>/dev/null

  # 等待服务启动
  sleep 3

  # 检查服务状态
  PID=$(pidof usbgps 2>/dev/null)
  if [ -n "$PID" ]; then
    logprint "SUCCESS: usbgps is running (PID: $PID)"

    # 优化进程优先级
    echo -1000 > /proc/$PID/oom_score_adj 2>/dev/null
    echo -17 > /proc/$PID/oom_adj 2>/dev/null
    renice -n -17 -p $PID 2>/dev/null

    logprint "USB GPS is now active!"
    logprint ""
    logprint "请重启手机使更改完全生效"
    logprint "状态: /data/local/tmp/usb_gps_enabled"
  else
    logprint "WARNING: usbgps service may not have started"
    logprint "Check logs: /data/local/tmp/gnssdrv.log"
    logprint ""
    logprint "如果启动失败，请检查:"
    logprint "1. USB GPS 模块是否已连接"
    logprint "2. TTY 设备路径是否正确"
    logprint "3. 使用 'gps_status.sh --diagnose' 诊断"
  fi

  logprint "========================================="
}

main "$@"
