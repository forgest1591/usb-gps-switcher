#!/system/bin/sh
#
# disable.sh — 恢复内置 GNSS，停止外置
# Magisk 模块禁用时调用（也可手动执行）
#
# 流程：
#   1. 停止外置 GPS 桥接进程
#   2. 清理运行状态
#   3. 恢复内置 GNSS HAL
#   4. 重启位置服务
#

MODDIR="${0%/*}"
if [ "$MODDIR" = "$0" ] || [ "$MODDIR" = "." ]; then
    MODDIR="/data/adb/usb_gps_switcher"
fi

. "$MODDIR/config.sh"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  USB GPS Switcher — 恢复内置 GNSS              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

logI "========================================"
logI "  USB GPS Switcher 禁用脚本"
logI "  恢复内置 GNSS HAL"
logI "========================================"

# ── 检查 root ──────────────────────────────────────────

if ! id | grep -q "uid=0"; then
    logE "需要 root 权限！"
    echo "❌ 需要 root 权限"
    exit 1
fi

# ── 步骤 1: 停止外置桥接进程 ────────────────────────────

echo "【步骤 1/3】停止外置 GPS 桥接"
echo ""

if is_running; then
    OLD_PID=$(cat $PID_FILE 2>/dev/null)
    logI "停止桥接进程 PID=$OLD_PID"
    kill "$OLD_PID" 2>/dev/null
    sleep 1
    
    # 确认已停止
    if kill -0 "$OLD_PID" 2>/dev/null; then
        logW "进程未响应 SIGTERM，发送 SIGKILL"
        kill -9 "$OLD_PID" 2>/dev/null
        sleep 1
    fi
    
    echo "  ✅ 已停止桥接进程 (原 PID: $OLD_PID)"
else
    echo "  ℹ️ 桥接进程未运行"
fi

# 杀掉所有相关残留进程
for pattern in usb_gps_bridge usb_gps_shell usb_gps_switcher; do
    for pid in $(pidof "$pattern" 2>/dev/null); do
        echo "  杀掉残留进程: $pattern (PID $pid)"
        kill "$pid" 2>/dev/null
    done
done

clear_pid
rm -f /data/local/tmp/usb_gps/pid 2>/dev/null
rm -f /data/local/tmp/usb_gps/.external_enabled 2>/dev/null

echo ""

# ── 步骤 2: 清理状态 ────────────────────────────────────

echo "【步骤 2/3】清理运行状态"
echo ""

# 清理临时文件
rm -f /data/local/tmp/usb_gps/bridge.log 2>/dev/null
rm -f /data/local/tmp/usb_gps/driver_pid 2>/dev/null

# 可选：卸载驱动（谨慎，这里保留因为可能还有其他设备用）
# modprobe -r ch343 2>/dev/null
# modprobe -r cdc_acm 2>/dev/null

echo "  ✅ 状态已清理"
echo ""

# ── 步骤 3: 恢复内置 GNSS HAL ───────────────────────────

echo "【步骤 3/3】启动内置 GNSS HAL"
echo ""

start_internal_gnss

# 额外重启 Android 位置服务
setprop ctl.restart location 2>/dev/null
setprop ctl.restart hal_location 2>/dev/null

echo "  ✅ 内置 GNSS 已恢复"
echo ""

# ── 验证 ────────────────────────────────────────────────

echo "【验证】"
echo ""

# 检查内置 GNSS 进程
GNSS_OK=""
for svc in android.hardware.gnss gpsd hal_gps gnss_service; do
    if pgrep -f "$svc" >/dev/null 2>&1; then
        echo "  ✅ $svc 运行中"
        GNSS_OK="yes"
    fi
done

if [ -z "$GNSS_OK" ]; then
    echo "  ℹ️ 未检测到 GNSS 服务，可能需要重启"
fi

# 检查属性
echo ""
echo "【属性】"
echo "  persist.sys.usb.gps.mode : $(getprop persist.sys.usb.gps.mode 2>/dev/null || echo '—')"
echo "  persist.sys.gnss.mode   : $(getprop persist.sys.gnss.mode 2>/dev/null || echo '—')"
echo "  ro.hardware.gps          : $(getprop ro.hardware.gps 2>/dev/null || echo '—')"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ 内置 GNSS 已恢复                            ║"
echo "║                                                  ║"
echo "║  如需切换到外置 GPS，请运行:                     ║"
echo "║    sh $MODDIR/enable.sh                        ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

logI "内置 GNSS 已恢复"

exit 0
