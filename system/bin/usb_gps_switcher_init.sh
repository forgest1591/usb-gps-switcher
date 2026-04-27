#!/system/bin/sh
#
# system/bin/usb_gps_switcher_init.sh
# Magisk overlay 早期初始化脚本
# 通过 modulectl 或 post-fs-data.d 在系统启动早期运行
#

MODDIR="/data/adb/usb_gps_switcher"
LOG_TAG="usb_gps_init"

log() {
    log -t "$LOG_TAG" -p i "$*"
}

log "USB GPS Switcher 初始化开始..."

# 创建运行时目录
mkdir -p /data/local/tmp/usb_gps
chmod 755 /data/local/tmp/usb_gps

# 设置 USB 串口权限
for dev in /dev/ttyACM* /dev/ttyUSB*; do
    if [ -c "$dev" ]; then
        chmod 666 "$dev" 2>/dev/null
        log "已设置 $dev 权限 (666)"
    fi
done

# 尝试修复 SELinux 上下文
for dev in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyUSB0 /dev/ttyUSB1; do
    if [ -c "$dev" ]; then
        chcon u:object_r:tty_device:s0 "$dev" 2>/dev/null
    fi
done

log "USB GPS Switcher 初始化完成"
exit 0
