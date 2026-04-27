#!/system/bin/sh
##########################################################################################
# USB GPS Switcher - Status & Diagnostics
##########################################################################################

MODE="$1"
LOGFILE=/data/local/tmp/usb_gps_status.log

logprint() {
  echo "$1" | tee -a $LOGFILE
}

print_status() {
  logprint "=========================================="
  logprint "  USB GPS Switcher - Status"
  logprint "=========================================="
  logprint ""

  # GPS 模式状态
  if [ -f /data/local/tmp/usb_gps_enabled ]; then
    logprint "🟢 GPS 模式: 外置 USB GPS (启用)"
  elif [ -f /data/local/tmp/usb_gps_disabled ]; then
    logprint "🔵 GPS 模式: 内置 GPS (启用)"
  else
    logprint "⚪ GPS 模式: 未配置"
  fi
  logprint ""

  # 系统属性
  logprint "--- 系统属性 ---"
  getprop | grep -iE "gps|gnss|location" | while read line; do
    logprint "  $line"
  done
  logprint ""

  # GNSS 服务状态
  logprint "--- GNSS 服务 ---"
  for svc in usbgps vendor.gnss_service_sprd android.hardware.gnss@1.0-service android.hardware.gnss@2.1-service vendor.qti.gnss-service gnss_service_unisoc sprd_gps; do
    PID=$(pidof $svc 2>/dev/null)
    if [ -n "$PID" ]; then
      logprint "  🟢 $svc (PID: $PID)"
    else
      logprint "  ⚫ $svc (未运行)"
    fi
  done
  logprint ""

  # USB GPS 设备
  logprint "--- USB GPS 设备 ---"
  for dev in /dev/ttyACM* /dev/ttyUSB* /dev/ttyS*; do
    if [ -e "$dev" ]; then
      logprint "  📱 $dev"
    fi
  done
  logprint ""

  # USB GPS 串口
  logprint "--- USB 设备 (GPS 相关) ---"
  lsusb 2>/dev/null | grep -iE "usb gps|uart|serial|ch343|ch340|cp210|ftdi|pl230" || logprint "  (无匹配的 USB GPS 设备)"
  logprint ""

  # 进程
  logprint "--- 相关进程 ---"
  ps -A 2>/dev/null | grep -iE "gps|gnss|nmea|ubx" | while read line; do
    logprint "  $line"
  done
  logprint ""

  # 日志文件
  logprint "--- 日志文件 ---"
  for f in /data/local/tmp/gnssdrv.log /data/local/tmp/usb_gps_enable.log /data/local/tmp/usb_gps_disable.log; do
    if [ -f "$f" ]; then
      SIZE=$(wc -c < "$f" 2>/dev/null || echo "0")
      logprint "  📄 $f ($SIZE bytes)"
      logprint "  最后 5 行:"
      tail -n 5 "$f" | sed 's/^/    /'
    fi
  done
}

print_diagnose() {
  logprint "=========================================="
  logprint "  USB GPS - 完整诊断报告"
  logprint "=========================================="
  logprint ""
  logprint "生成时间: $(date)"
  logprint ""

  # 设备信息
  logprint "--- 设备信息 ---"
  logprint "Android 版本: $(getprop ro.build.version.release)"
  logprint "SDK 版本: $(getprop ro.build.version.sdk)"
  logprint "SOC: $(getprop ro.board.platform)"
  logprint "内核版本: $(uname -r)"
  logprint ""

  # 内核 GPS 模块
  logprint "--- 内核 GPS 模块 ---"
  for mod in usbserial ch341 cdc_acm ftdi_sio pl2303; do
    if lsmod 2>/dev/null | grep -q "$mod"; then
      logprint "  ✓ $mod 已加载"
    else
      logprint "  ✗ $mod 未加载"
    fi
  done
  logprint ""

  # GPS 库文件
  logprint "--- GPS HAL 库 ---"
  for f in /vendor/lib64/hw/gps.default.so /system/vendor/lib64/hw/gps.default.so; do
    if [ -f "$f" ]; then
      SIZE=$(ls -lh "$f" 2>/dev/null | awk '{print $5}')
      ORIGIN=$(echo "$f" | grep -q "magisk" && echo "(Magisk)" || echo "(原厂)")
      logprint "  ✓ $f $SIZE $ORIGIN"
    else
      logprint "  ? $f 不存在"
    fi
  done
  logprint ""

  # init.rc 服务定义
  logprint "--- usbgps.rc 服务 ---"
  if grep -q "myusbgps" /vendor/etc/init/*.rc 2>/dev/null; then
    logprint "  ✓ myusbgps 服务已注册"
  else
    logprint "  ? myusbgps 服务未在 /vendor/etc/init/ 中找到"
  fi
  if grep -q "myusbgps" /system/etc/init/*.rc 2>/dev/null; then
    logprint "  ✓ myusbgps 服务已在 system 中注册"
  fi
  logprint ""

  # SELinux 状态
  logprint "--- SELinux 状态 ---"
  SELINUX=$(getenforce 2>/dev/null)
  logprint "  SELinux: $SELINUX"
  logprint ""

  # 网络连通性测试
  logprint "--- USB GPS 模块测试 ---"
  for dev in /dev/ttyACM0 /dev/ttyUSB0 /dev/ttyUSB1; do
    if [ -e "$dev" ]; then
      logprint "  测试 $dev..."
      # 尝试读取 1 秒的 NMEA 数据
      TIMEOUT_OUTPUT=$(timeout 1 cat "$dev" 2>/dev/null || cat "$dev" 2>/dev/null | head -c 200)
      if echo "$TIMEOUT_OUTPUT" | grep -q "\\$G"; then
        logprint "  ✓ $dev 有有效的 NMEA 数据"
        logprint "  样例: $(echo "$TIMEOUT_OUTPUT" | head -n 1 | cut -c1-80)"
      else
        logprint "  ⚠ $dev 无 NMEA 数据 (设备可能未输出或波特率不匹配)"
      fi
    fi
  done
  logprint ""

  # 内存和 CPU
  logprint "--- usbgps 资源使用 ---"
  USBGPS_PID=$(pidof usbgps 2>/dev/null)
  if [ -n "$USBGPS_PID" ]; then
    CPU=$(top -n 1 -p "$USBGPS_PID" 2>/dev/null | grep "$USBGPS_PID" | awk '{print $9}')
    MEM=$(ps -o rss= -p "$USBGPS_PID" 2>/dev/null)
    logprint "  PID: $USBGPS_PID, CPU: ${CPU}%, MEM: ${MEM}KB"
  else
    logprint "  usbgps 未运行"
  fi
  logprint ""

  logprint "=========================================="
  logprint "诊断完成。请查看上方日志或:"
  logprint "cat /data/local/tmp/usb_gps_status.log"
}

##########################################################################################
# Main
##########################################################################################

case "$MODE" in
  --diagnose|-d)
    print_diagnose
    ;;
  --help|-h)
    echo "用法: gps_status.sh [选项]"
    echo "  无参数   - 显示简要状态"
    echo "  --diagnose - 完整诊断报告"
    echo "  --help    - 显示此帮助"
    ;;
  *)
    print_status
    ;;
esac
