#!/system/bin/sh
#
# ============================================================
# USB GPS Switcher — 配置文件
# UIS7870 / Android 13 / UN982 & UM621A 全星全频 GNSS
# ============================================================

MODDIR="/data/adb/usb_gps_switcher"
KODIR="$MODDIR/drivers"

# ═══════════════════════════════════════════════════════════
#  ★ 基础配置 — 根据你的硬件修改这些参数
# ═══════════════════════════════════════════════════════════

# ── Android 版本检测 ──────────────────────────────────────

ANDROID_VERSION=$(getprop ro.build.version.sdk 2>/dev/null || echo "30")
# Android 10 = 29, Android 11 = 30, Android 12 = 31, Android 13 = 33, Android 14 = 34

case "$ANDROID_VERSION" in
    29) ANDROID_VER_NAME="Android 10" ;;
    30) ANDROID_VER_NAME="Android 11" ;;
    31) ANDROID_VER_NAME="Android 12" ;;
    32) ANDROID_VER_NAME="Android 12L" ;;
    33) ANDROID_VER_NAME="Android 13" ;;
    34) ANDROID_VER_NAME="Android 14" ;;
    *)  ANDROID_VER_NAME="Android $ANDROID_VERSION" ;;
esac

logI "检测到系统: $ANDROID_VER_NAME (SDK $ANDROID_VERSION)"

# ── GNSS 模块配置 ──────────────────────────────────────────

# GNSS 模块型号 (影响波特率和协议解析)
# 支持: UN982 | UM621A | GENERIC
GNSS_MODULE="UN982"

# USB 串口设备路径（连接后执行 ls -la /dev/ttyACM* /dev/ttyUSB* 确认）
USB_GPS_DEV="/dev/ttyACM0"
USB_GPS_DEV_FALLBACK="/dev/ttyUSB0"

# 波特率（不同模块默认不同）
#   UN982 / UM621A: 460800
#   Quectel GNSS: 115200
#   传统模块: 9600
BAUD_RATE=460800

# ── NMEA 协议配置 ─────────────────────────────────────────

# NMEA 语句过滤（逗号分隔，留空则接受全部）
# UN982/UM621A 多星座模块请用 GN 前缀语句
NMEA_FILTER="GNGGA,GNRMC,GNGSA,GNGSV,GNGLL,GNVTG,GST,PQGLL,PQGSA,PQGSV"

# 校验和验证（建议开启）
CHECKSUM_VALIDATE="true"

# 是否等待有效定位后才注入（推荐开启）
WAIT_FOR_FIX="true"

# 等待时间（秒），首次 TTFF 约 30-90 秒
WARM_UP_SECONDS=60

# ── Android GPS 注入目标 ──────────────────────────────────

# GPS 套接字路径
GPS_SOCKET="/dev/socket/gps"
GPS_SOCKET_ALT="/dev/socket/location/gps"
GPS_SOCKET_ALT2="/dev/socket/location/gps_bridge"

# ── 驱动配置 ──────────────────────────────────────────────

# 自动加载的驱动列表（按优先级）
DRIVER_ORDER="ch343 ch340 cp210x ftdi_sio pl2303 cdc_acm"

# 内核模块搜索路径
KMOD_PATHS="/system/lib/modules /lib/modules /vendor/lib/modules"

# USB 设备白名单（VendorID:ProductID, 逗号分隔）
USB_WHITELIST="1a86:55d4,1a86:7523,10c4:ea60,0403:6001,0403:6015,067b:2303,0x1d6b:0104"

# ── 日志配置 ──────────────────────────────────────────────

LOG_LEVEL="INFO"   # ERROR | WARN | INFO | DEBUG | VERBOSE
LOG_FILE="/data/local/tmp/usb_gps/bridge.log"
PID_FILE="/data/local/tmp/usb_gps/pid"
DRIVER_PID_FILE="/data/local/tmp/usb_gps/driver_pid"

# ── 调试开关 ─────────────────────────────────────────────

DEBUG="false"
FOREGROUND="false"

# ═══════════════════════════════════════════════════════════
#  ★ 以下内容通常无需修改
# ═══════════════════════════════════════════════════════════

# ── Android 版本相关配置 ──────────────────────────────────

# 根据系统版本自动选择启动延迟（低版本系统服务启动更慢）
case "$ANDROID_VERSION" in
    29|30) BOOT_DELAY=25 ;;   # Android 10/11 需要更长等待
    31|32) BOOT_DELAY=20 ;;   # Android 12
    *)     BOOT_DELAY=15 ;;   # Android 13+
esac

# USB VID/PID 表（用于自动识别）
USB_CH343="1a86:55d3,1a86:55d4"     # CH343P/Q
USB_CH340="1a86:7523,1a86:5523"     # CH340G/CH340C
USB_CP210="10c4:ea60,10c4:ea71"     # CP2102/CP2104/CP2105
USB_FTDI="0403:6001,0403:6010,0403:6015,0403:7c90"  # FT232/FT231X/FT2232
USB_PL2303="067b:2303,067b:25a3"    # PL2303HX/PL2303GC
USB_CDC="0x1d6b:0104,0x1d6b:0204"   # USB CDC-ACM

# USB 驱动名称映射
declare -A USB_DRIVER_MAP
USB_DRIVER_MAP["1a86:55d3"]="ch343"
USB_DRIVER_MAP["1a86:55d4"]="ch343"
USB_DRIVER_MAP["1a86:7523"]="ch340"
USB_DRIVER_MAP["10c4:ea60"]="cp210x"
USB_DRIVER_MAP["10c4:ea71"]="cp210x"
USB_DRIVER_MAP["0403:6001"]="ftdi_sio"
USB_DRIVER_MAP["0403:6015"]="ftdi_sio"
USB_DRIVER_MAP["067b:2303"]="pl2303"

# GNSS 模块默认配置
declare -A GNSS_CONFIG
case "$GNSS_MODULE" in
    "UN982")
        BAUD_RATE=${BAUD_RATE:-460800}
        NMEA_FILTER=${NMEA_FILTER:-"GNGGA,GNRMC,GNGSA,GNGSV,GNGLL,GNVTG,GLGSV,BGGSV,GAGSV"}
        ;;
    "UM621A")
        BAUD_RATE=${BAUD_RATE:-460800}
        NMEA_FILTER=${NMEA_FILTER:-"GNGGA,GNRMC,GNGSA,GNGSV,GNGLL,GNVTG,GST,GLGSV,BGGSV,GAGSV"}
        ;;
    "GENERIC"|*)
        BAUD_RATE=${BAUD_RATE:-9600}
        NMEA_FILTER=${NMEA_FILTER:-"GPGGA,GPRMC,GPGSA,GPGSV,GPGLL,GPVTG"}
        ;;
esac

# ── 工具函数 ──────────────────────────────────────────────

log_tag="usb_gps_switcher"

log() {
    local level="$1"; shift
    local msg="$*"
    local ts=$(date +"%m-%d %H:%M:%S")
    
    # 优先级过滤
    case "$LOG_LEVEL" in
        ERROR)   [ "$level" != "E" ] && return ;;
        WARN)    [ "$level" = "V" ] && return ;;
        INFO)    [ "$level" = "D" ] && [ "$level" = "V" ] && return ;;
        DEBUG)   [ "$level" = "V" ] && return ;;
        VERBOSE) ;;
    esac
    
    echo "[$ts] [$level] $msg"
    log -t "$log_tag" -p "$level" "$msg"
    
    if [ -n "$LOG_FILE" ]; then
        echo "[$ts] [$level] $msg" >> "$LOG_FILE" 2>/dev/null
    fi
}

logE() { log E "$*"; }
logW() { log W "$*"; }
logI() { log I "$*"; }
logD() { log D "$*"; }
logV() { log V "$*"; }

# ── 设备检测 ──────────────────────────────────────────────

find_gnss_device() {
    # 优先按模块型号查找
    local devs="$USB_GPS_DEV $USB_GPS_DEV_FALLBACK"
    
    # 按顺序尝试所有可能设备
    for dev in $devs \
               /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2 \
               /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3 \
               /dev/tty.usbmodem*; do
        if [ -c "$dev" ]; then
            logI "发现串口设备: $dev"
            echo "$dev"
            return 0
        fi
    done
    
    logW "未检测到 USB 串口设备"
    return 1
}

get_usb_vidpid() {
    local dev="$1"
    local vid="" pid=""
    
    if [ -d "/sys/class/tty/$dev/device" ]; then
        vid=$(cat /sys/class/tty/$dev/device/idVendor 2>/dev/null | tr -d ' ')
        pid=$(cat /sys/class/tty/$dev/device/idProduct 2>/dev/null | tr -d ' ')
    fi
    
    [ -n "$vid" ] && echo "${vid}:${pid}" || echo "unknown"
}

# ── NMEA 工具 ──────────────────────────────────────────────

is_valid_nmea() {
    local line="$1"
    
    # 必须以 $ 开头
    [ "${line:0:1}" != "\$" ] && return 1
    
    # 必须包含校验和标记 *
    echo "$line" | grep -q '\*' || return 1
    
    # 长度检查
    [ ${#line} -lt 10 ] && return 1
    
    if [ "$CHECKSUM_VALIDATE" = "true" ]; then
        # 校验和验证
        local data=$(echo "$line" | sed 's/^\$//' | cut -d'*' -f1)
        local recv_cs=$(echo "$line" | sed 's/.*\*//' | tr -d '\r\n')
        
        # 计算 XOR 校验和
        local calc_cs
        calc_cs=$(printf '%02X' $(echo -n "$data" | od -An -tx1 | tr ' ' '\n' | paste -sd '^' | bc 2>/dev/null) )
        
        # 简化的校验和
        local xor=0
        for byte in $(echo -n "$data" | od -An -tx1 | tr ' ' '\n' | grep -v '^$'); do
            xor=$((xor ^ 16#$byte))
        done
        local calc=$(printf '%02X' $xor)
        
        [ "${recv_cs,,}" != "${calc,,}" ] && logW "NMEA 校验和错误: 期望 $calc, 收到 $recv_cs"
        # 注意：校验和不匹配不一定是错误（NMEA 可能自带校验和字段但内容是乱码）
    fi
    
    return 0
}

pass_nmea_filter() {
    local sentence="$1"
    [ -z "$NMEA_FILTER" ] && return 0
    
    # 提取 NMEA 语句类型 (如 GNGGA, GPRMC)
    local talker=$(echo "$sentence" | cut -d',' -f1 | cut -c2-5)
    local type=$(echo "$sentence" | cut -d',' -f1 | cut -c6-)
    local combined="$talker$type"
    
    for allowed in $(echo "$NMEA_FILTER" | tr ',' ' '); do
        [ "$combined" = "$allowed" ] && return 0
    done
    
    return 1
}

# ── 驱动工具 ──────────────────────────────────────────────

load_driver_if_needed() {
    local vidpid="$1"
    local driver="${USB_DRIVER_MAP[$vidpid]}"
    
    if [ -z "$driver" ]; then
        # 尝试 CDC-ACM 通用驱动
        driver="cdc_acm"
    fi
    
    # 检查是否已加载
    if lsmod | grep -q "^$driver "; then
        logI "驱动 $driver 已加载"
        return 0
    fi
    
    # 尝试 insmod
    for kmod in "$KODIR/${driver}.ko" "$KODIR/${driver}_tty.ko"; do
        if [ -f "$kmod" ]; then
            logI "加载驱动: insmod $kmod"
            insmod "$kmod" 2>/dev/null && return 0
        fi
    done
    
    # 尝试 modprobe
    logI "尝试 modprobe $driver"
    modprobe "$driver" 2>/dev/null && return 0
    
    logW "无法加载驱动: $driver"
    return 1
}

# ── 权限修复 ──────────────────────────────────────────────

fix_permissions() {
    local dev="$1"
    chmod 666 "$dev" 2>/dev/null
    chown root:root "$dev" 2>/dev/null
    
    # 尝试 SELinux 上下文修复
    chcon u:object_r:tty_device:s0 "$dev" 2>/dev/null
    
    logI "已设置 $dev 权限: 666"
}

# ── 内置 GNSS HAL 控制 ─────────────────────────────────────
# ============================================================
# GNSS HAL 版本对应关系：
#   Android 10-11: GNSS 1.0 / 1.1 (HIDL)
#   Android 12-13: GNSS 2.0 / 2.1 (HIDL)
#   Android 14+:   GNSS 3.0 (AIDL)
# ============================================================

stop_internal_gnss() {
    logI "停止内置 GNSS HAL..."
    logI "Android 版本: $ANDROID_VER_NAME (SDK $ANDROID_VERSION)"
    
    # ── 1. 停止标准 HIDL/AIDL HAL 服务 ─────────────────────
    # 根据系统版本优先停止对应版本的服务
    
    # GNSS 3.0 (Android 14+, AIDL)
    for svc in \
        android.hardware.gnss-aidl-service \
        android.hardware.gnss@3.0-service \
        android.hardware.gnss@3.0-qti \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
        logD "停止服务: $svc"
    done
    
    # GNSS 2.1 (Android 12-13, HIDL)
    for svc in \
        android.hardware.gnss@2.1-service \
        android.hardware.gnss@2.1-service-qti \
        android.hardware.gnss@2.1-impl \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
        logD "停止服务: $svc"
    done
    
    # GNSS 2.0 (Android 10-12, HIDL)
    for svc in \
        android.hardware.gnss@2.0-service \
        android.hardware.gnss@2.0-impl \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
        logD "停止服务: $svc"
    done
    
    # GNSS 1.1 (Android 10-11, HIDL)
    for svc in \
        android.hardware.gnss@1.1-service \
        android.hardware.gnss@1.1-impl \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
        logD "停止服务: $svc"
    done
    
    # GNSS 1.0 (Android 10, HIDL)
    for svc in \
        android.hardware.gnss@1.0-service \
        android.hardware.gnss@1.0-impl \
        android.hardware.gnss-service \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
        logD "停止服务: $svc"
    done
    
    # ── 2. 停止厂商定制 GNSS 服务 ─────────────────────────
    
    # 高通 (Qualcomm)
    for svc in \
        vendor.qti.gnss-service \
        vendor.qti.hardware.gnss@1.0-service \
        vendor.qti.hardware.gnss@2.0-service \
        vendor.qti.hardware.gnss@2.1-service \
        qcom_gps \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # 联发科 (MediaTek)
    for svc in \
        mtk_agpsd \
        mtk_gps_daemon \
        mnld \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # 展锐 (UNISOC/UIS7870)
    for svc in \
        gnss_service_unisoc \
        sprd_gps \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # 华为/海思
    for svc in \
        android.hardware.gnss@1.0-service.hisi \
        hw_gps_service \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # 三星 Exynos
    for svc in \
        android.hardware.gnss@2.0-service.samsung \
        gpsd \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # 通用/其他
    for svc in \
        hal_gnss \
        gnss_hal \
        gnss_service \
        hal_gps \
        gps_hal \
        gpsd \
        location \
        location-daemon \
        android.hardware.gps@1.0-service \
        android.hardware.gps@2.0-service \
        ; do
        stop "$svc" 2>/dev/null
        setprop ctl.stop "$svc" 2>/dev/null
    done
    
    # ── 3. 强制杀掉残留进程 ───────────────────────────────
    for proc in \
        android.hardware.gnss \
        gnss_service \
        gpsd \
        hal_gps \
        hal_gnss \
        gps_hal \
        mtk_agpsd \
        mnld \
        ; do
        pkill -9 -f "$proc" 2>/dev/null
    done
    
    # ── 4. 设置属性禁用内置 ────────────────────────────────
    # 通用属性
    setprop persist.sys.gnss.mode external 2>/dev/null
    setprop persist.sys.usb.gps.mode external 2>/dev/null
    setprop ro.hardware.gps none 2>/dev/null
    setprop ro.hardware.gnss none 2>/dev/null
    
    # Android 10-11 特定
    setprop vendor.gps.mode external 2>/dev/null
    setprop persist.vendor.gps.mode external 2>/dev/null
    
    # Android 12+ 特定
    setprop persist.vendor.qti.gnss.mode external 2>/dev/null
    
    sleep 1
    logI "内置 GNSS 已停止"
}

start_internal_gnss() {
    logI "启动内置 GNSS HAL..."
    logI "Android 版本: $ANDROID_VER_NAME (SDK $ANDROID_VERSION)"
    
    # ── 1. 恢复属性 ───────────────────────────────────────
    # 通用属性
    setprop persist.sys.gnss.mode auto 2>/dev/null
    setprop persist.sys.usb.gps.mode internal 2>/dev/null
    setprop ro.hardware.gps auto 2>/dev/null
    setprop ro.hardware.gnss auto 2>/dev/null
    
    # Android 10-11 特定
    setprop vendor.gps.mode internal 2>/dev/null
    setprop persist.vendor.gps.mode internal 2>/dev/null
    
    # Android 12+ 特定
    setprop persist.vendor.qti.gnss.mode internal 2>/dev/null
    
    # ── 2. 根据系统版本启动对应 HAL ───────────────────────
    
    # GNSS 1.0 (Android 10)
    if [ "$ANDROID_VERSION" -le 29 ]; then
        for svc in \
            android.hardware.gnss@1.0-service \
            android.hardware.gnss@1.0-impl \
            android.hardware.gnss-service \
            ; do
            start "$svc" 2>/dev/null
            setprop ctl.start "$svc" 2>/dev/null
        done
    fi
    
    # GNSS 1.1 (Android 10-11)
    if [ "$ANDROID_VERSION" -le 30 ]; then
        for svc in \
            android.hardware.gnss@1.1-service \
            android.hardware.gnss@1.1-impl \
            ; do
            start "$svc" 2>/dev/null
            setprop ctl.start "$svc" 2>/dev/null
        done
    fi
    
    # GNSS 2.0 (Android 10-12)
    if [ "$ANDROID_VERSION" -le 31 ]; then
        for svc in \
            android.hardware.gnss@2.0-service \
            android.hardware.gnss@2.0-impl \
            ; do
            start "$svc" 2>/dev/null
            setprop ctl.start "$svc" 2>/dev/null
        done
    fi
    
    # GNSS 2.1 (Android 12-13)
    if [ "$ANDROID_VERSION" -ge 31 ] && [ "$ANDROID_VERSION" -le 33 ]; then
        for svc in \
            android.hardware.gnss@2.1-service \
            android.hardware.gnss@2.1-service-qti \
            android.hardware.gnss@2.1-impl \
            ; do
            start "$svc" 2>/dev/null
            setprop ctl.start "$svc" 2>/dev/null
        done
    fi
    
    # GNSS 3.0 / AIDL (Android 14+)
    if [ "$ANDROID_VERSION" -ge 34 ]; then
        for svc in \
            android.hardware.gnss-aidl-service \
            android.hardware.gnss@3.0-service \
            android.hardware.gnss@3.0-qti \
            ; do
            start "$svc" 2>/dev/null
            setprop ctl.start "$svc" 2>/dev/null
        done
    fi
    
    # ── 3. 启动厂商定制服务 ───────────────────────────────
    
    # 高通
    for svc in \
        vendor.qti.gnss-service \
        vendor.qti.hardware.gnss@1.0-service \
        vendor.qti.hardware.gnss@2.0-service \
        vendor.qti.hardware.gnss@2.1-service \
        ; do
        start "$svc" 2>/dev/null
        setprop ctl.start "$svc" 2>/dev/null
    done
    
    # 联发科
    for svc in mtk_agpsd mtk_gps_daemon mnld; do
        start "$svc" 2>/dev/null
        setprop ctl.start "$svc" 2>/dev/null
    done
    
    # 展锐
    for svc in gnss_service_unisoc sprd_gps; do
        start "$svc" 2>/dev/null
        setprop ctl.start "$svc" 2>/dev/null
    done
    
    # 通用服务
    for svc in hal_gnss gnss_service gpsd; do
        start "$svc" 2>/dev/null
        setprop ctl.start "$svc" 2>/dev/null
    done
    
    # ── 4. 触发系统重启 HAL ────────────────────────────────
    setprop ctl.restart gnss_service 2>/dev/null
    setprop ctl.restart android.hardware.gnss@1.0-service 2>/dev/null
    setprop ctl.restart android.hardware.gnss@2.0-service 2>/dev/null
    setprop ctl.restart android.hardware.gnss@2.1-service 2>/dev/null
    
    sleep 2
    logI "内置 GNSS 已启动"
}

# ── 进程管理 ──────────────────────────────────────────────

save_pid() {
    echo "$1" > "$PID_FILE"
}

clear_pid() {
    rm -f "$PID_FILE"
}

is_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat $PID_FILE)" 2>/dev/null
}

# ── 波特率自动检测 ────────────────────────────────────────

detect_baud_rate() {
    local dev="$1"
    local baud_rates="115200 9600 4800 19200 38400 57600"
    
    for baud in $baud_rates; do
        # 设置波特率
        stty -F "$dev" "$baud" 2>/dev/null
        
        # 尝试读取 1 秒
        data=$(timeout 1 cat "$dev" 2>/dev/null | head -1)
        
        # 检查是否是 NMEA 数据
        if echo "$data" | grep -qE '^\$[PG][A-Z]{2}[A-Z]{2}'; then
            echo "$baud"
            return 0
        fi
    done
    
    return 1
}

# ── 串口 NMEA 读取（单次） ────────────────────────────────

read_nmea_once() {
    local dev="$1"
    local timeout_sec="${2:-3}"
    
    timeout "$timeout_sec" cat "$dev" 2>/dev/null | head -5
}

# ── GPS 信号质量评估 ──────────────────────────────────────

check_gps_signal() {
    # 读取最新 GGA 语句获取信号质量
    localgga=$(logcat -d -s "usb_gps_switcher:V" 2>/dev/null | \
                grep '$GNGGA' | tail -1)
    
    if [ -n "$gga" ]; then
        # GGA 格式: $GNGGA,time,lat,NS,lon,EW,quality,nsat,hdop,alt,MSL,...
        # quality: 0=无效, 1=GPS, 2=DGPS, 4=RTK, 5=Float RTK
        quality=$(echo "$gga" | cut -d',' -f7)
        nsat=$(echo "$gga" | cut -d',' -f8)
        
        case "$quality" in
            1) echo "GPS (SPS)  卫星:$nsat" ;;
            2) echo "DGPS      卫星:$nsat" ;;
            4) echo "RTK Fixed 卫星:$nsat" ;;
            5) echo "RTK Float 卫星:$nsat" ;;
            *) echo "无定位    卫星:$nsat" ;;
        esac
    else
        echo "无 GGA 数据"
    fi
}

# ── GNSS 服务诊断 (帮助排查内置GPS无法停止的问题) ────────

diagnose_gnss_services() {
    logI "========== GNSS 服务诊断 =========="
    logI "Android 版本: $ANDROID_VER_NAME (SDK $ANDROID_VERSION)"
    logI ""
    
    logI "【正在运行的 GNSS 相关进程】"
    ps -A 2>/dev/null | grep -iE "gnss|gps|hal|location" | while read line; do
        logI "  $line"
    done
    
    logI ""
    logI "【GNSS 相关属性】"
    for prop in \
        ro.hardware.gps \
        ro.hardware.gnss \
        persist.sys.gnss.mode \
        persist.sys.usb.gps.mode \
        vendor.gps.mode \
        ; do
        val=$(getprop "$prop" 2>/dev/null)
        [ -n "$val" ] && logI "  $prop = $val"
    done
    
    logI ""
    logI "【GPS 套接字】"
    for sock in \
        /dev/socket/gps \
        /dev/socket/location/gps \
        /dev/socket/location/gps_bridge \
        ; do
        if [ -S "$sock" ]; then
            logI "  ✅ $sock (存在)"
            ls -la "$sock" 2>/dev/null | while read line; do
                logI "     $line"
            done
        else
            logI "  ❌ $sock (不存在)"
        fi
    done
    
    logI ""
    logI "【init 启动的 GNSS 服务】"
    getprop | grep -iE "gnss|gps" 2>/dev/null | while read line; do
        logI "  $line"
    done
    
    logI "===================================="
}
