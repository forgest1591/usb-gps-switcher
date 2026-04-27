#!/system/bin/sh
#
# enable.sh — 启用外置 GNSS，停止内置
# Magisk 模块启用时调用（也可手动执行）
#
# 流程：
#   1. 扫描并加载 USB-TTL 驱动
#   2. 检测 GNSS 模块串口
#   3. 停止内置 GNSS HAL
#   4. 启动外置 GPS 桥接服务
#

MODDIR="${0%/*}"
if [ "$MODDIR" = "$0" ] || [ "$MODDIR" = "." ]; then
    MODDIR="/data/adb/usb_gps_switcher"
fi

KODIR="$MODDIR/drivers"

# 加载配置
. "$MODDIR/config.sh"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  USB GPS Switcher — 启用外置 GNSS (UN982/UM621A) ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

logI "========================================"
logI "  USB GPS Switcher 启用脚本"
logI "  GNSS 模块: $GNSS_MODULE"
logI "  波特率:   $BAUD_RATE"
logI "========================================"

# ── 前置检查 ──────────────────────────────────────────────

# 创建持久状态标记（Magisk service.sh 启动时读取此文件）
mkdir -p /data/local/tmp/usb_gps
STATE_FLAG="/data/local/tmp/usb_gps/.external_enabled"
touch "$STATE_FLAG"

# 检查 root 权限
if ! id | grep -q "uid=0"; then
    logE "需要 root 权限！请用 su 执行"
    echo "❌ 需要 root 权限，请先执行: su"
    exit 1
fi

# 创建必要目录
mkdir -p "$KODIR"
chmod 755 /data/local/tmp/usb_gps

# ── 步骤 1: 停止现有桥接 ─────────────────────────────────

if is_running; then
    logW "检测到旧桥接进程正在运行，先停止..."
    kill $(cat $PID_FILE) 2>/dev/null
    sleep 1
    clear_pid
fi

# ── 步骤 2: USB-TTL 驱动加载 ──────────────────────────────

echo "【步骤 1/5】USB-TTL 驱动加载"
echo ""

# 尝试枚举所有 USB 串口设备并加载对应驱动
for dev_path in /sys/class/tty/*; do
    dev=$(basename "$dev_path")
    
    # 跳过非 USB 设备
    [ -d "$dev_path/device" ] || continue
    [ -L "$dev_path/device/driver" ] || continue
    
    vid=$(cat "$dev_path/device/idVendor" 2>/dev/null | tr -d ' ')
    pid=$(cat "$dev_path/device/idProduct" 2>/dev/null | tr -d ' ')
    
    if [ -n "$vid" ]; then
        vidpid="${vid}:${pid}"
        echo "  发现 USB 设备: $vidpid → /dev/$dev"
        
        # 根据 VID/PID 加载驱动
        case "$vidpid" in
            1a86:55d3|1a86:55d4)
                DRIVER="ch343"
                echo "  → CH343P/Q 驱动 (ch343)"
                ;;
            1a86:7523|1a86:5523)
                DRIVER="ch340"
                echo "  → CH340 驱动 (ch340/ch341)"
                ;;
            10c4:ea60|10c4:ea71|10c4:ea80)
                DRIVER="cp210x"
                echo "  → CP210x 驱动"
                ;;
            0403:6001|0403:6010|0403:6015|0403:7c90|0403:7c91)
                DRIVER="ftdi_sio"
                echo "  → FTDI 驱动"
                ;;
            067b:2303|067b:25a3|067b:23a3)
                DRIVER="pl2303"
                echo "  → PL2303 驱动"
                ;;
            *)
                DRIVER="cdc_acm"
                echo "  → 通用 CDC-ACM 驱动"
                ;;
        esac
        
        # 尝试加载驱动
        if lsmod | grep -q "^${DRIVER} "; then
            echo "  ✅ 驱动已加载"
        else
            echo -n "  → 加载驱动 $DRIVER... "
            # 1. 先尝试 modprobe
            if modprobe "$DRIVER" 2>/dev/null; then
                echo "✅ (modprobe)"
            # 2. 再尝试 insmod (按优先级)
            elif [ -f "$KODIR/${DRIVER}.ko" ] && insmod "$KODIR/${DRIVER}.ko" 2>/dev/null; then
                echo "✅ (insmod $KODIR/${DRIVER}.ko)"
            elif [ -f "$KODIR/${DRIVER}_tty.ko" ] && insmod "$KODIR/${DRIVER}_tty.ko" 2>/dev/null; then
                echo "✅ (insmod)"
            else
                echo "⚠️  (内核内置/未找到ko)"
            fi
        fi
    fi
done

echo ""

# ── 步骤 3: 检测 GNSS 模块串口 ─────────────────────────────

echo "【步骤 2/5】检测 GNSS 模块"
echo ""

USB_DEV=""
GPS_FOUND=""

for dev in \
    /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2 /dev/ttyACM3 \
    /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3 \
    /dev/ttyUSB4 /dev/ttyUSB5; do
    
    if [ ! -c "$dev" ]; then
        continue
    fi
    
    # 获取 USB 信息
    vidpid=$(get_usb_vidpid "$(basename $dev)")
    echo "  检测设备: $dev ($vidpid)"
    
    # 设置权限
    chmod 666 "$dev" 2>/dev/null
    
    # 尝试从串口读取 NMEA 数据（最多等待 3 秒）
    echo -n "  → 读取 NMEA... "
    
    # 用 timeout 读取一行，3秒超时
    OLDIFS="$IFS"
    IFS=''
    NMEA_TEST=$(timeout 3 cat "$dev" 2>/dev/null | head -1)
    IFS="$OLDIFS"
    
    if [ -n "$NMEA_TEST" ]; then
        echo "✅"
        echo "    收到: ${NMEA_TEST:0:80}"
        USB_DEV="$dev"
        GPS_FOUND="yes"
        
        # 确认是 GNSS 数据
        if echo "$NMEA_TEST" | grep -qE '\$[PG][A-Z]{2}[A-Z]{2}'; then
            echo "    ✅ 确认为 NMEA GNSS 数据"
            break
        fi
    else
        echo "❌ (无数据，可能波特率不匹配)"
    fi
done

if [ -z "$USB_DEV" ]; then
    echo "  ⚠️ 未自动检测到 GNSS 数据，使用默认设备"
    USB_DEV="$USB_GPS_DEV"
fi

echo ""

# ── 步骤 4: 停止内置 GNSS HAL ─────────────────────────────

echo "【步骤 3/5】停止内置 GNSS HAL"
echo ""

stop_internal_gnss

echo "  ✅ 内置 GNSS 已停止"
echo ""

# ── 步骤 5: 启动外置桥接服务 ───────────────────────────────

echo "【步骤 4/5】启动外置 GPS 桥接"
echo ""

# 修复串口权限
fix_permissions "$USB_DEV"

# 选择桥接方案
BRIDGE_PID=""

if [ -x "$MODDIR/bin/usb_gps_bridge" ]; then
    # 原生二进制方案（优先）
    echo "  启动原生桥接 (C++ 方案)..."
    "$MODDIR/bin/usb_gps_bridge" -d "$USB_DEV" -b "$BAUD_RATE" &
    BRIDGE_PID=$!
    echo "  PID: $BRIDGE_PID"
else
    # Shell 方案（后备）
    echo "  启动 Shell 桥接 (无需编译)..."
    
    # 动态检测波特率
    DETECT_BAUD=$(detect_baud_rate "$USB_DEV")
    if [ -n "$DETECT_BAUD" ]; then
        BAUD_RATE="$DETECT_BAUD"
        logI "自动检测波特率: $BAUD_RATE"
    fi
    
    sh "$MODDIR/bin/usb_gps_shell.sh" "$USB_DEV" "$BAUD_RATE" &
    BRIDGE_PID=$!
    echo "  PID: $BRIDGE_PID"
fi

save_pid $BRIDGE_PID
echo ""

# ── 等待 GPS 信号 ─────────────────────────────────────────

echo "【步骤 5/5】等待 GPS 信号锁定"
echo ""

logI "等待 $WARM_UP_SECONDS 秒（首次定位 TTFF）..."
echo "  等待 $WARM_UP_SECONDS 秒让 GPS 天线初始化..."

for i in $(seq 1 $WARM_UP_SECONDS); do
    printf "\r  倒计时: %3d/%d 秒" $i $WARM_UP_SECONDS
    sleep 1
done
echo ""
echo ""

# ── 最终验证 ──────────────────────────────────────────────

echo "【验证】"
echo ""

# 检查进程
if is_running; then
    echo "  ✅ 桥接进程运行中 (PID: $(cat $PID_FILE))"
else
    echo "  ⚠️ 桥接进程已退出，请检查日志"
fi

# 检查 NMEA
NMEA_COUNT=$(logcat -d -s "usb_gps_switcher:V" 2>/dev/null | grep -cE '\$[PG][A-Z]{2}[A-Z]{2}' || echo "0")
echo "  NMEA 语句计数: $NMEA_COUNT 条"

if [ "$NMEA_COUNT" -gt 0 ]; then
    echo "  ✅ GPS 数据流正常!"
else
    echo "  ℹ️ 无 NMEA 记录（可能尚未收到有效信号，需户外天线）"
fi

# 检查内置 GNSS 是否确实停止
GNSS_STOPPED=""
for svc in android.hardware.gnss gpsd hal_gps; do
    if ! pgrep -f "$svc" >/dev/null 2>&1; then
        GNSS_STOPPED="yes"
    fi
done

if [ "$GNSS_STOPPED" = "yes" ]; then
    echo "  ✅ 内置 GNSS 已禁用"
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  ✅ 外置 GNSS 已启用                              ║"
echo "║                                                  ║"
echo "║  设备:   $USB_DEV"
echo "║  波特率: $BAUD_RATE"
echo "║  模块:   $GNSS_MODULE"
echo "║  PID:    $(cat $PID_FILE 2>/dev/null || echo 'N/A')"
echo "║                                                  ║"
echo "║  恢复内置: sh $MODDIR/disable.sh"
echo "║  查看状态: sh $MODDIR/status.sh"
echo "╚══════════════════════════════════════════════════╝"
echo ""

logI "外置 GNSS 启用完成"

exit 0
