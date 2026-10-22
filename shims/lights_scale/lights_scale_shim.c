/*
 * oneui-renoir: LD_PRELOAD shim for renoir's lights HAL (android.hardware.lights-service.qti -> lights.qcom.so).
 *
 * Under One UI the backlight values reach the panel as (brightness * 257) & 0x7ff: a 0..255 level is scaled to
 * 16 bit somewhere in Xiaomi's chain and renoir's panel (max_brightness 2047) keeps only the low 11 bits. Moving the
 * slider zig-zagged between dark and bright, small values were black (boot 20/21: Backlight2SlpiNotifier showed
 * 198 -> 1734, 195 -> 963, 192 -> 192, 183 -> 1975; 255 -> 2047). Every value written to a backlight node is
 * therefore taken as 0..65535 and rescaled to 0..2047 (anything above 0 stays at least 1, never "off"). Values of
 * 1..7 * 257 are <= 2047 too, so a range check could not tell the scales apart. Xiaomi's files are not modified.
 *
 * lights.qcom.so writes through the fortified __open_2/__write_chk (and plain open/write as fallback), all reached
 * through its PLT, so preloaded definitions win.
 */
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <android/log.h>

#define TAG "lights_scale_shim"
#define PANEL_MAX 2047
#define SRC_MAX 65535

static unsigned long long tracked;   /* bit set of fds (< 64) that point at a backlight brightness node */
static char names[64][96];          /* path per tracked fd, for the log */
#define OBSERVE_ONLY 1               /* boot 22: rescaling both nodes made the panel almost black; measure first */

static int is_backlight(const char *path) {
    return path && (strstr(path, "backlight/brightness") || strstr(path, "-backlight/brightness") ||
                    strstr(path, "brightness_clone"));
}

static void track(int fd, const char *path) {
    if (fd < 0 || fd >= 64) return;
    if (is_backlight(path)) { tracked |= 1ULL << fd; snprintf(names[fd], sizeof(names[fd]), "%s", path); }
    else tracked &= ~(1ULL << fd);
}

static int (*real_open_2)(const char *, int);
static int (*real_open)(const char *, int, ...);
static ssize_t (*real_write_chk)(int, const void *, size_t, size_t);
static ssize_t (*real_write)(int, const void *, size_t);

int __open_2(const char *path, int flags) {
    if (!real_open_2) real_open_2 = dlsym(RTLD_NEXT, "__open_2");
    int fd = real_open_2(path, flags);
    track(fd, path);
    return fd;
}

int open(const char *path, int flags, ...) {
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    int mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    int fd = real_open(path, flags, mode);
    track(fd, path);
    return fd;
}

/* returns a replacement text in out (or NULL to keep buf) */
static const char *rescale(int fd, const void *buf, size_t count, char *out, size_t outlen) {
    if (fd < 0 || fd >= 64 || !(tracked & (1ULL << fd)) || count == 0 || count >= 32) return NULL;
    char tmp[32]; memcpy(tmp, buf, count); tmp[count] = 0;
    char *end; long v = strtol(tmp, &end, 10);
    if (end == tmp || v <= 0) return NULL;
    if (OBSERVE_ONLY) { __android_log_print(ANDROID_LOG_DEBUG, TAG, "%s <- %ld", names[fd], v); return NULL; }
    if (v > SRC_MAX) v = SRC_MAX;
    long s = (v * PANEL_MAX + SRC_MAX / 2) / SRC_MAX;
    if (s < 1) s = 1;
    snprintf(out, outlen, "%ld", s);
    __android_log_print(ANDROID_LOG_DEBUG, TAG, "backlight %ld -> %ld", v, s);
    return out;
}

ssize_t __write_chk(int fd, const void *buf, size_t count, size_t buflen) {
    if (!real_write_chk) real_write_chk = dlsym(RTLD_NEXT, "__write_chk");
    char out[32]; const char *r = rescale(fd, buf, count, out, sizeof(out));
    if (!r) return real_write_chk(fd, buf, count, buflen);
    ssize_t n = real_write_chk(fd, r, strlen(r), sizeof(out));
    return n < 0 ? n : (ssize_t)count;   /* the caller checks for its own length */
}

ssize_t write(int fd, const void *buf, size_t count) {
    if (!real_write) real_write = dlsym(RTLD_NEXT, "write");
    char out[32]; const char *r = rescale(fd, buf, count, out, sizeof(out));
    if (!r) return real_write(fd, buf, count);
    ssize_t n = real_write(fd, r, strlen(r));
    return n < 0 ? n : (ssize_t)count;
}
