# Artifact — USB GPS Switcher v3 (2026-04-21)

## 本次变更
用户新增需求：
1. **自动检测**外置 GPS 模块（设备型号 + 波特率自动识别）
2. **波特率改为 460800**（UN982/UM621A 全星全频高波特率）
3. **交叉编译**并集成 Android ARM64 原生二进制桥接工具

## 实现

### 交叉编译
- 编译器: Android NDK `aarch64-linux-android21-clang++` (Windows 路径)
- 编译命令: `-target aarch64-linux-android21 -static -std=c++17 -O2`
- 输出: `system/bin/usb_gps_bridge` — 3.7 MB 静态链接 ARM64 ELF
- 问题: `android-base` 框架头不可用，改用纯 POSIX API；`xor` 变量名冲突；`daemon()` NDK 不支持 → 改用 `fork()` 实现
- 问题: `va_start` 宏冲突 → 改用 `vsnprintf` + `fprintf`

### 自动检测
- `main.cpp`: `auto_detect_device_and_baud()` — 遍历所有候选设备，以所有波特率探测 NMEA 数据
- 波特率优先级: 460800 → 115200 → 57600 → 38400 → 19200 → 9600 → 4800
- USB VID/PID 数据库: UN982, UM621A, CH343P, CH340, CP210x, FTDI, PL2303
- 识别后使用设备默认波特率

### 波特率更新
- 默认波特率从 115200 改为 **460800**
- NMEA 过滤语句增加: GLGSV (GLONASS可见星), BGGSV (BeiDou), GAGSV (Galileo)

### USB 设备数据库
| 设备 | VID:PID | 默认波特率 |
|------|---------|-----------|
| UN982 GNSS | 2c7c:6005 | 460800 |
| UM621A GNSS | 2c7c:0900 | 460800 |
| CH343P | 1a86:55d3/55d4 | 460800 |
| CH340 | 1a86:7523 | 115200 |
| CP210x | 10c4:ea60/ea71 | 115200 |
| FTDI | 0403:6001/6015 | 115200 |
| PL2303 | 067b:2303 | 115200 |

## 输出
- `usb_gps_switcher.zip` — 1.4 MB（含 ARM64 二进制）
- `system/bin/usb_gps_bridge` — 3.7 MB 静态 ARM64 ELF
- `main.cpp` — ~29 KB 源码

## 局限
- 二进制为静态链接（3.7 MB），可进一步 strip 优化大小
- 车机需确认 UIS7870 内核支持 460800 波特率（一般支持）
- SELinux 可能阻止 GPS 套接字写入，需要 permissive 或调整策略
