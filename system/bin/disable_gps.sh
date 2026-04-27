#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Disable External GPS
# Switches back to built-in GPS (restores original HAL)
##########################################################################################

LOGFILE=/data/local/tmp/usb_gps_disable.log

logprint() {
  echo "[DISABLE] $(date) $1" | tee -a $LOGFILE
}

##########################################################################################
# Main
##########################################################################################

main() {
  logprint "========================================="
  logprint "USB GPS Switcher - Disable External GPS"
  logprint "========================================="

  # 创建禁用状态标记
  touch /data/local/tmp/usb_gps_disabled
  rm -f /data/local/tmp/usb_gps_enabled 2>/dev/null
  rm -f /data/local/tmp/usb_gps_config.sh 2>/dev/null

  # 停止 USB GPS 服务
  logprint "Stopping USB GPS service..."
  stop myusbgps 2>/dev/null
  setprop ctl.stop myusbgps 2>/dev/null

  # 强制杀死残留进程
  killall usbgps 2>/dev/null

  # 重置系统属性
  logprint "Resetting system properties..."
  setprop vendor.usb.gps.mode internal 2>/dev/null
  setprop persist.vendor.icoe.gps_mode internal 2>/dev/null
  setprop persist.sys.gnss.mode auto 2>/dev/null
  setprop vendor.usb.gps.ready 0 2>/dev/null

  # 删除内部 GPS 禁用标记
  rm -f /data/local/tmp/vendor.gnss_service_sprd.disabled 2>/dev/null

  # 等待进程退出
  sleep 2

  # 恢复并启动内置 GNSS 服务
  logprint "Restarting internal GNSS services..."
  start vendor.gnss_service_sprd 2>/dev/null
  setprop ctl.start vendor.gnss_service_sprd 2>/dev/null

  start android.hardware.gnss@1.0-service 2>/dev/null
  start android.hardware.gnss@2.1-service 2>/dev/null
  start vendor.qti.gnss-service 2>/dev/null

  # 等待服务启动
  sleep 3

  # 检查内置 GNSS 是否运行
  GNSS_PID=$(pidof vendor.gnss_service_sprd 2>/dev/null)
  if [ -n "$GNSS_PID" ]; then
    logprint "SUCCESS: Internal GNSS is running (PID: $GNSS_PID)"
  else
    logprint "Internal GNSS may still be starting..."
  fi

  logprint "========================================="
  logprint "已切换回内置 GPS"
  logprint "请重启手机使更改完全生效"
}

main "$@"
