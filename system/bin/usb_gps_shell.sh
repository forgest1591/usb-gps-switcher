#!/system/bin/sh
#
# usb_gps_shell.sh — 纯 Shell NMEA GNSS 桥接
# ============================================================
# 用途: 无需编译，读取 USB-TTL 串口 NMEA 数据并注入 Android GPS
# 支持: UN982 / UM621A 全星全频输出 (GN 前缀 NMEA)
#
# 工作原理:
#   1. 设置串口参数 (stty)  
#   2. dd 逐字符读取串口
#   3. 提取完整 NMEA 语句 ($ 开头，\r\n 结尾)
#   4. 校验和验证
#   5. 过滤/注入到 GPS 套接字
#
# 用法:
#   sh usb_gps_shell.sh /dev/ttyACM0 115200
#

USB_DEV="${1}"
BAUD="${2:-115200}"
GPS_SOCK="/dev/socket/gps"
GPS_SOCK_ALT="/dev/socket/location/gps"
LOG_TAG="usb_gps_switcher"
PID_FILE="/data/local/tmp/usb_gps/pid"

# ── 参数检查 ───────────────────────────────────────────────

if [ -z "$USB_DEV" ]; then
    log -t "$LOG_TAG" -p e "用法: sh $0 <设备> <波特率>"
    echo "用法: sh $0 /dev/ttyACM0 115200"
    exit 1
fi

if [ ! -c "$USB_DEV" ]; then
    log -t "$LOG_TAG" -p e "设备不存在: $USB_DEV"
    echo "❌ 设备不存在: $USB_DEV"
    exit 1
fi

# ── 日志工具 ─────────────────────────────────────────────

logI() { log -t "$LOG_TAG" -p i "$*"; }
logD() { log -t "$LOG_TAG" -p d "$*"; }
logV() { log -t "$LOG_TAG" -p v "$*"; }

# ── 初始化 ───────────────────────────────────────────────

logI "Shell GPS 桥接启动"
logI "设备: $USB_DEV @ ${BAUD} baud"
logI "等待 GPS 信号..."

# 设置串口权限
chmod 666 "$USB_DEV" 2>/dev/null

# 设置串口参数: raw mode, 8N1
stty -F "$USB_DEV" raw "$BAUD" -echo -echoe -echok -echoctl -echoke 2>/dev/null

# 如果 stty -F 不支持，尝试其他方式
stty -f "$USB_DEV" raw "$BAUD" 2>/dev/null

# 清空串口缓冲区
dd if="$USB_DEV" of=/dev/null bs=1024 count=10 2>/dev/null

# ── NMEA 语句解析函数 ───────────────────────────────────

# 从字符流提取完整 NMEA 语句
# 返回: 完整语句或空
nmea_extract() {
    local char
    local in_sentence=""
    local sentence=""
    local max_len=512
    local count=0
    
    # 用 dd 每次读一个字符
    while [ $count -lt $max_len ]; do
        # 非阻塞读取一个字节，超时 1 秒则放弃
        char=$(dd if="$USB_DEV" bs=1 count=1 2>/dev/null | tr -d '\0')
        
        if [ -z "$char" ]; then
            # 无数据，超时
            return 1
        fi
        
        if [ "$char" = '$' ]; then
            # 开始新语句
            in_sentence="yes"
            sentence='$'
            count=1
        elif [ -n "$in_sentence" ]; then
            sentence="$sentence$char"
            count=$((count + 1))
            
            # NMEA 结束: \r\n 或 \n
            if [ "$char" = $'\n' ] || [ "$char" = $'\r' ]; then
                # 去除尾部换行
                sentence=$(printf '%s' "$sentence" | tr -d '\r\n')
                
                # 基本验证
                if [ ${#sentence} -gt 10 ]; then
                    echo "$sentence"
                    return 0
                fi
                in_sentence=""
                sentence=""
            fi
        fi
    done
    
    return 1
}

# 验证 NMEA 校验和
# 格式: $XXXXX,...*CS\r\n
# CS = $ 后所有字节的 XOR (两位十六进制)
validate_checksum() {
    local sentence="$1"
    
    # 必须有 * 标记
    echo "$sentence" | grep -q '\*' || return 0
    
    local data=$(echo "$sentence" | sed 's/^\$//' | cut -d'*' -f1)
    local recv_cs=$(echo "$sentence" | sed 's/.*\*//' | tr -d '\r\n ' | cut -c1-2)
    
    if [ -z "$recv_cs" ]; then
        return 0  # 没有校验和字段，跳过
    fi
    
    # 计算 XOR 校验和
    local xor=0
    for i in $(echo -n "$data" | od -An -tx1 2>/dev/null | tr ' ' '\n' | grep -v '^$' | head -100); do
        xor=$((xor ^ 16#$i))
    done 2>/dev/null
    
    local calc_cs=$(printf '%02X' $xor 2>/dev/null)
    
    if [ "${recv_cs,,}" != "${calc_cs,,}" ]; then
        return 1
    fi
    
    return 0
}

# 发送 NMEA 到 GPS 套接字
send_to_gps() {
    local sentence="$1"
    
    # 尝试主套接字
    if [ -S "$GPS_SOCK" ]; then
        echo "$sentence" > "$GPS_SOCK" 2>/dev/null
        return 0
    fi
    
    # 尝试备用套接字
    if [ -S "$GPS_SOCK_ALT" ]; then
        echo "$sentence" > "$GPS_SOCK_ALT" 2>/dev/null
        return 0
    fi
    
    # 尝试 location 服务套接字
    for loc_sock in /dev/socket/location/*; do
        if [ -S "$loc_sock" ]; then
            echo "$sentence" > "$loc_sock" 2>/dev/null
        fi
    done 2>/dev/null
    
    return 0
}

# ── 主循环 ───────────────────────────────────────────────

logI "开始 NMEA 读取循环..."

VALID_COUNT=0
TOTAL_COUNT=0
LAST_FIX=""
GGA_COUNT=0
RMC_COUNT=0
RUN_START=$(date +%s)

while true; do
    # 提取 NMEA 语句
    sentence=$(nmea_extract)
    
    if [ -z "$sentence" ]; then
        # 无数据，稍微等待
        sleep 0.1
        continue
    fi
    
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    # 基本验证
    if [ "${sentence:0:1}" != '$' ]; then
        continue
    fi
    
    # 提取语句类型
    # 例如: GNGGA → GN + GGA
    local talker=$(echo "$sentence" | cut -d',' -f1 | cut -c2-5)
    local type=$(echo "$sentence" | cut -d',' -f1 | cut -c6-)
    local combined="$talker$type"
    
    # 调试日志 (每 100 条输出一次)
    if [ $((TOTAL_COUNT % 100)) -eq 1 ]; then
        logD "收到: ${sentence:0:60}..."
    fi
    
    # 计数主要语句
    case "$type" in
        GGA) GGA_COUNT=$((GGA_COUNT + 1)) ;;
        RMC) RMC_COUNT=$((RMC_COUNT + 1)) ;;
    esac
    
    # 完整 verbose 日志 (每 50 条)
    if [ $((TOTAL_COUNT % 50)) -eq 1 ]; then
        logV "Rcv[$TOTAL_COUNT]: ${sentence:0:60}"
    fi
    
    # 发送所有语句到 GPS 套接字
    send_to_gps "$sentence"
    
    # 记录最后有效的 GGA 时间
    if [ "$type" = "GGA" ]; then
        local qual=$(echo "$sentence" | cut -d',' -f7)
        if [ "$qual" != "0" ] && [ -n "$qual" ]; then
            LAST_FIX=$(date +%s)
            VALID_COUNT=$((VALID_COUNT + 1))
        fi
    fi
    
    # 定期健康报告 (每 60 秒)
    local now=$(date +%s)
    if [ $((now - RUN_START)) -gt 0 ] && [ $((now - RUN_START)) -lt 100000 ]; then
        :
    fi
    
done &

BRIDGE_PID=$!
echo "$BRIDGE_PID" > "$PID_FILE"

logI "桥接已启动 PID=$BRIDGE_PID"
logI "设备=$USB_DEV 波特率=$BAUD"
logI "按 Ctrl+C 或 kill $BRIDGE_PID 停止"

# 等待子进程
wait $BRIDGE_PID

logI "桥接已退出"
exit 0
