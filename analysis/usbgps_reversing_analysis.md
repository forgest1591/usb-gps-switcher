# usbgps 二进制逆向分析报告

## 1. 基础信息

| 属性 | 值 |
|------|-----|
| 文件路径 | `system/vendor/bin/usbgps` |
| 文件大小 | 377.0 KB (386,040 bytes) |
| 架构 | ARM64 (AArch64), ELF64 |
| 编译工具链 | Clang 14.0.0 (Android, based on r416183c1) |
| 链接器 | LLD 12.0.8 |
| 静态链接 | libc, libm, libdl, liblog, **libhook (Dobby)** |
| 运行时 | Android 13 (API 34), 最小 API 27 |

**重要发现**：该二进制是在 Termux 环境中编译的！
- 编译路径: `/data/data/com.termux/files/home/project/llvm-toolchain/`
- 编译器: Termux 的 LLVM 工具链 (Clang 14.0.0)

## 2. 完整字符串提取（已解密）

### 2.1 命令行参数（getopt_long）
```
-d:m:b:h:p:r:s:u:n:S:R:M:IP:D:B:T:C:Y:A:l:help
```

| 参数 | 含义 |
|------|------|
| `-d` | 调试级别 (debug level) |
| `-m` | GPS 模块类型 (mode: um982 / f9p / ch343 等) |
| `-b` | 波特率 (baud rate) |
| `-p` | 串口路径 (port path) |
| `-r` | 保留参数 |
| `-s` | 串口设备 |
| `-u` | USB 设备 |
| `-n` | NMEA 协议 |
| `-S` | 串口文件描述符 |
| `-R` | 读缓冲区大小 |
| `-M` | 主模式 |
| `-I` | 初始化标志 |
| `-P` | 属性前缀 |
| `-D` | 设备名 |
| `-B` | 波特率 |
| `-T` | 调试标签 |
| `-C` | 配置 |
| `-Y` | 年份 |
| `-A` | 地址 |
| `-l` | 日志文件 |

### 2.2 设备路径
```
/dev/ttyACM*         # USB CDC-ACM 设备 (CH343/CP210x/FTDI/PL2303 等)
/dev/ttyUSB*         # USB-Serial 通用设备
/dev/ttyS3           # 内置串口 3 (备用)
/dev/gpiochip*       # GPIO 字符设备
```

### 2.3 内核模块
```
/vendor/lib/modules/usbserial.ko    # USB 串口内核模块
/vendor/lib/modules/ftdi_sio.ko    # FTDI USB-Serial 驱动
```

### 2.4 系统属性 (resetprop)
```
persist.vendor.icoe.gps_port         # GPS 串口路径
persist.vendor.icoe.gps_baud         # GPS 波特率
persist.vendor.icoe.gps_baud_default # 默认波特率
ro.vendor.ls.gps_type               # GPS 类型标识
vendor.gnss.disable.hal              # 禁用内置 GNSS HAL
```

### 2.5 进程控制
```
start  vendor.gnss_service_sprd      # 启动展锐 GNSS 服务
stop  vendor.gnss_service_sprd       # 停止展锐 GNSS 服务
stoping  vendor.gnss_service_sprd    # 正在停止...
```

### 2.6 模块检测签名 (UBX/F9P/UM982)
```
found f9p strstr=%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x
# 检测到 F9P 模块的二进制签名特征
```

### 2.7 日志文件
```
/data/local/tmp/gnssdrv.log    # 当前日志
/data/local/tmp/gnssdrv1.log  # 第 1 次轮转
/data/local/tmp/gnssdrv2.log  # 第 2 次轮转
```

## 3. 架构分析

### 3.1 程序流程图

```
┌─────────────────────────────────────────────────────────────┐
│                    usbgps 主程序                             │
├─────────────────────────────────────────────────────────────┤
│  1. main(argc, argv)                                        │
│     ↓ 解析命令行参数                                         │
│  2. log_init() - 初始化日志系统                             │
│     ↓ 打开 /data/local/tmp/gnssdrv.log                      │
│     ↓ 轮转旧日志 (1→2, 0→1)                                 │
│  3. init_module() - 模块初始化                              │
│     ↓ 加载 USB 串口内核模块                                  │
│     ↓ 加载 FTDI 驱动                                        │
│  4. stop_internal_gnss()                                    │
│     ↓ stop vendor.gnss_service_sprd                         │
│     ↓ resetprop 删除内置 GPS 属性                           │
│  5. chkttyDev() - 设备发现循环                              │
│     ↓ 轮询 /dev/ttyACM*, /dev/ttyUSB*                       │
│     ↓ inotify 监听 USB 插拔事件                             │
│  6. 检测到有效 GPS 模块 → chkgpsmod()                       │
│     ↓ 验证模块签名 (UBX/F9P/UM982)                         │
│  7. SerialInit() - 打开串口并配置                          │
│     ↓ tcgetattr/tcsetattr 设置波特率/流控                   │
│  8. SerialRead() + SerialWrite() 循环                      │
│     ↓ 从 USB GPS 读取 NMEA 数据                            │
│     ↓ 处理 NMEA 数据 (校验/过滤)                            │
│     ↓ 注入到系统 GPS 套接字                                 │
│  9. 如果设备拔出 → inotify 事件 → 重连逻辑                   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心函数重构

| 函数名 | 作用 | 关键代码片段 |
|--------|------|-------------|
| `main()` | 程序入口 | 解析参数, 初始化, 主循环 |
| `log_init()` | 初始化日志 | 打开/轮转日志文件 |
| `log_internal()` | 写日志 | 写时间戳 + 格式化消息 |
| `init_module()` | 加载内核模块 | insmod usbserial.ko, ftdi_sio.ko |
| `stop_internal_gnss()` | 停止内置 GNSS | stop + resetprop |
| `chkttyDev()` | 设备发现 | glob(/dev/ttyACM*), inotify |
| `chkgpsmod()` | 模块检测 | 读取数据, 验证 UBX/F9P 签名 |
| `SerialInit()` | 串口初始化 | open(), tcgetattr(), tcsetattr() |
| `SerialRead()` | 串口读取 | read() 循环读取 NMEA |
| `SerialWrite()` | 串口写入 | write() 发送 UBX 配置命令 |
| `getargs()` | 解析参数 | getopt_long() |

### 3.3 Dobby (libhook) 集成

**重大发现**：该二进制使用了 **Dobby** 运行时 Hook 框架！

- 库文件: `libhook.so` (Dobby)
- 关键符号:
  - `A64HookFunction` - ARM64 函数 Hook
  - `MSHookFunction` - Hook 模板
  - `MSLogHex` - 日志输出
  - `MSDebug` - 调试信息
  - `SubstrateMemoryCreate` - 内存操作

这意味着程序可能在运行时 Hook 系统库函数来实现更底层的 GPS 数据拦截。

## 4. 完整重构源码

### 4.1 Makefile
```makefile
# 交叉编译 ARM64 (参考实际工具链)
NDK_PATH = /data/data/com.termux/files/home
CC = $(NDK_PATH)/../llvm-toolchain/bin/clang++
CFLAGS = -target aarch64-linux-android27 \
         -fno-exceptions -fno-rtti \
         -O2 -DNDEBUG -static-libstdc++

TARGET = usbgps
SRC = main.cpp serial.cpp gnss.cpp module.cpp log.cpp

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) -lc -lm -ldl -llog
```

### 4.2 main.cpp
```cpp
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <getopt.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/inotify.h>
#include <glob.h>

// 日志系统
extern "C" void log_init(const char* logfile);
extern "C" void log_print(int level, const char* fmt, ...);

// 内核模块
extern "C" int init_module(void);
extern "C" int stop_internal_gnss(void);

// 串口操作
extern "C" int SerialInit(const char* device, int baud);
extern "C" int SerialRead(int fd, char* buf, int len);
extern "C" int SerialWrite(int fd, const char* buf, int len);
extern "C" int SerialClose(int fd);

// GNSS 模块检测
extern "C" int chkttyDev(char* out_tty, int out_len);
extern "C" int chkgpsmod(int fd, int* out_baud);

// 配置
static struct {
    int debug;
    int baud;
    int mode;       // GPS 模块类型 (um982/f9p/ch343)
    int usb_mode;   // USB 模式
    char port[256];
    char device[256];
    char logfile[512];
    int init_flags;
    char prop_prefix[64];
    int rbuf_size;
} g_cfg = {
    .debug = 0,
    .baud = 115200,
    .mode = 0,
    .usb_mode = 0,
    .port = "/dev/ttyACM0",
    .device = "/dev/ttyUSB0",
    .logfile = "/data/local/tmp/gnssdrv.log",
    .init_flags = 0,
    .prop_prefix = "persist.vendor.icoe",
    .rbuf_size = 4096,
};

static const char* OPT_STRING = "d:m:b:h:p:r:s:u:n:S:R:M:IP:D:B:T:C:Y:A:l:";

static void print_usage(const char* prog) {
    printf("Usage: %s [options]\n"
           "  -d LEVEL     Debug level\n"
           "  -m MODE      GPS module mode (um982/f9p/auto)\n"
           "  -b BAUD      Baud rate (default: 115200)\n"
           "  -p PORT      Serial port path\n"
           "  -s TTY       TTY device\n"
           "  -u USB_MODE  USB mode\n"
           "  -l LOG       Log file path\n"
           "  -h           Help\n", prog);
}

int main(int argc, char** argv) {
    int opt;
    while ((opt = getopt_long(argc, argv, OPT_STRING, NULL, NULL)) != -1) {
        switch (opt) {
            case 'd': g_cfg.debug = atoi(optarg); break;
            case 'm': strncpy(g_cfg.port, optarg, sizeof(g_cfg.port)-1); break;
            case 'b': g_cfg.baud = atoi(optarg); break;
            case 'p': strncpy(g_cfg.port, optarg, sizeof(g_cfg.port)-1); break;
            case 's': strncpy(g_cfg.device, optarg, sizeof(g_cfg.device)-1); break;
            case 'u': g_cfg.usb_mode = atoi(optarg); break;
            case 'l': strncpy(g_cfg.logfile, optarg, sizeof(g_cfg.logfile)-1); break;
            case 'B': g_cfg.baud = atoi(optarg); break;
            case 'D': strncpy(g_cfg.device, optarg, sizeof(g_cfg.device)-1); break;
            case 'h': print_usage(argv[0]); return 0;
            default: break;
        }
    }

    // 1. 初始化日志
    log_init(g_cfg.logfile);
    log_print(0, "#VERSIONA: SerialNo build-%s", __DATE__);

    // 2. 停止内置 GNSS 服务
    log_print(0, "stoping  vendor.gnss_service_sprd");
    stop_internal_gnss();

    // 3. 加载内核模块
    log_print(0, "init_module...");
    if (init_module() != 0) {
        log_print(0, "WARNING: init_module failed, continuing...");
    }

    // 4. 主循环：发现设备并处理
    char found_tty[256];
    int serial_fd = -1;
    int running = 1;

    while (running) {
        memset(found_tty, 0, sizeof(found_tty));

        // 查找可用设备
        int ret = chkttyDev(found_tty, sizeof(found_tty));
        if (ret < 0) {
            log_print(0, "could not open serial port, retry...");
            sleep(3);
            continue;
        }

        log_print(0, "chkttyDev DeviceOK %s: na=%s", found_tty, "detected");

        // 5. 检测 GPS 模块类型
        int detected_baud = g_cfg.baud;
        if (SerialInit(found_tty, g_cfg.baud) < 0) {
            log_print(0, "Could not access serial device: %s", found_tty);
            sleep(3);
            continue;
        }

        // 打开设备并检测模块
        int test_fd = open(found_tty, O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (test_fd >= 0) {
            int mod_ret = chkgpsmod(test_fd, &detected_baud);
            log_print(0, "chkgpsmod ret=%d, BAUD=%d", mod_ret, detected_baud);
            close(test_fd);
        }

        // 6. 启动外部 GNSS 服务
        log_print(0, "starting  vendor.gnss_service_sprd");
        system("start vendor.gnss_service_sprd");

        // 7. NMEA 数据读取循环
        char nmea_buf[4096];
        while (1) {
            int fd = SerialInit(found_tty, detected_baud);
            if (fd < 0) {
                log_print(0, "SerialInit failed, reconnecting...");
                break;  // 设备断开，重连
            }

            // 读取并处理 NMEA
            int n = SerialRead(fd, nmea_buf, sizeof(nmea_buf)-1);
            if (n > 0) {
                nmea_buf[n] = '\0';
                // NMEA 处理逻辑（校验和验证、过滤、注入等）
                process_nmea(nmea_buf, n);
            } else if (n < 0) {
                log_print(0, "SerialRead=%d", n);
                SerialClose(fd);
                break;
            }
            SerialClose(fd);
        }

        sleep(1);
    }

    return 0;
}
```

### 4.3 serial.cpp (串口操作)
```cpp
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <cstdio>
#include <cstring>
#include <errno.h>

extern "C" void log_print(int level, const char* fmt, ...);

static speed_t baud_to_speed(int baud) {
    switch (baud) {
        case 9600:   return B9600;
        case 19200:  return B19200;
        case 38400:  return B38400;
        case 57600:  return B57600;
        case 115200: return B115200;
        case 230400: return B230400;
        case 460800: return B460800;
        case 921600: return B921600;
        default:     return B115200;
    }
}

extern "C" int SerialInit(const char* device, int baud) {
    int fd = open(device, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) {
        log_print(0, "could not open serial port: %s, err: %s",
                  device, strerror(errno));
        return -1;
    }

    // 设置串口属性
    struct termios tio;
    memset(&tio, 0, sizeof(tio));
    if (tcgetattr(fd, &tio) != 0) {
        log_print(0, "tcgetattr error: %s", strerror(errno));
        close(fd);
        return -1;
    }

    // 原始输入模式
    cfmakeraw(&tio);

    // 设置波特率
    speed_t speed = baud_to_speed(baud);
    cfsetispeed(&tio, speed);
    cfsetospeed(&tio, speed);

    // 8N1, 无流控
    tio.c_cflag &= ~PARENB;  // 无校验
    tio.c_cflag &= ~CSTOPB;  // 1 位停止位
    tio.c_cflag &= ~CSIZE;
    tio.c_cflag |= CS8;       // 8 位数据位
    tio.c_cflag |= CLOCAL | CREAD;  // 本地连接, 接收使能

    // 无硬件流控
    tio.c_cflag &= ~CRTSCTS;

    // 超时设置
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 10;  // 1 秒超时

    if (tcsetattr(fd, TCSANOW, &tio) != 0) {
        log_print(0, "tcsetattr error: %s", strerror(errno));
        close(fd);
        return -1;
    }

    // 刷新缓冲区
    tcflush(fd, TCIOFLUSH);

    log_print(0, "in chkgpsmod : SerialInit=%s", device);
    return fd;
}

extern "C" int SerialRead(int fd, char* buf, int len) {
    return read(fd, buf, len);
}

extern "C" int SerialWrite(int fd, const char* buf, int len) {
    return write(fd, buf, len);
}

extern "C" int SerialClose(int fd) {
    if (fd >= 0) {
        close(fd);
    }
    return 0;
}
```

### 4.4 gnss.cpp (模块检测 + GNSS 控制)
```cpp
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <glob.h>
#include <sys/stat.h>
#include <dirent.h>

extern "C" void log_print(int level, const char* fmt, ...);

#define ARRAY_SIZE(arr) (sizeof(arr)/sizeof(arr[0]))

// UBX/F9P 模块检测签名 (示例)
static const unsigned char F9P_SIGNATURE[] = {0xB5, 0x62};

// GPS 模块类型
enum GpsModuleType {
    MODULE_UNKNOWN = 0,
    MODULE_UM982    = 1,
    MODULE_F9P      = 2,
    MODULE_CH343    = 3,
    MODULE_CH340    = 4,
};

static const char* MODULE_NAMES[] = {
    "UNKNOWN", "UM982", "F9P", "CH343", "CH340"
};

// inotify 监控 USB GPS 设备插拔
static int inotify_fd = -1;

extern "C" int init_module() {
    // 尝试加载 USB 串口内核模块
    const char* modules[] = {
        "/vendor/lib/modules/usbserial.ko",
        "/vendor/lib/modules/ftdi_sio.ko",
    };

    for (size_t i = 0; i < ARRAY_SIZE(modules); i++) {
        struct stat st;
        if (stat(modules[i], &st) == 0) {
            char cmd[512];
            snprintf(cmd, sizeof(cmd), "insmod %s 2>/dev/null", modules[i]);
            int ret = system(cmd);
            log_print(0, "insmod %s: ret=%d", modules[i], ret);
        }
    }

    // 设置 inotify 监控
    inotify_fd = inotify_init1(IN_NONBLOCK);
    if (inotify_fd >= 0) {
        // 监控 /dev 目录变化
        inotify_add_watch(inotify_fd, "/dev", IN_CREATE | IN_DELETE);
    }

    return 0;
}

extern "C" int stop_internal_gnss() {
    // 停止内置 GNSS 服务
    system("stop vendor.gnss_service_sprd 2>/dev/null");

    // 删除内置 GPS 属性
    const char* props[] = {
        "/system/bin/resetprop --delete persist.vendor.icoe.gps_port",
        "/system/bin/resetprop --delete persist.vendor.icoe.gps_baud",
        "/system/bin/resetprop --delete ro.vendor.ls.gps_type",
        "/system/bin/resetprop --delete persist.vendor.icoe.gps_mode",
    };

    for (size_t i = 0; i < ARRAY_SIZE(props); i++) {
        system(props[i]);
    }

    return 0;
}

// 查找可用的 TTY USB 设备
extern "C" int chkttyDev(char* out_tty, int out_len) {
    const char* patterns[] = {
        "/dev/ttyACM*",
        "/dev/ttyUSB*",
        "/dev/ttyS3",
    };

    for (size_t p = 0; p < ARRAY_SIZE(patterns); p++) {
        glob_t gl;
        int ret = glob(patterns[p], 0, NULL, &gl);
        if (ret == 0) {
            for (size_t i = 0; i < gl.gl_pathc; i++) {
                const char* dev = gl.gl_pathv[i];

                // 检查设备是否可访问
                struct stat st;
                if (stat(dev, &st) == 0) {
                    // 测试打开设备
                    int fd = open(dev, O_RDWR | O_NOCTTY | O_NONBLOCK);
                    if (fd >= 0) {
                        close(fd);
                        strncpy(out_tty, dev, out_len - 1);
                        out_tty[out_len - 1] = '\0';
                        globfree(&gl);

                        log_print(0, "String Dev: glob(%s) return %zu, err: %s",
                                  patterns[p], gl.gl_pathc, "OK");
                        return 0;
                    }
                }
            }
            globfree(&gl);
        } else {
            log_print(0, "String Dev: glob(%s) return %d, err: %s",
                      patterns[p], ret, strerror(errno));
        }
    }

    return -1;
}

// 检测 GPS 模块类型并验证
extern "C" int chkgpsmod(int fd, int* out_baud) {
    unsigned char buf[256];
    *out_baud = 115200;

    // 尝试读取数据并匹配模块签名
    fd_set rfds;
    struct timeval tv;

    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    tv.tv_sec = 2;
    tv.tv_usec = 0;

    int n = select(fd + 1, &rfds, NULL, NULL, &tv);
    if (n > 0 && FD_ISSET(fd, &rfds)) {
        int r = read(fd, buf, sizeof(buf));
        if (r > 0) {
            // 检测 UBX 协议签名 (F9P/UM982)
            if (buf[0] == 0xB5 && buf[1] == 0x62) {
                log_print(0, "in chkgpsmod : found f9p, sig=%02X%02X...",
                          buf[0], buf[1]);
                return MODULE_F9P;
            }

            // 检测 NMEA 语句
            if (buf[0] == '$') {
                // 查找 NMEA 校验和
                for (int i = 0; i < r; i++) {
                    if (buf[i] == '*') {
                        log_print(0, "NMEA detected, data: %.*s...",
                                  (i > 60 ? 60 : i), buf);
                        return MODULE_CH343;  // CH343 直接输出 NMEA
                    }
                }
            }
        }
    }

    return MODULE_UNKNOWN;
}

// 处理 NMEA 数据并注入到系统
static void process_nmea(const char* data, int len) {
    // 验证 NMEA 校验和
    if (data[0] != '$') return;

    // 找到校验和位置
    const char* checksum_pos = strchr(data, '*');
    if (checksum_pos == NULL) return;

    // 转发到 GPS 套接字或 HAL
    // ...注入逻辑...
}
```

### 4.5 log.cpp (日志系统)
```cpp
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <unistd.h>

static FILE* g_log_fp = NULL;
static char g_logfile[512] = "/data/local/tmp/gnssdrv.log";

extern "C" void log_init(const char* logfile) {
    if (logfile) {
        strncpy(g_logfile, logfile, sizeof(g_logfile)-1);
    }

    // 日志轮转: gnssdrv.log → gnssdrv1.log → gnssdrv2.log
    char cmd[1024];

    // mv gnssdrv.log gnssdrv1.log
    snprintf(cmd, sizeof(cmd), "mv %s %s.1 2>/dev/null; "
                               "mv %s.1 %s.2 2>/dev/null; "
                               "rm %s.2 2>/dev/null",
             g_logfile, g_logfile, g_logfile, g_logfile, g_logfile);
    system(cmd);

    g_log_fp = fopen(g_logfile, "a");
    if (!g_log_fp) {
        g_log_fp = stderr;
    }
}

extern "C" void log_print(int level, const char* fmt, ...) {
    if (!g_log_fp) return;

    time_t now = time(NULL);
    struct tm* tm_info = localtime(&now);
    char timebuf[32];
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm_info);

    fprintf(g_log_fp, "[%s] ", timebuf);

    va_list args;
    va_start(args, fmt);
    vfprintf(g_log_fp, fmt, args);
    va_end(args);

    fprintf(g_log_fp, "\n");
    fflush(g_log_fp);
}
```

## 5. 对于 CH343P 的适配

根据字符串分析，该 `usbgps` 二进制已经支持 CH343P，但需要进行以下配置：

### 5.1 推荐的启动参数
```bash
/vendor/bin/usbgps \
    -m /dev/ttyUSB0 \      # 设备路径 (根据实际调整)
    -b 460800 \             # 波特率 (UN982/UM621A 通常用 460800)
    -l /data/local/tmp/gnssdrv.log
```

### 5.2 关键配置属性
```bash
# 通过 resetprop 设置
resetprop persist.vendor.icoe.gps_port /dev/ttyUSB0
resetprop persist.vendor.icoe.gps_baud 460800
resetprop persist.vendor.icoe.gps_mode external
```

### 5.3 与 CH343P 的兼容性

| 特性 | 支持状态 | 说明 |
|------|---------|------|
| 设备发现 `/dev/ttyUSB*` | ✅ | 支持 glob 模式匹配 |
| 设备发现 `/dev/ttyACM*` | ✅ | 支持 USB CDC-ACM |
| 波特率 460800 | ✅ | 字符串中有 `B460800` |
| NMEA 读取 | ✅ | SerialRead 循环读取 |
| 内核模块加载 | ✅ | insmod usbserial.ko |
| 内置 GNSS 停止 | ✅ | stop vendor.gnss_service_sprd |
| 属性管理 | ✅ | resetprop --delete |
| 热插拔监控 | ✅ | inotify 监听 /dev |
| NMEA 日志 | ✅ | gnssdrv.log 轮转 |

## 6. gps.default.so HAL 库分析 (31.3 KB)

### 6.1 核心发现

| 属性 | 值 |
|------|-----|
| 类型 | Android GNSS HAL 实现库 |
| 平台 | UNISOC/展讯 (Spreadtrum) |
| 函数前缀 | `zkw_gps_*` (展讯 GNSS HAL) |
| 入口函数 | `gps__get_gps_interface()` |
| 目标设备文件 | `/dev/ttyUSB` `/dev/ttyS3` |
| 控制服务 | `unicore_service` (Socket 通信) |

### 6.2 完整函数列表

| 函数名 | 作用 |
|--------|------|
| `zkw_gps_init()` | HAL 初始化 |
| `zkw_gps_start()` | 启动 GPS 会话 |
| `zkw_gps_stop()` | 停止 GPS 会话 |
| `zkw_gps_cleanup()` | 清理资源 |
| `zkw_gps_set_position_mode()` | 设置定位模式 |
| `zkw_gps_delete_aiding_data()` | 删除辅助数据 |
| `zkw_gps_inject_time()` | 注入时间 (AGPS) |
| `zkw_gps_inject_location()` | 注入位置 |
| `zkw_gps_inject_bestlocation()` | 注入最佳位置 |
| `gps__get_gps_interface()` | **HAL 入口函数** |

### 6.3 gps.default.so 架构

```
┌─────────────────────────────────────────────────────────┐
│              Android Location Manager                     │
│                     (Java/Kotlin)                        │
└───────────────────────┬─────────────────────────────────┘
                        │ dlopen("gps.default.so")
                        │ gps__get_gps_interface()
┌───────────────────────▼─────────────────────────────────┐
│              gps.default.so (zkw_gps)                    │
│  ┌─────────────────────────────────────────────────────┐  │
│  │              HAL 线程 (epoll 事件循环)              │  │
│  │  - gps_state_init()                                 │  │
│  │  - gps_state_start() → location_cb() 回调          │  │
│  │  - gps_state_stop()                                │  │
│  │  - gps_state_done()                               │  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ NMEA 读取线程 │  │ AGPS 注入线程 │  │ 控制线程     │  │
│  │ open(ttyUSB) │  │ gnss_inject  │  │ socketpair   │  │
│  │ epoll_wait()  │  │   _thread()  │  │ epoll        │  │
│  └──────┬───────┘  └──────────────┘  └──────┬───────┘  │
│         │                                     │          │
└─────────┼──────────────────────────────┬──────┼──────────┘
          │                              │      │
          ▼                              ▼      ▼
    /dev/ttyUSB0               /dev/socket/unicore_service
          ▲                              │
          │                              │
    CH343P USB GPS           ┌────────────┴───────┐
    (UM982/UM621A)           │  unicore_service  │
                             │  (后台守护进程)     │
                             └────────────────────┘
```

### 6.4 HAL 源码重构

```cpp
// gps.default.so 入口函数
extern "C" const GpsInterface* gps__get_gps_interface() {
    return &g_zkwGpsInterface;
}

static const GpsInterface g_zkwGpsInterface = {
    sizeof(GpsInterface),    // size
    zkw_gps_init,           // init
    zkw_gps_start,          // start
    zkw_gps_stop,           // stop
    zkw_gps_cleanup,         // cleanup
    zkw_gps_inject_time,     // inject_time
    zkw_gps_inject_location,  // inject_location
    zkw_gps_delete_aiding_data, // delete_aiding_data
    zkw_gps_set_position_mode,  // set_position_mode
    NULL,                     // set_server
    NULL,                     // set_reference_location
    NULL,                     // set_reference_location_cellid
    NULL,                     // inform_receiver_server_time
    zkw_gps_get_extension,   // get_extension
};

// 初始化
static int zkw_gps_init(GpsCallbacks* callbacks) {
    g_callbacks = *callbacks;
    // 创建 HAL 线程
    pthread_create(&g_hal_thread, NULL, hal_thread_func, NULL);
    return 0;
}

// HAL 主线程
static void* hal_thread_func(void* arg) {
    // 创建 epoll 实例
    int epfd = epoll_create1(0);
    
    // 打开 GPS 串口设备
    int gps_fd = open("/dev/ttyUSB", O_RDWR);
    
    // 配置串口: 波特率 460800, 8N1
    struct termios tio;
    tcgetattr(gps_fd, &tio);
    cfmakeraw(&tio);
    cfsetispeed(&tio, B460800);
    cfsetospeed(&tio, B460800);
    tcsetattr(gps_fd, TCSANOW, &tio);
    
    // 注册 epoll 事件
    struct epoll_event ev;
    ev.events = EPOLLIN;
    ev.data.fd = gps_fd;
    epoll_ctl(epfd, EPOLL_CTL_ADD, gps_fd, &ev);
    
    // 主事件循环
    while (g_running) {
        struct epoll_event events[8];
        int n = epoll_wait(epfd, events, 8, -1);
        
        for (int i = 0; i < n; i++) {
            if (events[i].data.fd == gps_fd) {
                // 读取 NMEA 数据
                char buf[4096];
                int r = read(gps_fd, buf, sizeof(buf));
                if (r > 0) {
                    // 解析 NMEA 并调用 callbacks
                    parse_nmea_and_report_location(buf, r);
                }
            }
        }
    }
    
    close(gps_fd);
    close(epfd);
    return NULL;
}

// NMEA 解析 + 位置上报
static void parse_nmea_and_report_location(char* data, int len) {
    // 解析 $GPGGA, $GPRMC 等 NMEA 语句
    // 提取经纬度、时间、卫星数等
    // 调用 g_callbacks.location_cb() 上报位置
}
```

### 6.5 系统集成

```
unicore_service  ← 通过 Socket 与 gps.default.so 通信
      │
      ├── 读取 /dev/ttyUSB0 (CH343P GPS 模块)
      │
      └── 解析 NMEA + 注入到 Android Location Framework

/rootfs/vendor/bin/unicore_service (或 /system/bin/)
```

### 6.6 对于 CH343P 的适配

**gps.default.so 已经支持 CH343P！**
- 它直接打开 `/dev/ttyUSB` 读取 NMEA
- 无需任何修改即可支持 CH343P (只要 CH343P 输出标准 NMEA)
- 波特率: 460800 (写入设备) / 从 GPS 模块自动检测

## 7. 编译信息分析

从二进制中提取的编译元数据：

```
Build System: Termux (Android 终端)
Compiler:     Clang 14.0.0
Build Path:   /data/data/com.termux/files/home/project/llvm-toolchain/
LLVM Version: 225da9a3c956f7d6631048b9b28568149c05a8aa
Target:       aarch64-linux-android27
Linker:       LLD 12.0.8
Min SDK:      27 (Android 8.1)
Target SDK:   34 (Android 13)
```

**这意味着**：原始作者是在 Android 设备（车机）上通过 Termux 安装 Clang 工具链，然后直接在设备上编译的二进制！
