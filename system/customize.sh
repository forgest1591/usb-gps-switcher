#!/system/bin/sh
#
# customize.sh — Magisk 模块安装钩子
# ============================================================
# Magisk v19+ 在安装/升级/卸载模块时执行此脚本
# 上下文: $MODPATH = /data/adb/usb_gps_switcher
#         $MAGISK_VER = Magisk 版本
#         $KSU = 是否为 KernelSU (yes/no)
# ============================================================

MODPATH="/data/adb/usb_gps_switcher"

# ── 安装时 ────────────────────────────────────────────────
on_install() {
    ui_print "- 正在安装 USB GPS Switcher..."
    
    # 创建运行目录
    mkdir -p /data/local/tmp/usb_gps
    chmod 755 /data/local/tmp/usb_gps
    
    # 创建驱动目录
    mkdir -p "$MODPATH/drivers"
    
    # 设置脚本权限
    chmod 755 "$MODPATH/enable.sh"
    chmod 755 "$MODPATH/disable.sh"
    chmod 755 "$MODPATH/status.sh"
    chmod 755 "$MODPATH/config.sh"
    
    # 二进制和 shell 工具
    if [ -f "$MODPATH/system/bin/usb_gps_bridge" ]; then
        chmod 755 "$MODPATH/system/bin/usb_gps_bridge"
    fi
    chmod 755 "$MODPATH/system/bin/usb_gps_shell.sh"
    chmod 755 "$MODPATH/system/bin/usb_gps_switcher_init.sh"
    
    ui_print "- 权限设置完成"
}

# ── 首次安装完成后（模块已启用状态）───────────────────────
on_installed() {
    ui_print "- USB GPS Switcher 安装完成！"
    ui_print ""
    ui_print "使用说明:"
    ui_print "  1. 连接 GNSS 模块到车机 USB"
    ui_print "  2. 执行: sh $MODPATH/enable.sh"
    ui_print "  3. 查看状态: sh $MODPATH/status.sh"
    ui_print ""
    ui_print "禁用模块 = 恢复内置 GNSS"
    ui_print "启用模块 = 启动外置 GNSS"
}

# ── 升级时（保留用户配置）─────────────────────────────────
on_upgrade() {
    ui_print "- 正在升级 USB GPS Switcher..."
    
    # 保留旧配置
    if [ -f "/data/local/tmp/usb_gps/.external_enabled" ]; then
        ui_print "- 保留外置 GPS 启用状态"
    fi
    
    # 停止旧进程
    if [ -f "/data/local/tmp/usb_gps/pid" ]; then
        kill $(cat /data/local/tmp/usb_gps/pid) 2>/dev/null
        rm -f /data/local/tmp/usb_gps/pid
    fi
}

# ── 卸载时 ────────────────────────────────────────────────
on_uninstall() {
    ui_print "- 正在卸载 USB GPS Switcher..."
    
    # 停止所有桥接进程
    for pid in $(pidof usb_gps_bridge 2>/dev/null) \
               $(pidof usb_gps_shell 2>/dev/null) \
               $(pidof usb_gps_switcher 2>/dev/null); do
        kill "$pid" 2>/dev/null
        ui_print "- 已停止进程 PID=$pid"
    done
    
    # 清理状态文件
    rm -f /data/local/tmp/usb_gps/.external_enabled
    rm -f /data/local/tmp/usb_gps/pid
    
    # 恢复系统属性（让下次启动使用内置 GNSS）
    setprop persist.sys.usb.gps.mode internal 2>/dev/null
    setprop persist.sys.gnss.mode auto 2>/dev/null
    setprop ro.hardware.gps auto 2>/dev/null
    
    ui_print "- 已清理配置"
    ui_print "- 下次重启将恢复内置 GNSS"
}

# ── Magisk 框架调用 ───────────────────────────────────────
# Magisk v19+ 标准钩子
[ -f "/data/adb/magisk/util_functions.sh" ] && . /data/adb/magisk/util_functions.sh

# 检测是安装/升级/卸载
if [ "$1" = "uninstall" ]; then
    on_uninstall
else
    on_install
    on_installed
fi
