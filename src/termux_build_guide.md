# Termux 编译指南 - USB GPS Bridge v2.1

## 在车机上（通过 Termux）编译步骤

### 1. 安装编译工具
```bash
pkg update
pkg install git clang make
```

### 2. 拉取仓库
```bash
cd /sdcard  # 或你解压 zip 的目录
cd usb-gps-switcher/src
```

### 3. 编译
```bash
chmod +x build.sh
./build.sh
```

脚本会自动检测 NDK、API 版本并编译。

或者手动：
```bash
clang --target=aarch64-linux-android21 -O2 -Wall -static -o usbgps usbgps.c
```

### 4. 替换模块中的二进制
```bash
cp usbgps ../system/vendor/bin/usbgps
chmod 755 ../system/vendor/bin/usbgps
```

### 5. 重新打包并刷入 Magisk
```bash
cd ..
zip -r usb_gps_switcher_v2.1.zip system/
# 传到电脑，通过 Magisk App 安装
```

## 源码功能特性 (usbgps.c)

### 自动检测
- **USB 设备扫描**：遍历 `/dev/ttyUSB*`、`/dev/ttyACM*`
- **模块类型识别**：通过 USB VID/PID 匹配 20+ 已知 GPS 模块
- **波特率自动检测**：自动测试 9600~921600，自动验证 NMEA 数据

### 支持的模块
| 模块 | VID:PID | 默认波特率 |
|------|---------|-----------|
| WCH CH343 | 1a86:55d4 | 460800 |
| WCH CH340 | 1a86:7523 | 115200 |
| CP210x | 10c4:ea60 | 115200 |
| FTDI | 0403:6001 | 115200 |
| PL2303 | 067b:2303 | 115200 |
| UM982 | 2e88:fff1 | 460800 |
| UM621A | 2e88:fff2 | 460800 |
| u-blox ZED-F9P | 1546:u02 | 460800 |
| u-blox NEO-M9N | 1546:uta | 460800 |

### 命令行参数
- `-d` 调试模式（详细日志）
- `-b <rate>` 强制波特率
- `-p <port>` 强制串口路径
- `-s <socket>` 强制 GPS 套接字路径
- `-h` 帮助信息

### 输出示例
```
USB GPS Bridge v2.1 - Termux Build
[usbgps] GPS Module: WCH CH343 @ /dev/ttyUSB0
[usbgps] Baud rate auto-detection starting for /dev/ttyUSB0
[baud] Detected module: WCH CH343, trying default baud 460800
[baud] ✓ Baud 460800 has valid NMEA data
[baud] Detected baud rate: 460800
[usbgps] Bridge started, forwarding NMEA data...
```
