#!/system/bin/sh
#
# service.sh — Magisk 模块服务脚本
# ============================================================
# 核心逻辑：
#   - 模块被启用 → auto-start 标记存在 → 启动外置 GPS
#   - 模块被禁用 → auto-start 标记被删除 → 停止外置 GPS
#   - 重启后自动恢复上次状态（持久化）
#
# auto-start 标记由 enable.sh / disable.sh 管理
# 兼容 Android 10 / 11 / 12 / 13 / 14
# ============================================================

MODDIR="/data/adb/usb_gps_switcher"
STATE_FLAG="/data/local/tmp/usb_gps/.external_enabled"
PID_FILE="/data/local/tmp/usb_gps/pid"
LOG_TAG="usb_gps_switcher"

. "$MODDIR/config.sh"

log() {
    log -t "$LOG_TAG" -p i "$*"
}

# ── 延迟启动 (等系统服务就绪) ────────────────────────────
# Android 10/11 需要更长时间等待系统服务完全启动
# BOOT_DELAY 在 config.sh 中根据 Android 版本自动设置

log "service.sh: 等待系统服务就绪 (${BOOT_DELAY}s)..."
sleep $BOOT_DELAY

# ── 检查 auto-start 状态 ────────────────────────────────
if [ -f "$STATE_FLAG" ]; then
    # 模块被启用 → 启动外置 GPS
    log "service.sh: 检测到 auto-start 标记，启动外置 GNSS"
    
    # 停止内置 GNSS
    stop_internal_gnss
    
    # 找到设备
    USB_DEV=$(find_gnss_device)
    if [ -n "$USB_DEV" ]; then
        fix_permissions "$USB_DEV"
        
        # 启动桥接
        if [ -x "$MODDIR/bin/usb_gps_bridge" ]; then
            "$MODDIR/bin/usb_gps_bridge" -d "$USB_DEV" -b "$BAUD_RATE" &
        else
            sh "$MODDIR/bin/usb_gps_shell.sh" "$USB_DEV" "$BAUD_RATE" &
        fi
        
        PID=$!
        echo $PID > "$PID_FILE"
        log "外置 GNSS 桥接已启动 PID=$PID"
    else
        log "未找到 USB GPS 设备，将在下次检测"
    fi
else
    # 模块被禁用（或首次安装未启用）→ 恢复内置
    log "service.sh: 无 auto-start 标记，保持内置 GNSS"
    
    # 确保外置进程已停止
    if [ -f "$PID_FILE" ]; then
        kill $(cat $PID_FILE) 2>/dev/null
        rm -f "$PID_FILE"
    fi
    
    # 确保内置 GNSS 启动
    start_internal_gnss
fi

log "service.sh: 完成"
exit 0
