/**
 * usb_gps_bridge — NMEA GNSS Bridge v3
 * Pure POSIX, no Android framework dependencies.
 * Auto-detects USB GPS modules and baud rates.
 * Supports UN982 / UM621A full-constellation output.
 *
 * Build (Android NDK):
 *   aarch64-linux-android21-clang++ -target aarch64-linux-android21 \
 *     -static -std=c++17 -O2 main.cpp -o usb_gps_bridge
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <cstdarg>
#include <cerrno>
#include <ctime>
#include <algorithm>
#include <string>
#include <vector>

/* Android / POSIX */
#include <sys/select.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <signal.h>
#include <ctype.h>

/* ═══════════════════════════════════════════════════════════════
 *  Constants
 * ═══════════════════════════════════════════════════════════════ */

#define MAX_NMEA_LEN   512
#define READ_BUF_SIZE  4096
#define INJECT_BUF_SIZE 8192

/* Baud rates tested in priority order */
static const int BAUD_RATES[] = {460800, 115200, 57600, 38400, 19200, 9600, 4800};
static const int N_BAUDS = (int)(sizeof(BAUD_RATES) / sizeof(BAUD_RATES[0]));

/* GPS socket paths */
static const char* GPS_SOCKETS[] = {
    "/dev/socket/gps",
    "/dev/socket/location/gps",
    "/dev/socket/location/gps_bridge",
    "/dev/socket/location/gnss",
    NULL
};

/* ═══════════════════════════════════════════════════════════════
 *  USB Device Database — UN982 / UM621A + common USB-TTL chips
 * ═══════════════════════════════════════════════════════════════ */

struct UsbDevice {
    const char* name;
    const char* vidpid;       /* "VID:PID" */
    const char* driver;
    int         default_baud;
};

static const UsbDevice USB_DB[] = {
    /* UN982 — Full-constellation GNSS */
    {"UN982 GNSS",        "2c7c:6005", "cdc_acm", 460800},
    /* UM621A — Full-constellation GNSS */
    {"UM621A GNSS",       "2c7c:0900", "cdc_acm", 460800},
    /* Quectel LC29H */
    {"Quectel LC29H",    "2c7c:0306", "cdc_acm", 115200},
    /* Quectel L76-L */
    {"Quectel L76-L",    "2c7c:0205", "cdc_acm", 115200},
    /* Quectel L89 */
    {"Quectel L89",      "2c7c:0301", "cdc_acm", 115200},
    /* CH343P — most common GPS adapter */
    {"CH343P GPS",       "1a86:55d4", "ch343",   460800},
    {"CH343P GPS",       "1a86:55d3", "ch343",   460800},
    /* CH340 */
    {"CH340 GPS",        "1a86:7523", "ch340",   115200},
    /* CP210x */
    {"CP210x GPS",       "10c4:ea60", "cp210x",  115200},
    {"CP2104 GPS",      "10c4:ea71", "cp210x",  115200},
    /* FTDI FT232 */
    {"FTDI FT232",       "0403:6001", "ftdi_sio",115200},
    {"FTDI FT231X",      "0403:6015", "ftdi_sio",115200},
    /* PL2303 */
    {"PL2303 GPS",       "067b:2303", "pl2303",  115200},
};

static const int N_USB_DB = (int)(sizeof(USB_DB) / sizeof(USB_DB[0]));

/* ═══════════════════════════════════════════════════════════════
 *  Logging
 * ═══════════════════════════════════════════════════════════════ */

enum LogLevel { L_ERROR = 0, L_WARN = 1, L_INFO = 2, L_DEBUG = 3, L_VERBOSE = 4 };

static LogLevel  g_min_level = L_INFO;
static FILE*     g_logf      = NULL;
static const char* g_tag     = "usb_gps";

/* ═══════════════════════════════════════════════════════════════
 *  Logging (continued)
 * ═══════════════════════════════════════════════════════════════ */

static void init_log(const char* path) {
    if (path && path[0]) {
        g_logf = fopen(path, "a");
    }
}

static void set_level(const char* s) {
    if (!strcmp(s, "ERROR"))   g_min_level = L_ERROR;
    else if (!strcmp(s, "WARN"))  g_min_level = L_WARN;
    else if (!strcmp(s, "INFO"))  g_min_level = L_INFO;
    else if (!strcmp(s, "DEBUG")) g_min_level = L_DEBUG;
    else if (!strcmp(s, "VERBOSE")) g_min_level = L_VERBOSE;
}

/* Simple buffered logging — avoids va_start macro issues */
static void ilog(LogLevel lv, const char* fmt, ...) {
    if (lv > g_min_level) return;
    const char* L[] = {"E", "W", "I", "D", "V"};
    char ts[32];
    time_t now = time(NULL);
    struct tm* tm = localtime(&now);
    strftime(ts, sizeof(ts), "%m-%d %H:%M:%S", tm);

    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    fprintf(stderr, "[%s] [%s] [%s] %s\n", ts, L[lv], g_tag, buf);
    fflush(stderr);
    if (g_logf) {
        fprintf(g_logf, "[%s] [%s] [%s] %s\n", ts, L[lv], g_tag, buf);
        fflush(g_logf);
    }
}

#define LOGE(...) ilog(L_ERROR,   __VA_ARGS__)
#define LOGW(...) ilog(L_WARN,    __VA_ARGS__)
#define LOGI(...) ilog(L_INFO,    __VA_ARGS__)
#define LOGD(...) ilog(L_DEBUG,   __VA_ARGS__)
#define LOGV(...) ilog(L_VERBOSE, __VA_ARGS__)

/* ═══════════════════════════════════════════════════════════════
 *  Serial port helpers
 * ═══════════════════════════════════════════════════════════════ */

static speed_t baud_to_speed(int baud) {
    switch (baud) {
        case 460800: return B460800;
        case 115200: return B115200;
        case 57600:  return B57600;
        case 38400:  return B38400;
        case 19200:  return B19200;
        case 9600:   return B9600;
        case 4800:   return B4800;
        default:     return B9600;
    }
}

static bool set_serial_opts(int fd, int baud) {
    struct termios tio;
    if (tcgetattr(fd, &tio) != 0) {
        LOGE("tcgetattr failed: %s", strerror(errno));
        return false;
    }
    cfmakeraw(&tio);
    speed_t sp = baud_to_speed(baud);
    cfsetispeed(&tio, sp);
    cfsetospeed(&tio, sp);
    /* 8N1: CLOCAL=ignore modem, CREAD=enable receiver */
    tio.c_cflag = (tio.c_cflag & ~CSIZE) | CS8 | CLOCAL | CREAD;
    tio.c_iflag &= ~(IXON | IXOFF | IXANY);
    tio.c_oflag &= ~OPOST;
    tio.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    tio.c_cc[VMIN] = 0;
    tio.c_cc[VTIME] = 20;  /* 2 s timeout */
    if (tcsetattr(fd, TCSANOW, &tio) != 0) {
        LOGE("tcsetattr failed baud=%d: %s", baud, strerror(errno));
        return false;
    }
    tcflush(fd, TCIOFLUSH);
    return true;
}

/* ═══════════════════════════════════════════════════════════════
 *  GPS socket injection
 * ═══════════════════════════════════════════════════════════════ */

static int open_gps_socket(const char* path) {
    if (!path) return -1;
    int fd = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (fd < 0) { LOGV("socket failed %s: %s", path, strerror(errno)); return -1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        LOGV("connect %s failed: %s", path, strerror(errno));
        close(fd);
        return -1;
    }
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    LOGI("GPS socket connected: %s", path);
    return fd;
}

static int open_best_gps_socket(void) {
    for (int i = 0; GPS_SOCKETS[i]; i++) {
        int fd = open_gps_socket(GPS_SOCKETS[i]);
        if (fd >= 0) return fd;
    }
    return -1;
}

static bool send_nmea(int gps_fd, const char* nmea, int len) {
    if (gps_fd < 0 || !nmea || len <= 0) return false;
    ssize_t sent = send(gps_fd, nmea, len, MSG_DONTWAIT);
    if (sent < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
        LOGV("send GPS failed: %s", strerror(errno));
        return false;
    }
    return true;
}

/* ═══════════════════════════════════════════════════════════════
 *  USB device identification
 * ═══════════════════════════════════════════════════════════════ */

static bool read_usb_vidpid(const char* dev, char* vid_out, char* pid_out) {
    char path[256];
    vid_out[0] = pid_out[0] = 0;

    snprintf(path, sizeof(path), "/sys/class/tty/%s/device/idVendor", dev);
    FILE* f = fopen(path, "r");
    if (!f) return false;
    if (fgets(vid_out, 16, f)) {
        size_t n = strlen(vid_out);
        while (n > 0 && (vid_out[n-1] == '\r' || vid_out[n-1] == '\n')) {
            vid_out[--n] = 0;
        }
    }
    fclose(f);

    snprintf(path, sizeof(path), "/sys/class/tty/%s/device/idProduct", dev);
    f = fopen(path, "r");
    if (!f) return false;
    if (fgets(pid_out, 16, f)) {
        size_t n = strlen(pid_out);
        while (n > 0 && (pid_out[n-1] == '\r' || pid_out[n-1] == '\n')) {
            pid_out[--n] = 0;
        }
    }
    fclose(f);

    return vid_out[0] && pid_out[0];
}

static const UsbDevice* identify_device(const char* dev) {
    char vid[16] = {0}, pid[16] = {0};
    if (!read_usb_vidpid(dev, vid, pid)) return NULL;

    char vp[32];
    snprintf(vp, sizeof(vp), "%s:%s", vid, pid);
    LOGI("USB VID:PID = %s", vp);

    for (int i = 0; i < N_USB_DB; i++) {
        if (strcmp(vp, USB_DB[i].vidpid) == 0) {
            LOGI("Identified: %s", USB_DB[i].name);
            return &USB_DB[i];
        }
    }
    LOGW("Unknown USB device: %s", vp);
    return NULL;
}

/* ═══════════════════════════════════════════════════════════════
 *  NMEA helpers
 * ═══════════════════════════════════════════════════════════════ */

/* Validate XOR checksum: everything after $ up to (not including) * */
static bool nmea_valid_checksum(const char* sentence) {
    const char* star = strchr(sentence, '*');
    if (!star || star - sentence < 4) return true;  /* no checksum field */

    char recv_cs[3] = {0};
    if (star[1] && star[2]) {
        recv_cs[0] = star[1];
        recv_cs[1] = star[2];
    } else {
        return true;
    }

    uint8_t cs_xor = 0;
    const char* p = strchr(sentence, '$');
    if (!p) return true;
    p++;  /* skip $ */
    while (p < star) cs_xor ^= (uint8_t)(*p++);

    char calc[3];
    snprintf(calc, sizeof(calc), "%02X", (unsigned int)cs_xor);
    if (strcasecmp(recv_cs, calc) != 0) {
        LOGV("NMEA checksum mismatch: expect %s, got %.2s (%.40s...)", calc, recv_cs, sentence);
        return false;
    }
    return true;
}

/* Extract talker+type from $PREFIX,TYPE,... -> "PREFIXTYPE" */
static void nmea_talkertype(const char* s, char* out_type, size_t maxlen) {
    /* Find first comma */
    const char* comma = strchr(s, ',');
    if (!comma || comma - s < 5) { out_type[0] = 0; return; }
    size_t n = comma - s - 1;  /* skip leading $ */
    if (n > maxlen - 1) n = maxlen - 1;
    memcpy(out_type, s + 1, n);
    out_type[n] = 0;
}

/* ═══════════════════════════════════════════════════════════════
 *  Auto-detection
 * ═══════════════════════════════════════════════════════════════ */

/* Read one NMEA sentence from fd within timeout_sec. Returns buf or NULL. */
static bool read_nmea(int fd, char* buf, int bufsize, int timeout_sec) {
    fd_set rfds;
    struct timeval tv;
    char line[MAX_NMEA_LEN];
    int llen = 0;
    memset(line, 0, sizeof(line));

    time_t start = time(NULL);
    while (time(NULL) - start < timeout_sec) {
        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        int ret = select(fd + 1, &rfds, NULL, NULL, &tv);
        if (ret <= 0) continue;

        unsigned char c;
        int n = read(fd, &c, 1);
        if (n <= 0) continue;

        if (c == '\r' || c == '\n') {
            if (llen > 6 && line[0] == '$') {
                line[llen] = 0;
                /* Basic sanity: must look like NMEA */
                if (strncmp(line + 1, "GP", 2) == 0 ||
                    strncmp(line + 1, "GN", 2) == 0 ||
                    strncmp(line + 1, "GB", 2) == 0 ||
                    strncmp(line + 1, "GA", 2) == 0 ||
                    strncmp(line + 1, "GL", 2) == 0 ||
                    strncmp(line + 1, "PQ", 2) == 0) {
                    strncpy(buf, line, bufsize - 1);
                    buf[bufsize - 1] = 0;
                    return true;
                }
            }
            llen = 0;
            memset(line, 0, sizeof(line));
        } else if (llen < MAX_NMEA_LEN - 1 && isprint((unsigned char)c)) {
            line[llen++] = (char)c;
        }
    }
    return false;
}

static bool probe_device(const char* dev, int baud, char* out_nmea, int nmea_size) {
    int fd = open(dev, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) return false;
    if (!set_serial_opts(fd, baud)) { close(fd); return false; }

    /* Discard stale data */
    tcflush(fd, TCIOFLUSH);

    bool ok = read_nmea(fd, out_nmea, nmea_size, 3);
    close(fd);
    return ok;
}

/* Scan all candidate devices at all baud rates.
   Returns a newly-allocated device path string (caller frees), or NULL. */
static char* auto_detect_device_and_baud(int* baud_out) {
    const char* candidates[] = {
        "/dev/ttyACM0", "/dev/ttyACM1", "/dev/ttyACM2",
        "/dev/ttyUSB0", "/dev/ttyUSB1", "/dev/ttyUSB2",
        "/dev/ttyUSB3", "/dev/ttyUSB4", NULL
    };

    char nmea[MAX_NMEA_LEN];
    const UsbDevice* dev_info = NULL;
    char* result = NULL;
    int best_baud = 115200;

    for (int i = 0; candidates[i]; i++) {
        const char* dev = candidates[i];
        if (access(dev, R_OK | W_OK) != 0) continue;

        /* First try to identify by USB VID/PID */
        dev_info = identify_device(dev);
        if (dev_info) {
            best_baud = dev_info->default_baud;
            if (probe_device(dev, best_baud, nmea, sizeof(nmea))) {
                LOGI("Auto-detect: %s @ %d — %s", dev, best_baud, nmea);
                result = strdup(dev);
                *baud_out = best_baud;
                return result;
            }
            /* Known device but no data at default baud — try all */
        }

        /* Unknown device or known device needs baud detection */
        for (int b = 0; b < N_BAUDS; b++) {
            int baud = BAUD_RATES[b];
            if (probe_device(dev, baud, nmea, sizeof(nmea))) {
                LOGI("Auto-detect: %s @ %d — %s (found by sweep)",
                     dev, baud, nmea);
                if (!result) result = strdup(dev);
                if (!dev_info) *baud_out = baud;
                else *baud_out = best_baud;
                /* Prefer identified device; if equal, prefer higher baud */
                if (!dev_info || (dev_info && BAUD_RATES[b] >= best_baud)) {
                    *baud_out = baud;
                    return result;
                }
            }
        }
    }
    return result;
}

/* ═══════════════════════════════════════════════════════════════
 *  NMEA parsing — extract meaningful info
 * ═══════════════════════════════════════════════════════════════ */

/* Parse $--GGA and fill GgaInfo. Returns true on success. */
struct GgaInfo {
    bool  valid;
    int   quality;      /* 0=invalid, 1=GPS, 2=DGPS, 4=RTK Fixed, 5=RTK Float */
    int   num_sats;
    float hdop;
    float altitude;
    double lat, lon;
    char  lat_ns, lon_ew;

    GgaInfo() : valid(false), quality(0), num_sats(0),
                hdop(999), altitude(0), lat(0), lon(0),
                lat_ns('N'), lon_ew('E') {}
};

static bool parse_gga(const char* s, GgaInfo* out) {
    /* $--GGA,time,lat,NS,lon,EW,quality,ns,hdop,alt,M,geoid,M*cs */
    char buf[MAX_NMEA_LEN];
    strncpy(buf, s, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = 0;

    char* f[15];
    int nf = 0;
    f[nf++] = strtok(buf, ",");
    while (nf < 14 && (f[nf] = strtok(NULL, ",")) != NULL) nf++;

    if (nf < 10) return false;

    /* Check this is GGA */
    size_t typelen = strlen(f[0]);
    if (typelen < 6) return false;
    const char* t = f[0] + typelen - 3;
    if (strncmp(t, "GGA", 3) != 0) return false;

    out->valid = true;
    if (nf > 6 && f[6][0]) out->quality = atoi(f[6]);
    if (nf > 7 && f[7][0]) out->num_sats = atoi(f[7]);
    if (nf > 8 && f[8][0]) out->hdop = (float)atof(f[8]);
    if (nf > 9 && f[9][0]) out->altitude = (float)atof(f[9]);

    /* Latitude ddmm.mmmm -> dd.dddd */
    if (nf > 1 && strlen(f[1]) >= 6) {
        double deg = floor(atof(f[1]) / 100.0);
        double min = atof(f[1]) - deg * 100.0;
        out->lat = deg + min / 60.0;
    }
    if (nf > 2 && f[2][0]) out->lat_ns = f[2][0];

    /* Longitude dddmm.mmmm -> ddd.dddd */
    if (nf > 3 && strlen(f[3]) >= 6) {
        double deg = floor(atof(f[3]) / 100.0);
        double min = atof(f[3]) - deg * 100.0;
        out->lon = deg + min / 60.0;
    }
    if (nf > 4 && f[4][0]) out->lon_ew = f[4][0];

    return true;
}

/* Parse $--RMC */
struct RmcInfo {
    bool  valid;
    bool  data_ok;       /* A=valid */
    double speed_knots;
    double track_angle;

    RmcInfo() : valid(false), data_ok(false), speed_knots(0), track_angle(0) {}
};

static bool parse_rmc(const char* s, RmcInfo* out) {
    char buf[MAX_NMEA_LEN];
    strncpy(buf, s, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = 0;

    char* f[12];
    int nf = 0;
    f[nf++] = strtok(buf, ",");
    while (nf < 11 && (f[nf] = strtok(NULL, ",")) != NULL) nf++;

    if (nf < 9) return false;
    size_t typelen = strlen(f[0]);
    if (typelen < 6) return false;
    const char* t = f[0] + typelen - 3;
    if (strncmp(t, "RMC", 3) != 0) return false;

    out->valid = true;
    out->data_ok = (nf > 1 && f[1][0] == 'A');
    if (nf > 7 && f[7][0]) out->speed_knots = atof(f[7]);
    if (nf > 8 && f[8][0]) out->track_angle = atof(f[8]);
    return true;
}

/* Parse $--GSA */
struct GsaInfo {
    bool valid;
    char mode;           /* A=auto, M=manual */
    int  fix_type;       /* 1=none, 2=2D, 3=3D */
    std::vector<int> sats;
    float pdop, hdop, vdop;

    GsaInfo() : valid(false), mode('A'), fix_type(0),
                pdop(999), hdop(999), vdop(999) {}
};

static bool parse_gsa(const char* s, GsaInfo* out) {
    char buf[MAX_NMEA_LEN];
    strncpy(buf, s, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = 0;

    char* f[18];
    int nf = 0;
    f[nf++] = strtok(buf, ",");
    while (nf < 17 && (f[nf] = strtok(NULL, ",")) != NULL) nf++;

    if (nf < 17) return false;
    size_t typelen = strlen(f[0]);
    if (typelen < 6) return false;
    const char* t = f[0] + typelen - 3;
    if (strncmp(t, "GSA", 3) != 0) return false;

    out->valid = true;
    if (f[1][0]) out->mode = f[1][0];
    if (f[2][0]) out->fix_type = atoi(f[2]);
    for (int i = 3; i <= 14; i++) {
        if (nf > i && f[i][0] && isdigit((unsigned char)f[i][0])) {
            out->sats.push_back(atoi(f[i]));
        }
    }
    if (nf > 15 && f[15][0]) out->pdop = (float)atof(f[15]);
    if (nf > 16 && f[16][0]) out->hdop = (float)atof(f[16]);
    if (nf > 17 && f[17][0]) out->vdop = (float)atof(f[17]);
    return true;
}

/* ═══════════════════════════════════════════════════════════════
 *  Status printing
 * ═══════════════════════════════════════════════════════════════ */

struct Stats {
    uint64_t rx_bytes = 0;
    uint64_t tx_bytes = 0;
    uint64_t checksum_err = 0;
    uint64_t gga_total = 0;
    uint64_t gga_valid  = 0;
    uint64_t rmc_total  = 0;
    uint64_t gsa_total  = 0;
    uint64_t gsv_total  = 0;
    time_t   start_time = 0;
    int      cur_baud   = 0;

    Stats() : start_time(time(NULL)) {}
};

static const char* quality_str(int q) {
    switch (q) {
        case 1: return "GPS (SPS)";
        case 2: return "DGPS";
        case 4: return "RTK Fixed";
        case 5: return "RTK Float";
        default: return "No Fix";
    }
}

static void print_status(const GgaInfo& gga, const GsaInfo& gsa,
                         const RmcInfo& rmc, const Stats& st) {
    time_t elapsed = time(NULL) - st.start_time;
    int min = (int)(elapsed / 60);
    int sec = (int)(elapsed % 60);

    LOGI("========================================");
    LOGI("  GPS Status  [%02d:%02d]", min, sec);
    LOGI("========================================");
    LOGI("  Baud: %d  Rx:%llu  Tx:%llu  CS-Err:%llu",
         st.cur_baud,
         (unsigned long long)st.rx_bytes,
         (unsigned long long)st.tx_bytes,
         (unsigned long long)st.checksum_err);
    LOGI("----------------------------------------");
    LOGI("  Quality:  %s", quality_str(gga.quality));
    LOGI("  Satellites: %d", gga.num_sats);
    LOGI("  HDOP:     %.1f", gga.hdop);
    LOGI("  Altitude: %.1f m", gga.altitude);
    if (gga.valid) {
        LOGI("  Position: %.6f%c, %.6f%c",
             gga.lat, gga.lat_ns, gga.lon, gga.lon_ew);
    }
    if (rmc.valid) {
        double kmh = rmc.speed_knots * 1.852;
        LOGI("  Speed:    %.1f km/h  Track: %.1f deg", kmh, rmc.track_angle);
    }
    if (gsa.valid) {
        LOGI("  Fix:      %s  PDOP:%.1f  HDOP:%.1f  VDOP:%.1f",
             (gsa.fix_type == 3 ? "3D" : gsa.fix_type == 2 ? "2D" : "None"),
             gsa.pdop, gsa.hdop, gsa.vdop);
        if (!gsa.sats.empty()) {
            char ids[128] = {0};
            int pos = 0;
            for (size_t i = 0; i < gsa.sats.size() && i < 16; i++) {
                pos += snprintf(ids + pos, sizeof(ids) - pos - 1, "%d ", gsa.sats[i]);
            }
            LOGI("  Sats:     %s", ids);
        }
    }
    LOGI("  NMEA: GGA=%llu(v=%llu) RMC=%llu GSA=%llu GSV=%llu",
         (unsigned long long)st.gga_total,
         (unsigned long long)st.gga_valid,
         (unsigned long long)st.rmc_total,
         (unsigned long long)st.gsa_total,
         (unsigned long long)st.gsv_total);
    LOGI("========================================");
}

/* ═══════════════════════════════════════════════════════════════
 *  Main
 * ═══════════════════════════════════════════════════════════════ */

static volatile sig_atomic_t g_running = 1;

static void signal_handler(int) {
    g_running = 0;
}

static void print_usage(const char* prog) {
    fprintf(stderr,
        "\n"
        "  usb_gps_bridge v3 — NMEA GNSS Bridge\n"
        "\n"
        "  Usage: %s [options]\n"
        "\n"
        "  Options:\n"
        "    -d <dev>     Serial device (default: auto-detect)\n"
        "    -b <baud>    Baud rate (default: 460800)\n"
        "    -a           Auto-detect device AND baud rate (default)\n"
        "    -D           Daemon mode\n"
        "    -w <sec>     Warm-up wait for first fix (default: 60)\n"
        "    -l <path>    Log file path\n"
        "    -L <level>   Log level: ERROR|WARN|INFO|DEBUG|VERBOSE (default: INFO)\n"
        "    -h           Show this help\n"
        "\n"
        "  Example:\n"
        "    %s -a                    # Full auto-detect\n"
        "    %s -d /dev/ttyACM0 -b 460800  # Manual\n"
        "\n",
        prog, prog, prog);
}

int main(int argc, char** argv) {
    const char* device = NULL;
    int baud = 460800;
    bool auto_detect = true;
    bool daemon = false;
    int warm_up = 60;
    const char* log_path = NULL;
    const char* log_level = "INFO";

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-d") && i + 1 < argc) {
            device = argv[++i];
            auto_detect = false;
        } else if (!strcmp(argv[i], "-b") && i + 1 < argc) {
            baud = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-a")) {
            auto_detect = true;
        } else if (!strcmp(argv[i], "-D")) {
            daemon = true;
        } else if (!strcmp(argv[i], "-w") && i + 1 < argc) {
            warm_up = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-l") && i + 1 < argc) {
            log_path = argv[++i];
        } else if (!strcmp(argv[i], "-L") && i + 1 < argc) {
            log_level = argv[++i];
        } else {
            print_usage(argv[0]);
            return 1;
        }
    }

    init_log(log_path);
    set_level(log_level);

    LOGI("========================================");
    LOGI("  USB GPS Bridge v3 — Full GNSS");
    LOGI("  UN982 / UM621A / CH343P / CP210x");
    LOGI("========================================");

    /* ── Auto-detect ── */
    if (auto_detect || !device) {
        LOGI("[AUTO] Scanning for USB GPS modules...");
        char* detected = auto_detect_device_and_baud(&baud);
        if (detected) {
            device = detected;
            LOGI("[AUTO] Found: %s @ %d baud", device, baud);

            const UsbDevice* info = identify_device(device);
            if (info) {
                LOGI("         Device: %s  Driver: %s", info->name, info->driver);
            }
        } else {
            LOGE("[AUTO] No GPS module found!");
            LOGE("       Try: -d /dev/ttyACM0 -b 460800");
            return 1;
        }
    } else {
        LOGI("Device: %s @ %d baud (manual)", device, baud);

        const UsbDevice* info = identify_device(device);
        if (info) {
            LOGI("Device: %s, default baud: %d", info->name, info->default_baud);
        }
    }

    /* ── Open serial ── */
    int serial_fd = open(device, O_RDWR | O_NOCTTY);
    if (serial_fd < 0) {
        LOGE("Cannot open %s: %s", device, strerror(errno));
        return 1;
    }
    if (!set_serial_opts(serial_fd, baud)) {
        close(serial_fd);
        return 1;
    }
    LOGI("Serial fd=%d opened", serial_fd);

    /* ── Open GPS socket ── */
    int gps_fd = open_best_gps_socket();
    if (gps_fd < 0) {
        LOGW("Cannot connect to GPS socket (need root or SELinux)");
    } else {
        LOGI("GPS socket fd=%d connected", gps_fd);
    }

    /* ── Daemonize via fork ── */
    if (daemon) {
        LOGI("Daemonizing...");
        int pid = fork();
        if (pid < 0) {
            LOGE("fork() failed: %s", strerror(errno));
        } else if (pid > 0) {
            /* Parent exits */
            _exit(0);
        }
        /* Child continues as daemon */
        setsid();
        chdir("/");
        close(STDIN_FILENO);
        close(STDOUT_FILENO);
        close(STDERR_FILENO);
        LOGI("Daemonized, PID=%d", (int)getpid());
    }

    /* ── Signal handling ── */
    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    /* ── Main loop ── */
    LOGI("NMEA bridge running. warm_up=%ds. PID=%d", warm_up, (int)getpid());
    LOGI("(Press Ctrl+C to stop)");

    Stats stats;
    stats.cur_baud = baud;

    char line[MAX_NMEA_LEN];
    int llen = 0;
    memset(line, 0, sizeof(line));

    GgaInfo last_gga;
    GsaInfo last_gsa;
    RmcInfo last_rmc;

    time_t last_status = time(NULL);
    time_t start_time = time(NULL);
    int warm_up_done = 0;

    while (g_running) {
        fd_set rfds;
        struct timeval tv;
        FD_ZERO(&rfds);
        FD_SET(serial_fd, &rfds);
        tv.tv_sec = 0;
        tv.tv_usec = 500000;  /* 500ms poll */

        int ret = select(serial_fd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR) continue;
            LOGE("select failed: %s", strerror(errno));
            sleep(1);
            continue;
        }
        if (ret == 0) {
            /* Periodic health report */
            time_t now = time(NULL);
            if (now - last_status >= 30) {
                print_status(last_gga, last_gsa, last_rmc, stats);
                last_status = now;
            }
            /* Check warm-up */
            if (!warm_up_done && (now - start_time) >= warm_up) {
                LOGI("Warm-up complete. GPS should be ready.");
                warm_up_done = 1;
            }
            continue;
        }

        unsigned char c;
        int n = read(serial_fd, &c, 1);
        if (n <= 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                LOGE("Serial read error: %s", strerror(errno));
            }
            continue;
        }

        stats.rx_bytes += n;

        /* Accumulate line */
        if (c == '\r') continue;  /* skip CR */
        if (c == '\n') {
            /* Process complete line */
            if (llen > 5 && line[0] == '$') {
                line[llen] = 0;

                /* Extract type for stats */
                char tbuf[32];
                nmea_talkertype(line, tbuf, sizeof(tbuf));
                if (strstr(tbuf, "GGA")) stats.gga_total++;
                else if (strstr(tbuf, "RMC")) stats.rmc_total++;
                else if (strstr(tbuf, "GSA")) stats.gsa_total++;
                else if (strstr(tbuf, "GSV")) stats.gsv_total++;

                /* Checksum */
                if (!nmea_valid_checksum(line)) {
                    stats.checksum_err++;
                    llen = 0; memset(line, 0, sizeof(line));
                    continue;
                }

                /* Parse key sentences */
                GgaInfo gga;
                GsaInfo gsa;
                RmcInfo rmc;
                if (parse_gga(line, &gga)) {
                    last_gga = gga;
                    if (gga.quality > 0) stats.gga_valid++;
                }
                if (parse_gsa(line, &gsa)) last_gsa = gsa;
                if (parse_rmc(line, &rmc)) last_rmc = rmc;

                /* Inject to GPS socket */
                if (gps_fd >= 0) {
                    char pkt[INJECT_BUF_SIZE];
                    int ilen = snprintf(pkt, sizeof(pkt), "%s\r\n", line);
                    if (send_nmea(gps_fd, pkt, ilen)) {
                        stats.tx_bytes += ilen;
                    }
                }

                /* Verbose */
                if (stats.gga_total % 20 == 1) {
                    LOGV("NMEA[%llu]: %.60s",
                         (unsigned long long)stats.gga_total, line);
                }
            }
            llen = 0;
            memset(line, 0, sizeof(line));

        } else if (llen < MAX_NMEA_LEN - 1 && isprint((unsigned char)c)) {
            line[llen++] = (char)c;
        } else if (c == '$') {
            /* New sentence */
            llen = 1;
            line[0] = '$';
        }
    }

    LOGI("Shutting down...");
    if (serial_fd >= 0) close(serial_fd);
    if (gps_fd >= 0)    close(gps_fd);
    if (g_logf)         fclose(g_logf);

    LOGI("GPS Bridge stopped.");
    return 0;
}
