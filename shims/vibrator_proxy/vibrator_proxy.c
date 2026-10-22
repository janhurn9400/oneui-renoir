/*
 * oneui-renoir: vibrator proxy for Samsung's framework on renoir.
 *
 * renoir's vibrator HAL (Xiaomi, AIDL android.hardware.vibrator V1) is registered as IVibrator/vibratorfeature, so
 * One UI finds no IVibrator/default and has no vibration. Registering Xiaomi's HAL as default is not enough:
 * Samsung's libvibratorservice (AidlHalWrapper::getSehHal) takes the HAL binder's extension as its own
 * vendor.samsung.hardware.vibrator.ISehVibrator and dereferences it unchecked (boot 5: system_server SIGSEGV in
 * supportsHapticEngine with Xiaomi's HAL as default).
 *
 * This process registers IVibrator/default as a pass-through proxy: every IVibrator transaction is forwarded as is
 * (interface token re-written, data and binder objects copied with AParcel_appendFrom) to Xiaomi's
 * IVibrator/vibratorfeature and the reply copied back. Its binder extension is a minimal ISehVibrator (V5, hash from
 * Samsung's vendor.samsung.hardware.vibrator-V5-ndk.so) that reports its version/hash and answers every Samsung
 * call with EX_UNSUPPORTED_OPERATION, i.e. "no haptic engine". Own code; Xiaomi's and Samsung's files untouched.
 */
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <android/binder_ibinder.h>
#include <android/binder_parcel.h>
#include <android/binder_status.h>
#include <android/log.h>

#define TAG "vibrator_proxy"
#define LOG(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)

#define VIB_DESC "android.hardware.vibrator.IVibrator"
#define SEH_DESC "vendor.samsung.hardware.vibrator.ISehVibrator"
#define SEH_VERSION 5
#define SEH_HASH "41c6b1795252a8a498c41ea9d7baed6192bd5eaa"
#define CODE_GET_INTERFACE_VERSION 16777215   /* FIRST_CALL_TRANSACTION + 16777214 */
#define CODE_GET_INTERFACE_HASH 16777214      /* FIRST_CALL_TRANSACTION + 16777213 */

/* platform (non-NDK) libbinder_ndk API, see frameworks/native/libs/binder/ndk/include_platform */
AIBinder *AServiceManager_waitForService(const char *instance);
binder_exception_t AServiceManager_addService(AIBinder *binder, const char *instance);
void AIBinder_markVintfStability(AIBinder *binder);
binder_status_t AIBinder_setExtension(AIBinder *binder, AIBinder *ext);
bool ABinderProcess_setThreadPoolMaxThreadCount(uint32_t numThreads);
void ABinderProcess_startThreadPool(void);
void ABinderProcess_joinThreadPool(void);

static AIBinder *g_target;   /* Xiaomi's IVibrator/vibratorfeature */

static void *on_create(void *args) { return args; }
static void on_destroy(void *data) { (void)data; }

static binder_status_t vib_transact(AIBinder *self, transaction_code_t code, const AParcel *in, AParcel *out) {
    (void)self;
    AParcel *fwd = NULL, *reply = NULL;
    binder_status_t st = AIBinder_prepareTransaction(g_target, &fwd);   /* writes the IVibrator interface token */
    if (st != STATUS_OK) return st;
    int32_t pos = AParcel_getDataPosition(in);                          /* NDK already consumed the token */
    st = AParcel_appendFrom(in, fwd, pos, AParcel_getDataSize(in) - pos);
    if (st != STATUS_OK) { AParcel_delete(fwd); return st; }
    st = AIBinder_transact(g_target, code, &fwd, &reply, 0);            /* consumes fwd */
    if (st != STATUS_OK) return st;
    st = AParcel_appendFrom(reply, out, 0, AParcel_getDataSize(reply)); /* status header + results as is */
    AParcel_delete(reply);
    return st;
}

static binder_status_t seh_transact(AIBinder *self, transaction_code_t code, const AParcel *in, AParcel *out) {
    (void)self; (void)in;
    AStatus *ok = AStatus_newOk();
    if (code == CODE_GET_INTERFACE_VERSION) {
        AParcel_writeStatusHeader(out, ok); AStatus_delete(ok);
        return AParcel_writeInt32(out, SEH_VERSION);
    }
    if (code == CODE_GET_INTERFACE_HASH) {
        AParcel_writeStatusHeader(out, ok); AStatus_delete(ok);
        return AParcel_writeString(out, SEH_HASH, sizeof(SEH_HASH) - 1);
    }
    AStatus_delete(ok);
    AStatus *unsupported = AStatus_fromExceptionCode(EX_UNSUPPORTED_OPERATION);
    binder_status_t st = AParcel_writeStatusHeader(out, unsupported);
    AStatus_delete(unsupported);
    return st;
}

static void on_target_died(void *cookie) {
    (void)cookie;
    LOG("Xiaomi vibrator HAL died, exiting (init restarts the proxy)");
    _exit(1);
}

int main(void) {
    ABinderProcess_setThreadPoolMaxThreadCount(4);
    ABinderProcess_startThreadPool();

    g_target = AServiceManager_waitForService(VIB_DESC "/vibratorfeature");
    if (!g_target) { LOG("no " VIB_DESC "/vibratorfeature"); return 1; }
    AIBinder_Class *vib_class = AIBinder_Class_define(VIB_DESC, on_create, on_destroy, vib_transact);
    AIBinder_Class *seh_class = AIBinder_Class_define(SEH_DESC, on_create, on_destroy, seh_transact);
    if (!AIBinder_associateClass(g_target, vib_class)) { LOG("vibratorfeature is not an " VIB_DESC); return 1; }
    AIBinder_DeathRecipient *dr = AIBinder_DeathRecipient_new(on_target_died);
    AIBinder_linkToDeath(g_target, dr, NULL);

    AIBinder *seh = AIBinder_new(seh_class, NULL);
    AIBinder *proxy = AIBinder_new(vib_class, NULL);
    AIBinder_markVintfStability(seh);
    AIBinder_markVintfStability(proxy);
    if (AIBinder_setExtension(proxy, seh) != STATUS_OK) { LOG("setExtension failed"); return 1; }
    binder_exception_t e = AServiceManager_addService(proxy, VIB_DESC "/default");
    if (e != EX_NONE) { LOG("addService " VIB_DESC "/default failed: %d", e); return 1; }
    LOG(VIB_DESC "/default -> vibratorfeature, ISehVibrator stub v%d", SEH_VERSION);
    ABinderProcess_joinThreadPool();
    return 0;
}
