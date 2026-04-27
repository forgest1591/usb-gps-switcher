# USB GPS Switcher — Android 车机通用

> 支持 **UN982 / UM621A** 全星全频 GNSS 模块，集成主流 USB-TTL 驱动
> **兼容 Android 10 / 11 / 12 / 13 / 14**

## 平台

- **车机**: UIS7870 / MTK / Qualcomm / 其他 Android 车机
- **系统**: Android 10 ~ 14
- **内核**: Linux 4.4+ (4.9 / 4.14 / 4.19 / 5.4 / 5.10)
- **Root**: Magisk v20+ / KernelSU
- **架构**: ARM64 / ARM32

---

## Android 版本兼容性

| Android 版本 | SDK | GNSS HAL | GPS 套接字 | 状态 |
|-------------|-----|----------|-----------|------|
| Android 10 | 29 | GNSS 1.0 / 1.1 | `/dev/socket/gps` | ✅ 已适配 |
| Android 11 | 30 | GNSS 1.1 / 2.0 | `/dev/socket/gps` | ✅ 已适配 |
| Android 12 | 31 | GNSS 2.0 / 2.1 | `/dev/socket/location/gps` | ✅ 已适配 |
| Android 13 | 33 | GNSS 2.1 | `/dev/socket/location/gps` | ✅ 已测试 |
| Android 14 | 34 | GNSS 3.0 (AIDL) | `/dev/socket/location/gps` | ✅ 已适配 |

### GNSS HAL 版本说明

| HAL 版本 | Android | 接口 | 服务名 |
|---------|---------|------|--------|
| **GNSS 1.0** | 10 | HIDL | `android.hardware.gnss@1.0-service` |
| **GNSS 1.1** | 10-11 | HIDL | `android.hardware.gnss@1.1-service` |
| **GNSS 2.0** | 10-12 | HIDL | `android.hardware.gnss@2.0-service` |
| **GNSS 2.1** | 12-13 | HIDL | `android.hardware.gnss@2.1-service` |
| **GNSS 3.0** | 14+ | AIDL | `android.hardware.gnss-aidl-service` |

### 厂商定制 GNSS 服务

| 厂商 | 服务名 |
|------|--------|
| 高通 (Qualcomm) | `vendor.qti.gnss-service`, `vendor.qti.hardware.gnss@*.service` |
| 联发科 (MediaTek) | `mtk_agpsd`, `mnld` |
| 展锐 (UNISOC) | `gnss_service_unisoc`, `sprd_gps` |
| 华为 (HiSilicon) | `android.hardware.gnss@1.0-service.hisi` |
| 三星 (Exynos) | `android.hardware.gnss@2.0-service.samsung` |

**注意**：不同车机厂商可能有定制化的 GNSS 服务名，如果内置 GPS 无法停止，请查看实际服务名：
```bash
# 查看正在运行的 GNSS 相关服务
ps -A | grep -iE "gnss|gps|hal|location"

# 使用诊断模式
sh /data/adb/usb_gps_switcher/status.sh --diagnose
```

---

## 模块功能

### 模块启用时（推荐工作模式）
- ✅ 自动加载 USB-TTL 驱动 (CH343 / CP210x / FTDI / PL2303)
- ✅ 创建串口设备节点
- ✅ 停止内置 GNSS HAL
- ✅ 启动外置 GNSS 桥接服务
- ✅ NMEA 数据注入 Android GPS 套接字

### 模块禁用时（恢复原厂）
- ⛔ 停止外置桥接进程
- ⛔ 卸载驱动模块
- ⛔ 恢复内置 GNSS HAL

---

## 支持的 GNSS 模块

| 模块型号 | 卫星系统 | 备注 |
|---------|---------|------|
| **UN982** | GPS L1/L5 + GLONASS + BeiDou + Galileo | 全星座 |
| **UM621A** | GPS + GLONASS + BeiDou + Galileo + QZSS | 全频 |
| 通用 NMEA | GPS L1 | 兼容 |

## 支持的 USB-TTL 芯片

| 芯片 | Vendor ID | Product ID | 驱动 |
|------|-----------|------------|------|
| CH343 | 1a86 | 55d3/55d4 | ch343.ko |
| CH340 | 1a86 | 7523 | ch341.ko |
| CP2102/4 | 10c4 | ea60 | cp210x.ko |
| FTDI FT232 | 0403 | 6001 | ftdi_sio.ko |
| PL2303 | 067b | 2303 | pl2303.ko |
| CDC-ACM | 0x1d6b | 0x0104 | cdc_acm.ko |

---

## 安装步骤

### 1. 刷入模块
```bash
# 将 usb_gps_switcher.zip 复制到车机
# Magisk App → 模块 → 从本地安装 → 选择zip
# 重启
```

### 2. 连接 GNSS 模块
```
车机 USB-A/C 口 ←→ UN982/UM621A ←→ GPS天线
```

### 3. 检查识别
```bash
# 查看 USB 设备
lsusb

# 查看串口
ls -la /dev/ttyACM* /dev/ttyUSB*

# 查看驱动
lsmod | grep -E "ch34|ch343|cp210|ftdi|pl230|usb_serial"
```

### 4. 启用外置 GPS
```bash
su
sh /data/adb/usb_gps_switcher/enable.sh
sh /data/adb/usb_gps_switcher/status.sh
```

### 5. 验证
```bash
logcat | grep -iE "gps|nmea|usb_gps"
```

---

## 配置

编辑 `/data/adb/usb_gps_switcher/config.sh`：

```bash
# 主设备路径（连接模块后查看 ls -la /dev/ttyACM*）
USB_GPS_DEV="/dev/ttyACM0"

# 波特率（UN982/UM621A 通常 115200）
BAUD_RATE=115200

# NMEA 语句过滤
NMEA_FILTER="GNGGA,GNRMC,GNGSA,GNGSV,GLGSV,BGGSV,GAGSV,GNGLL,GNVTG"

# 等待定位时间（秒）
WARM_UP=45
```

---

## 常用命令

```bash
# 启用外置 GPS
sh /data/adb/usb_gps_switcher/enable.sh

# 恢复内置 GPS
sh /data/adb/usb_gps_switcher/disable.sh

# 查看状态
sh /data/adb/usb_gps_switcher/status.sh

# 诊断模式（排查内置 GPS 无法停止的问题）
sh /data/adb/usb_gps_switcher/status.sh --diagnose

# 查看实时 NMEA
sh /data/adb/usb_gps_switcher/nmea_watch.sh
```

---

## NMEA 语句说明

GNSS 模块输出的 NMEA 0183 语句：

| 语句 | 内容 | 对 Android 重要性 |
|------|------|-----------------|
| GNGGA | 定位数据 | ⭐⭐⭐ 核心 |
| GNRMC | 推荐定位 | ⭐⭐⭐ 核心 |
| GNGSA | 卫星信息 | ⭐⭐ 精度 |
| GNGSV | 可见卫星 | ⭐ 调试 |
| GNGLL | 地理坐标 | ⭐ |
| GNVTG | 速度航向 | ⭐ |

GN 前缀 = 多星座混合（GLONASS+GPS+NONE）

---

## 故障排查

### 内置 GPS 无法停止

```bash
# 1. 运行诊断
sh /data/adb/usb_gps_switcher/status.sh --diagnose

# 2. 查看实际的 GNSS 服务名
ps -A | grep -iE "gnss|gps|hal|location"

# 3. 手动停止
stop android.hardware.gnss@1.0-service  # 根据实际服务名修改
```

### 串口未创建
```bash
# 检查 USB 是否识别
lsusb

# 手动加载驱动
insmod /data/adb/usb_gps_switcher/k驱动/ch343.ko
ls -la /dev/ttyACM0
```

### 没有 NMEA 数据
```bash
# 检查波特率
stty -F /dev/ttyACM0

# 查看原始数据
cat /dev/ttyACM0 &
# 或
hexdump -C /dev/ttyACM0 | head
```

### Android 没有收到 GPS
```bash
# 检查权限
ls -la /dev/socket/gps

# 查看注入日志
logcat | grep usb_gps
```

---

## 卸载

```bash
# Magisk App → 模块 → USB GPS Switcher → 右下角卸载图标 → 重启
```

---

## 编译原生桥接工具

```bash
# 需要 Android NDK
ndk-build

# 或交叉编译
aarch64-linux-android-gcc -static main.cpp -o system/bin/usb_gps_bridge
```
