#!/system/bin/sh
#
# status.sh — USB GPS Switcher 状态查询
# 支持 Android 10/11/12/13/14
#

MODDIR="/data/adb/usb_gps_switcher"
. "$MODDIR/config.sh" 2>/dev/null

# 解析参数
DIAGNOSE=""
[ "$1" = "-d" ] || [ "$1" = "--diagnose" ] && DIAGNOSE="yes"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║       USB GPS Switcher — 状态报告                   ║"
echo "║       $(date +%Y-%m-%d\ %H:%M:%S)"
echo "║       系统: ${ANDROID_VER_NAME:-Android}"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 诊断模式 ─────────────────────────────────────────────
if [ "$DIAGNOSE" = "yes" ]; then
    echo "【诊断模式】"
    diagnose_gnss_services
    exit 0
fi

# ── USB 设备 ─────────────────────────────────────────────
echo "【USB 串口设备】"
for dev in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2 \
           /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
    if [ -c "$dev" ]; then
        vid=$(cat /sys/class/tty/${dev##*/}/device/idVendor 2>/dev/null | tr -d ' ')
        pid=$(cat /sys/class/tty/${dev##*/}/device/idProduct 2>/dev/null | tr -d ' ')
        echo "  ✅ $dev  (VID:PID = ${vid:-—}:${pid:-—})"
    fi
done
ls -la /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | grep "^c" | while IFS= read -r line; do
    echo "  ? $line"
done
echo ""

# ── 已加载驱动 ───────────────────────────────────────────
echo "【USB-TTL 驱动状态】"
DRIVERS_LOADED=""
for drv in ch343 ch340 cp210x ftdi_sio pl2303 cdc_acm; do
    if lsmod | grep -q "^$drv "; then
        echo "  ✅ $drv 已加载"
        DRIVERS_LOADED="yes"
    fi
done
[ -z "$DRIVERS_LOADED" ] && echo "  ℹ️ 未检测到串口驱动（可能内置）"
echo ""

# ── 桥接进程 ─────────────────────────────────────────────
echo "【外置桥接进程】"
if is_running 2>/dev/null; then
    PID=$(cat $PID_FILE 2>/dev/null || echo "?")
    CMD=$(ps -p "$PID" -o comm= 2>/dev/null || echo "?")
    CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | tr -d ' ')
    MEM=$(ps -p "$PID" -o rss= 2>/dev/null | tr -d ' ')
    echo "  ✅ 运行中  PID=$PID  cmd=$CMD  CPU=${CPU}%  MEM=${MEM}KB"
    
    # 检查读取的设备
    if [ -d "/proc/$PID/fd" ]; then
        for fd in /proc/$PID/fd/*; do
            tgt=$(readlink "$fd" 2>/dev/null)
            case "$tgt" in
                /dev/ttyACM*|/dev/ttyUSB*)
                    echo "     读取串口: $tgt"
                    break
                    ;;
            esac
        done
    fi
else
    echo "  ⭕ 未运行"
fi
echo ""

# ── 内置 GNSS ─────────────────────────────────────────────
echo "【内置 GNSS HAL】"
GNSS_ON=""
for svc in android.hardware.gnss@1.0 android.hardware.gnss@2.0 gpsd hal_gps; do
    if pgrep -f "$svc" >/dev/null 2>&1; then
        echo "  ✅ $svc 运行中"
        GNSS_ON="yes"
    fi
done
[ -z "$GNSS_ON" ] && echo "  ⭕ 已禁用"
echo ""

# ── GPS 模式判定 ─────────────────────────────────────────
echo "【当前 GPS 模式】"
MODE="未知"
if is_running 2>/dev/null; then
    MODE="🔷 外置 GNSS"
    echo "  $MODE"
    echo "     模块: $GNSS_MODULE"
    echo "     设备: $(cat /proc/$(cat $PID_FILE 2>/dev/null)/fd/* 2>/dev/null | grep -m1 tty || echo $USB_GPS_DEV)"
    echo "     波特率: $BAUD_RATE"
else
    MODE="🔶 内置 GNSS"
    echo "  $MODE"
fi
echo ""

# ── GPS 信号 ──────────────────────────────────────────────
echo "【GPS 信号质量】"
GGA=$(logcat -d -s "usb_gps_switcher:V" 2>/dev/null | grep '$GNGGA' | tail -1)
[ -z "$GGA" ] && GGA=$(logcat -d -s "usb_gps_switcher:V" 2>/dev/null | grep '$GPGGA' | tail -1)

if [ -n "$GGA" ]; then
    QUAL=$(echo "$GGA" | cut -d',' -f7)
    NSAT=$(echo "$GGA" | cut -d',' -f8)
    HDOP=$(echo "$GGA" | cut -d',' -f9)
    ALT=$(echo "$GGA" | cut -d',' -f10)
    
    case "$QUAL" in
        0) QSTR="❌ 无效" ;;
        1) QSTR="✅ GPS (SPS)" ;;
        2) QSTR="✅ DGPS" ;;
        4) QSTR="🚀 RTK Fixed" ;;
        5) QSTR="🚀 RTK Float" ;;
        *) QSTR="⚠️ 未知($QUAL)" ;;
    esac
    
    echo "  定位质量: $QSTR"
    echo "  卫星数:  $NSAT"
    echo "  HDOP:    ${HDOP:-—} (越小越精确)"
    echo "  海拔:    ${ALT:-—}m"
    echo "  GGA:     ${GGA:0:60}..."
else
    echo "  ℹ️ 暂无 GGA 数据"
fi
echo ""

# ── 最近 NMEA ─────────────────────────────────────────────
echo "【最新 NMEA 语句】"
NMEA=$(logcat -d -s "usb_gps_switcher:V" 2>/dev/null | grep -E '^\[.*\]\s+\$[PG][A-Z]{2}' | tail -3)
if [ -n "$NMEA" ]; then
    echo "$NMEA" | while IFS= read -r line; do
        echo "  $line"
    done
else
    echo "  ℹ️ 无 NMEA 记录"
fi
echo ""

# ── 系统属性 ─────────────────────────────────────────────
echo "【系统属性】"
echo "  GNSS 模块:    $(getprop persist.sys.gnss.module 2>/dev/null || echo '—')"
echo "  GPS 模式:    $(getprop persist.sys.usb.gps.mode 2>/dev/null || echo '—')"
echo "  硬件 GPS:    $(getprop ro.hardware.gps 2>/dev/null || echo '—')"
echo ""

echo "╔══════════════════════════════════════════════════════╗"
echo "║  启用外置: sh $MODDIR/enable.sh"
echo "║  恢复内置: sh $MODDIR/disable.sh"
echo "║  诊断模式: sh $MODDIR/status.sh --diagnose"
echo "║  模块目录: $MODDIR"
echo "║  配置文件: $MODDIR/config.sh"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
