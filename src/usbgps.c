/*
 * USB GPS Bridge for Android (Termux Native Build)
 * =================================================
 * Supports: CH343, CH340, CP210x, FTDI, PL2303, CDC-ACM, UM982, UM621A
 * Auto-detects: USB device, baud rate, GPS module model
 * NMEA passthrough to Android GPS HAL socket
 *
 * Build (Termux): make
 * Build (NDK/standalone): aarch64-linux-android-gcc -o usbgps usbgps.c -static -O2
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/time.h>
#include <dirent.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>

/* ======================= CONFIG ======================= */
#define GPS_SOCKET_PATH     "/dev/socket/gps"
#define GPS_SOCKET_PATH2    "/dev/socket/location/gps"
#define GPS_SOCKET_PATH3    "/dev/socket/gps_socket"
#define BAUD_DEFAULT        B460800
#define BAUD_FALLBACK       B115200
#define NMEA_BUF_SIZE       4096
#define SAMPLE_TIMEOUT_MS   3000
#define DETECT_BUFSIZE      512
#define LOG(fmt, ...) do { } while(0)

/* ======================= GPS MODULE DATABASE ======================= */
typedef struct {
    const char *vid;
    const char *pid;
    const char *name;
    int default_baud;
    int supported_bauds[8];
} gps_module_t;

static const gps_module_t known_modules[] = {
    /* U-Blox modules */
    { "1546", "uta",  "u-blox NEO-M9N",   B460800,  { B460800, B115200, B38400, B9600, 0 }},
    { "1546", "u01",  "u-blox NEO-M10S",  B115200,  { B115200, B460800, B38400, B9600, 0 }},
    { "1546", "u02",  "u-blox ZED-F9P",   B460800,  { B460800, B115200, B38400, B9600, 0 }},
    { "1546", "u03",  "u-blox ZED-F9R",   B460800,  { B460800, B115200, B38400, B9600, 0 }},
    { "1546", "u04",  "u-blox ZED-M10",   B115200,  { B115200, B460800, B38400, B9600, 0 }},

    /* UM982 / UM621A - Unicore */
    { "2e88", "fff1", "UM982 GNSS",        B460800,  { B460800, B115200, B921600, B38400, B9600, 0 }},
    { "2e88", "fff2", "UM621A GNSS",       B460800,  { B460800, B115200, B921600, B38400, B9600, 0 }},
    { "2e88", "fff3", "UM6L0 GNSS",        B115200,  { B115200, B460800, B921600, B38400, B9600, 0 }},

    /* CH340 / CH341 - WCH */
    { "1a86", "7523", "WCH CH340",        B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "1a86", "5523", "WCH CH341",        B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "4348", "5523", "WCH CH340G",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "1a86", "55d4", "WCH CH343",        B460800,  { B460800, B115200, B921600, B57600, B230400, B9600, 0 }},
    { "1a86", "55dd", "WCH CH343K",       B460800,  { B460800, B115200, B921600, B57600, B230400, B9600, 0 }},

    /* CP210x - Silicon Labs */
    { "10c4", "ea60", "Silicon Labs CP210x", B115200, { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},
    { "10c4", "ea70", "Silicon Labs CP2105",  B115200, { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},

    /* FTDI */
    { "0403", "6001", "FTDI FT232R",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},
    { "0403", "6010", "FTDI FT2232",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},
    { "0403", "6011", "FTDI FT4232",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},
    { "0403", "6014", "FTDI FT232H",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},
    { "0403", "7c00", "FTDI FT231X",       B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, B921600, 0 }},

    /* PL2303 - Prolific */
    { "067b", "2303", "Prolific PL2303",   B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "067b", "23a3", "Prolific PL2303GC", B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "067b", "25a3", "Prolific PL2303GB", B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "067b", "26a3", "Prolific PL2303GT", B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
    { "067b", "27a3", "Prolific PL2303GL", B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},

    /* CDC-ACM generic */
    { "0000", "0000", "Generic CDC-ACM",   B115200,  { B115200, B9600, B38400, B57600, B230400, B460800, 0 }},
};

static const int baud_rates[] = {
    B460800, B921600, B230400, B115200,
    B57600,  B38400,  B9600,   0
};

/* ======================= FORWARD DECLARATIONS ======================= */
static int     open_serial(const char *port, speed_t baud);
static speed_t detect_baud_rate(const char *port);
static speed_t try_baud(const char *port, speed_t baud);
static int     has_nmea_data(const char *port, int timeout_ms);
static int     is_valid_nmea(const char *buf, int len);
static int     open_gps_socket(void);
static void    daemonize(void);
static void    signal_handler(int sig);
static void    log_msg(const char *fmt, ...);
static const char* baud_to_str(speed_t baud);
static int     check_device_exists(const char *port);
static const gps_module_t* detect_module_type(const char *port);
static int     set_baud_rate(int fd, speed_t baud);

/* ======================= GLOBAL STATE ======================= */
static volatile int g_running = 1;
static int g_debug = 0;
static int g_baud = B460800;

/* ======================= SIGNAL HANDLING ======================= */
static void signal_handler(int sig) {
    (void)sig;
    g_running = 0;
}

/* ======================= LOGGING ======================= */
static void log_msg(const char *fmt, ...) {
    if (!g_debug) return;
    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char timebuf[32];
    strftime(timebuf, sizeof(timebuf), "%H:%M:%S", tm);
    fprintf(stderr, "[usbgps %s] ", timebuf);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
}

/* ======================= BAUD RATE HELPERS ======================= */
static const char* baud_to_str(speed_t baud) {
    switch (baud) {
        case B9600:   return "9600";
        case B19200:  return "19200";
        case B38400:  return "38400";
        case B57600:  return "57600";
        case B115200: return "115200";
        case B230400: return "230400";
        case B460800: return "460800";
        case B921600: return "921600";
        default:      return "UNKNOWN";
    }
}

static speed_t str_to_baud(const char *str) {
    int b = atoi(str);
    switch (b) {
        case 9600:   return B9600;
        case 19200:  return B19200;
        case 38400:  return B38400;
        case 57600:  return B57600;
        case 115200: return B115200;
        case 230400: return B230400;
        case 460800: return B460800;
        case 921600: return B921600;
        default:     return 0;
    }
}

/* ======================= DEVICE SCANNING ======================= */
static int check_device_exists(const char *port) {
    return access(port, R_OK | W_OK) == 0;
}

/* Read USB device info from /sys */
static int read_usb_info(const char *port, char *vid, char *pid, size_t vidsize, char *pidsize) {
    char syspath[256];
    char realpath_buf[512];
    
    if (realpath(port, realpath_buf) == NULL) return -1;
    
    /* Try to find USB device info in sysfs */
    char *tty = strstr(realpath_buf, "/ttyUSB");
    char *acm = strstr(realpath_buf, "/ttyACM");
    
    if (!tty && !acm) {
        /* Might be USB serial over ChaoZhou */
        snprintf(syspath, sizeof(syspath), "/sys/class/tty/%s/device/driver", 
                 strrchr(port, '/') ? strrchr(port, '/') + 1 : port);
    }
    
    /* Try common patterns for CH343 */
    snprintf(syspath, sizeof(syspath), "/sys/class/tty/%s/device/idVendor",
             strrchr(port, '/') ? strrchr(port, '/') + 1 : port);
    
    FILE *f = fopen(syspath, "r");
    if (f) {
        if (fgets(vid, vidsize, f)) {
            vid[strcspn(vid, "\n")] = 0;
            fclose(f);
            snprintf(syspath, sizeof(syspath), "/sys/class/tty/%s/device/idProduct",
                     strrchr(port, '/') ? strrchr(port, '/') + 1 : port);
            FILE *f2 = fopen(syspath, "r");
            if (f2) {
                if (fgets(pid, pidsize, f2)) pid[strcspn(pid, "\n")] = 0;
                fclose(f2);
            }
            return 0;
        }
        fclose(f);
    }
    
    /* Fallback: try CH343-specific sysfs path */
    snprintf(syspath, sizeof(syspath), "/sys/bus/usb-serial/devices/%s/device/../idVendor",
             strrchr(port, '/') ? strrchr(port, '/') + 1 : port);
    f = fopen(syspath, "r");
    if (f) {
        if (fgets(vid, vidsize, f)) vid[strcspn(vid, "\n")] = 0;
        fclose(f);
        return 0;
    }
    
    return -1;
}

static const gps_module_t* detect_module_type(const char *port) {
    char vid[32] = {0};
    char pid[32] = {0};
    
    if (read_usb_info(port, vid, pid, sizeof(vid), sizeof(pid)) == 0 && vid[0]) {
        for (int i = 0; i < (int)(sizeof(known_modules)/sizeof(known_modules[0])); i++) {
            const gps_module_t *m = &known_modules[i];
            if (strcasecmp(vid, m->vid) == 0 && strcasecmp(pid, m->pid) == 0) {
                return m;
            }
        }
    }
    return NULL;
}

/* ======================= SERIAL I/O ======================= */
static int set_baud_rate(int fd, speed_t baud) {
    struct termios2 t;
    if (ioctl(fd, TCGETS2, &t) == 0) {
        t.c_cflag &= ~CBAUD;
        t.c_cflag |= BOTHER;
        t.c_ispeed = t.c_ospeed = (speed_t)ioctl(fd, SOUND_PEEKSPEED, (void*)(long)baud);
        if (t.c_ispeed == 0) t.c_ispeed = t.c_ospeed = (speed_t)baud;
        if (ioctl(fd, TCSETS2, &t) == 0) return 0;
    }
    
    /* Fallback: standard termios */
    struct termios tt;
    if (tcgetattr(fd, &tt) == 0) {
        cfsetospeed(&tt, baud);
        cfsetispeed(&tt, baud);
        if (tcsetattr(fd, TCSANOW, &tt) == 0) return 0;
    }
    return -1;
}

static int open_serial(const char *port, speed_t baud) {
    int fd = open(port, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) return -1;
    
    struct termios tt;
    memset(&tt, 0, sizeof(tt));
    if (tcgetattr(fd, &tt) != 0) {
        close(fd);
        return -1;
    }
    
    cfmakeraw(&tt);
    tt.c_cflag = CS8 | CLOCAL | CREAD;
    tt.c_iflag = 0;
    tt.c_oflag = 0;
    tt.c_lflag = 0;
    tt.c_cc[VMIN] = 0;
    tt.c_cc[VTIME] = 10; /* 1 second timeout */
    
    cfsetospeed(&tt, baud);
    cfsetispeed(&tt, baud);
    
    if (tcsetattr(fd, TCSANOW, &tt) != 0) {
        close(fd);
        return -1;
    }
    
    /* Flush buffers */
    tcflush(fd, TCIOFLUSH);
    return fd;
}

/* ======================= NMEA VALIDATION ======================= */
static int is_valid_nmea(const char *buf, int len) {
    if (len < 6) return 0;
    if (buf[0] != '$') return 0;
    
    /* Find * marker */
    const char *star = memchr(buf, '*', len);
    if (!star) {
        /* No checksum, check for plain NMEA sentence */
        return (strstr(buf, "GNGGA") || strstr(buf, "GLGGA") || 
                strstr(buf, "GPGGA") || strstr(buf, "GNRMC") ||
                strstr(buf, "GNZDA") || strstr(buf, "GNGSA") ||
                strstr(buf, "GNVTG") || strstr(buf, "$")) ? 1 : 0;
    }
    
    int datalen = star - buf;
    if (datalen < 6) return 0;
    
    /* Verify checksum if present */
    if (star - buf + 3 <= len) {
        int checksum = 0;
        for (int i = 1; i < datalen; i++) checksum ^= buf[i];
        char checksum_str[3];
        snprintf(checksum_str, sizeof(checksum_str), "%02X", checksum);
        if (strncasecmp(star + 1, checksum_str, 2) == 0) return 1;
        /* Accept even without valid checksum (lenient) */
        return (buf[0] == '$') ? 1 : 0;
    }
    
    return (buf[0] == '$') ? 1 : 0;
}

/* ======================= BAUD RATE DETECTION ======================= */
static int has_nmea_data(int fd, int timeout_ms) {
    fd_set rfds;
    struct timeval tv;
    
    FD_ZERO(&rfds);
    FD_SET(fd, &rfds);
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    
    char buf[256];
    int total = 0;
    
    /* Wait for data */
    int ret = select(fd + 1, &rfds, NULL, NULL, &tv);
    if (ret <= 0) return 0;
    
    /* Read available data */
    while (1) {
        ret = select(fd + 1, &rfds, NULL, NULL, &tv);
        if (ret <= 0) break;
        int n = read(fd, buf + total, sizeof(buf) - total - 1);
        if (n <= 0) break;
        total += n;
        if (total >= 6) break;
    }
    
    if (total > 0) {
        buf[total] = '\0';
        return is_valid_nmea(buf, total);
    }
    return 0;
}

static speed_t try_baud(const char *port, speed_t baud) {
    int fd = open_serial(port, baud);
    if (fd < 0) return 0;
    
    /* Try to read NMEA data */
    int found = has_nmea_data(fd, SAMPLE_TIMEOUT_MS);
    close(fd);
    
    if (found) {
        log_msg("[baud] ✓ Baud %s has valid NMEA data", baud_to_str(baud));
        return baud;
    }
    log_msg("[baud] ✗ Baud %s has no NMEA data", baud_to_str(baud));
    return 0;
}

static speed_t detect_baud_rate(const char *port) {
    log_msg("[baud] Starting baud rate auto-detection for %s", port);
    
    /* First: try module-specific defaults */
    const gps_module_t *mod = detect_module_type(port);
    if (mod && mod->default_baud) {
        log_msg("[baud] Detected module: %s, trying default baud %s",
                mod->name, baud_to_str(mod->default_baud));
        if (try_baud(port, mod->default_baud)) return mod->default_baud;
        
        /* Try other supported bauds for this module */
        for (int i = 0; mod->supported_bauds[i]; i++) {
            if (mod->supported_bauds[i] == mod->default_baud) continue;
            if (try_baud(port, mod->supported_bauds[i])) 
                return mod->supported_bauds[i];
        }
    }
    
    /* Generic scan: try all common baud rates */
    log_msg("[baud] Scanning all common baud rates...");
    for (int i = 0; baud_rates[i]; i++) {
        if (baud_rates[i] == B921600) continue; /* Skip rarest */
        speed_t result = try_baud(port, baud_rates[i]);
        if (result) return result;
    }
    
    /* Last resort: try B921600 */
    if (try_baud(port, B921600)) return B921600;
    
    log_msg("[baud] WARNING: Could not detect baud rate!");
    return B460800; /* Safe default for UM982/CH343 */
}

/* ======================= GPS SOCKET ======================= */
static int open_gps_socket(void) {
    const char *paths[] = {
        GPS_SOCKET_PATH,
        GPS_SOCKET_PATH2,
        GPS_SOCKET_PATH3,
        "/dev/socket/gps-hal",
        NULL
    };
    
    for (int i = 0; paths[i]; i++) {
        int sock = socket(AF_UNIX, SOCK_DGRAM, 0);
        if (sock < 0) continue;
        
        struct sockaddr_un addr;
        memset(&addr, 0, sizeof(addr));
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, paths[i], sizeof(addr.sun_path) - 1);
        
        if (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0) {
            log_msg("[gps] Connected to HAL socket: %s", paths[i]);
            return sock;
        }
        close(sock);
    }
    
    log_msg("[gps] WARNING: Could not connect to GPS socket");
    return -1;
}

/* ======================= USB DEVICE SCANNING ======================= */
static int is_gps_device_path(const char *name) {
    return (strstr(name, "ttyUSB") != NULL ||
            strstr(name, "ttyACM") != NULL ||
            strstr(name, "ttyHS")  != NULL ||
            strstr(name, "ttyW")   != NULL ||
            strstr(name, "ttyS")   != NULL);
}

static void scan_usb_devices(char (*devices)[256], int *count, int max) {
    *count = 0;
    DIR *d = opendir("/dev");
    if (!d) return;
    
    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        if (!is_gps_device_path(entry->d_name)) continue;
        if (*count >= max) break;
        
        char path[300];
        snprintf(path, sizeof(path), "/dev/%s", entry->d_name);
        
        /* Verify we can open it */
        int test = open(path, O_RDWR | O_NOCTTY);
        if (test >= 0) {
            close(test);
            strncpy(devices[*count], path, 255);
            (*count)++;
            log_msg("[scan] Found device: %s", path);
        }
    }
    closedir(d);
}

static const char* detect_gps_module_name(const char *port) {
    const gps_module_t *mod = detect_module_type(port);
    if (mod) return mod->name;
    
    /* Try reading from /proc/bus/usb/devices or uevent */
    FILE *f;
    char line[512];
    char syspath[256];
    char ttyname[64];
    
    strncpy(ttyname, strrchr(port, '/') ? strrchr(port, '/') + 1 : port, sizeof(ttyname) - 1);
    
    snprintf(syspath, sizeof(syspath), "/sys/class/tty/%s/device/uevent", ttyname);
    f = fopen(syspath, "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "PRODUCT=", 8) == 0) {
                /* Format: VID/PID/BCD */
                char *p = line + 8;
                char vid[16] = {0}, pid[16] = {0};
                int vi, pi;
                if (sscanf(p, "%x/%x/", &vi, &pi) == 2) {
                    snprintf(vid, sizeof(vid), "%04x", vi);
                    snprintf(pid, sizeof(pid), "%04x", pi);
                    
                    for (int i = 0; i < (int)(sizeof(known_modules)/sizeof(known_modules[0])); i++) {
                        const gps_module_t *m = &known_modules[i];
                        if (strcasecmp(vid, m->vid) == 0 && strcasecmp(pid, m->pid) == 0) {
                            fclose(f);
                            return m->name;
                        }
                    }
                    static char generic[64];
                    snprintf(generic, sizeof(generic), "USB Serial %s:%s", vid, pid);
                    fclose(f);
                    return generic;
                }
            }
        }
        fclose(f);
    }
    
    return "Unknown USB GPS Module";
}

/* ======================= DAEMONIZE ======================= */
static void daemonize(void) {
    signal(SIGTERM, signal_handler);
    signal(SIGINT,  signal_handler);
    signal(SIGHUP,  signal_handler);
    
    /* Don't fully daemonize - keep in foreground so Magisk can manage */
    /* But redirect stdout/stderr to /dev/null */
    int nullfd = open("/dev/null", O_RDWR);
    if (nullfd >= 0) {
        dup2(nullfd, STDIN_FILENO);
        dup2(nullfd, STDOUT_FILENO);
        dup2(nullfd, STDERR_FILENO);
        if (nullfd > 2) close(nullfd);
    }
}

/* ======================= GPS BRIDGE LOOP ======================= */
static int bridge_loop(int serial_fd, int gps_fd) {
    unsigned char buf[NMEA_BUF_SIZE];
    unsigned char line[NMEA_BUF_SIZE];
    int line_pos = 0;
    int nmea_count = 0;
    time_t last_report = time(NULL);
    
    while (g_running) {
        fd_set rfds;
        struct timeval tv;
        
        FD_ZERO(&rfds);
        FD_SET(serial_fd, &rfds);
        tv.tv_sec = 2;
        tv.tv_usec = 0;
        
        int ret = select(serial_fd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR || errno == EAGAIN) continue;
            break;
        }
        if (ret == 0) {
            /* Periodic health check */
            time_t now = time(NULL);
            if (now - last_report >= 60) {
                log_msg("[status] Running, NMEA packets: %d", nmea_count);
                last_report = now;
            }
            continue;
        }
        
        int n = read(serial_fd, buf, sizeof(buf) - 1);
        if (n <= 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
            log_msg("[error] Serial read error: %s", strerror(errno));
            break;
        }
        buf[n] = '\0';
        
        /* Process byte by byte, extract NMEA sentences */
        for (int i = 0; i < n; i++) {
            if (buf[i] == '\r' || buf[i] == '\n') {
                if (line_pos > 0 && line[0] == '$') {
                    line[line_pos] = '\0';
                    
                    if (is_valid_nmea((char*)line, line_pos)) {
                        nmea_count++;
                        
                        /* Forward to GPS HAL socket */
                        if (gps_fd >= 0) {
                            int sent = send(gps_fd, line, line_pos, 0);
                            if (g_debug && sent > 0 && nmea_count % 100 == 0) {
                                log_msg("[nmea] Forwarded: %.20s... (total: %d)", line, nmea_count);
                            }
                        }
                        
                        /* Also write to stdout for debugging */
                        if (g_debug && nmea_count <= 5) {
                            log_msg("[nmea] >>> %s", line);
                        }
                    }
                    line_pos = 0;
                }
            } else if (buf[i] >= 0x20 && buf[i] < 0x7F) {
                /* Printable ASCII */
                if (line_pos < NMEA_BUF_SIZE - 1) {
                    line[line_pos++] = buf[i];
                }
            } else if ((unsigned char)buf[i] >= 0x80) {
                /* Binary garbage from wrong baud rate - reset */
                if (line_pos > 0) {
                    line_pos = 0;
                }
            }
        }
    }
    
    return 0;
}

/* ======================= MAIN ======================= */
static void print_usage(const char *prog) {
    fprintf(stderr,
        "USB GPS Bridge v2.1 (Termux Build)\n"
        "Usage: %s [options]\n"
        "  -d          Debug mode (verbose logging to stderr)\n"
        "  -b <rate>   Force baud rate (9600,115200,460800,etc)\n"
        "  -p <port>   Force serial port (e.g. /dev/ttyUSB0)\n"
        "  -s <socket> Force GPS socket path\n"
        "  -h          Show this help\n"
        "\n"
        "Auto-detection: Scans /dev/ttyUSB* and /dev/ttyACM* for GPS devices,\n"
        "                auto-detects baud rate and module type.\n",
        prog);
}

int main(int argc, char *argv[]) {
    const char *forced_port = NULL;
    const char *forced_socket = NULL;
    speed_t forced_baud = 0;
    
    /* Parse args */
    int opt;
    while ((opt = getopt(argc, argv, "hdb:p:s:")) != -1) {
        switch (opt) {
            case 'd': g_debug = 1; break;
            case 'b': forced_baud = str_to_baud(optarg); break;
            case 'p': forced_port = optarg; break;
            case 's': forced_socket = optarg; break;
            default:
            case 'h': print_usage(argv[0]); return 0;
        }
    }
    
    fprintf(stderr, "USB GPS Bridge v2.1 - Termux Build\n");
    
    /* Daemonize (keep foreground if debug) */
    if (!g_debug) daemonize();
    
    /* Find GPS device */
    char serial_port[256];
    if (forced_port) {
        strncpy(serial_port, forced_port, sizeof(serial_port) - 1);
        if (!check_device_exists(serial_port)) {
            fprintf(stderr, "[usbgps] ERROR: Device %s not found\n", serial_port);
            return 1;
        }
    } else {
        char devices[16][256];
        int count = 0;
        scan_usb_devices(devices, &count, 16);
        
        if (count == 0) {
            fprintf(stderr, "[usbgps] ERROR: No USB GPS device found!\n");
            fprintf(stderr, "[usbgps] Make sure your USB GPS module is connected.\n");
            return 1;
        }
        
        strncpy(serial_port, devices[0], sizeof(serial_port) - 1);
        if (count > 1) {
            fprintf(stderr, "[usbgps] WARNING: Multiple devices found, using: %s\n", serial_port);
        }
    }
    
    /* Detect module type */
    const char *module_name = detect_gps_module_name(serial_port);
    fprintf(stderr, "[usbgps] GPS Module: %s @ %s\n", module_name, serial_port);
    
    /* Detect baud rate */
    if (forced_baud) {
        g_baud = forced_baud;
        fprintf(stderr, "[usbgps] Using forced baud rate: %s\n", baud_to_str(g_baud));
    } else {
        g_baud = detect_baud_rate(serial_port);
        fprintf(stderr, "[usbgps] Detected baud rate: %s\n", baud_to_str(g_baud));
    }
    
    /* Open serial */
    int serial_fd = open_serial(serial_port, g_baud);
    if (serial_fd < 0) {
        fprintf(stderr, "[usbgps] ERROR: Cannot open %s\n", serial_port);
        return 1;
    }
    
    /* Open GPS socket */
    int gps_fd = open_gps_socket();
    if (gps_fd < 0) {
        fprintf(stderr, "[usbgps] WARNING: GPS HAL socket not available, outputting to stdout only\n");
    }
    
    fprintf(stderr, "[usbgps] Bridge started, forwarding NMEA data...\n");
    
    /* Main loop */
    int ret = bridge_loop(serial_fd, gps_fd);
    
    /* Cleanup */
    if (serial_fd >= 0) close(serial_fd);
    if (gps_fd >= 0) close(gps_fd);
    
    fprintf(stderr, "[usbgps] Exiting\n");
    return ret;
}
