/*
 * oneui-renoir: LD_PRELOAD shim for Xiaomi's mfp-daemon (renoir's FPC1540 fingerprint HAL).
 *
 * Samsung's framework always sends enroll(..., timeoutSec = 0, ...) to the HIDL 2.1 fingerprint HAL: its own HALs
 * read 0 as "no limit". renoir's fingerprint.fpc.so turns the timeout into the poll() wait for the finger
 * (timeout_sec * 1000 ms), so 0 fails at once with FPC_ERROR_TIMEDOUT. AOSP passes 60 s; do the same when 0 arrives.
 *
 * fpc_enroll(device, hat, hat_len, gid, timeout_sec) is exported by fingerprint.fpc.so and reached through its PLT,
 * so a preloaded definition wins. Nothing of Xiaomi's files is modified.
 */
#include <dlfcn.h>
#include <stdint.h>
#include <android/log.h>

#define TAG "fpc_timeout_shim"
#define FPC_LIB "/vendor/lib64/hw/fingerprint.fpc.so"
#define DEFAULT_TIMEOUT_SEC 60

typedef int (*fpc_enroll_fn)(void *dev, const uint8_t *hat, uint32_t hat_len, uint32_t gid, uint32_t timeout_sec);

static fpc_enroll_fn real_fpc_enroll(void) {
    static fpc_enroll_fn fn;
    if (!fn) {
        /* the module is dlopen()ed locally by libhardware: look it up in that library, RTLD_NEXT as fallback */
        void *h = dlopen(FPC_LIB, RTLD_NOW | RTLD_NOLOAD);
        if (h) fn = (fpc_enroll_fn)dlsym(h, "fpc_enroll");
        if (!fn) fn = (fpc_enroll_fn)dlsym(RTLD_NEXT, "fpc_enroll");
        if (!fn) __android_log_print(ANDROID_LOG_ERROR, TAG, "real fpc_enroll not found: %s", dlerror());
    }
    return fn;
}

int fpc_enroll(void *dev, const uint8_t *hat, uint32_t hat_len, uint32_t gid, uint32_t timeout_sec) {
    fpc_enroll_fn fn = real_fpc_enroll();
    if (!fn) return -1;
    if (timeout_sec == 0) {
        __android_log_print(ANDROID_LOG_INFO, TAG, "enroll timeout 0 -> %d s", DEFAULT_TIMEOUT_SEC);
        timeout_sec = DEFAULT_TIMEOUT_SEC;
    }
    return fn(dev, hat, hat_len, gid, timeout_sec);
}
