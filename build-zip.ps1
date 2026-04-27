#!/system/bin/sh
#
# build.sh — 打包 Magisk 模块 zip
# 用法: 在 Android 设备上运行
#   cd /path/to/android13-usb-gps-switcher
#   sh build.sh
#

set -e

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$WORKDIR/usb_gps_switcher.zip"
TMP="/dev/tmp/usb_gps_build"

echo "===== USB GPS Switcher — Magisk 模块打包 ====="
echo "工作目录: $WORKDIR"

# 清理旧文件
rm -rf "$TMP"
rm -f "$OUT"

# 创建临时目录
mkdir -p "$TMP/system/bin"
mkdir -p "$TMP/system/etc"
mkdir -p "$TMP/system/etc/selinux"
mkdir -p "$TMP/system/bin"

echo "- 复制模块文件..."

# module.prop
cp "$WORKDIR/system/module.prop" "$TMP/"

# 主脚本
cp "$WORKDIR/enable.sh"    "$TMP/"
cp "$WORKDIR/disable.sh"   "$TMP/"
cp "$WORKDIR/status.sh"    "$TMP/"
chmod 755 "$TMP/enable.sh" "$TMP/disable.sh" "$TMP/status.sh"

# 配置文件
cp "$WORKDIR/config.sh"    "$TMP/"
chmod 644 "$TMP/config.sh"

# service.sh (Magisk 模块服务脚本)
cp "$WORKDIR/system/service.sh" "$TMP/"
chmod 755 "$TMP/service.sh"

# customize.sh (安装/卸载脚本)
cp "$WORKDIR/system/customize.sh" "$TMP/"
chmod 755 "$TMP/customize.sh"

# system/ 目录内容
cp -r "$WORKDIR/system/system" "$TMP/"

# 二进制文件 (如果有)
if [ -f "$WORKDIR/system/bin/usb_gps_bridge" ]; then
    cp "$WORKDIR/system/bin/usb_gps_bridge" "$TMP/system/bin/"
    chmod 755 "$TMP/system/bin/usb_gps_bridge"
fi

# Shell 桥接 (始终包含，作为后备)
cp "$WORKDIR/system/bin/usb_gps_shell.sh" "$TMP/system/bin/"
chmod 755 "$TMP/system/bin/usb_gps_shell.sh"

# system.prop
if [ -f "$WORKDIR/system/system.prop" ]; then
    cp "$WORKDIR/system/system.prop" "$TMP/system/"
fi

# SELinux 策略 (模块层面)
if [ -f "$WORKDIR/system/system/etc/selinux/usb_gps_switcher.te" ]; then
    mkdir -p "$TMP/system/system_ext/etc/selinux"
    cp "$WORKDIR/system/system/etc/selinux/usb_gps_switcher.te" \
       "$TMP/system/system_ext/etc/selinux/"
fi

# 显示文件列表
echo ""
echo "- 模块内容:"
find "$TMP" -type f | sed "s|$TMP|  |"

# 打包
echo ""
echo "- 打包 zip..."
cd "$TMP"
zip -r "$OUT" . > /dev/null 2>&1
cd "$WORKDIR"

# 清理
rm -rf "$TMP"

# 完成
SIZE=$(du -h "$OUT" | cut -f1)
echo ""
echo "✅ 打包完成!"
echo "   输出文件: $OUT"
echo "   文件大小: $SIZE"
echo ""
echo "安装方法:"
echo "  1. 将 zip 文件复制到车机"
echo "  2. Magisk App → 模块 → 从本地安装"
echo "  3. 重启"
echo ""
echo "刷入后配置:"
echo "  1. 连接 CH343P GPS 模块到车机 USB"
echo "  2. 执行:  sh /data/adb/usb_gps_switcher/enable.sh"
echo "  3. 查看状态: sh /data/adb/usb_gps_switcher/status.sh"
