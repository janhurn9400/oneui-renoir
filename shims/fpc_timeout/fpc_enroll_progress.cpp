/*
 * oneui-renoir: enrolment progress for Samsung's UI (part of libfpc_timeout_shim.so, preloaded into mfp-daemon).
 *
 * renoir's FPC HAL reports "remaining" as touches left (25, 24 ... 0 for 26 touches). Samsung's enrol UI reads it as
 * percent left: it started at ~75 % and filled 1 % per touch, the progress circle barely moved (boot 18). Report
 * remaining * 100 / total instead, total being the first remaining + 1 of an enrolment.
 *
 * mfp-daemon calls BpHwBiometricsFingerprintClientCallback::onEnrollResult, which tail-calls the exported static
 * _hidl_onEnrollResult through the PLT of android.hardware.biometrics.fingerprint@2.1.so, so a preloaded definition
 * wins. It returns hardware::Return<void> (non-trivial -> returned through a hidden pointer): RetVoid below is never
 * constructed here, `return real(...)` hands the caller's result slot straight through (guaranteed copy elision).
 */
#include <dlfcn.h>
#include <stdint.h>
#include <android/log.h>

#define TAG "fpc_timeout_shim"
#define SYM "_ZN7android8hardware10biometrics11fingerprint4V2_139BpHwBiometricsFingerprintClientCallback20" \
            "_hidl_onEnrollResultEPNS0_10IInterfaceEPNS0_7details16HidlInstrumentorEmjjj"

struct RetVoid {               // stands in for android::hardware::Return<void>
    RetVoid(const RetVoid &);  // declared only: makes the type non-trivial, so the ABI matches; never called
    ~RetVoid();
    char opaque[64];
};

#pragma clang diagnostic ignored "-Wreturn-type-c-linkage"   // C linkage only to pin the mangled name

typedef RetVoid (*enroll_result_fn)(void *iface, void *instr, uint64_t dev, uint32_t fid, uint32_t gid, uint32_t rem);

extern "C" RetVoid hidl_onEnrollResult(void *iface, void *instr, uint64_t dev, uint32_t fid, uint32_t gid,
                                       uint32_t rem) __asm__(SYM);

extern "C" RetVoid hidl_onEnrollResult(void *iface, void *instr, uint64_t dev, uint32_t fid, uint32_t gid,
                                       uint32_t rem) {
    static enroll_result_fn real;
    static uint32_t total, last;
    if (!real) real = (enroll_result_fn)dlsym(RTLD_NEXT, SYM);
    if (rem > 0) {
        if (total == 0 || rem >= last) total = rem + 1;   // a new enrolment starts (or a repeat of the first step)
        last = rem;
        uint32_t pct = rem * 100 / total;
        if (pct == 0) pct = 1;                            // only the final 0 may say "done"
        __android_log_print(ANDROID_LOG_DEBUG, TAG, "enroll remaining %u/%u -> %u%%", rem, total, pct);
        rem = pct;
    } else {
        total = 0;
    }
    return real(iface, instr, dev, fid, gid, rem);
}
