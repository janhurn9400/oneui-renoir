/*
 * oneui-renoir: register TrebleDroid's system-side Bluetooth audio provider (sysbta) also as ".../default".
 *
 * AOSP's Bluetooth stack uses IBluetoothAudioProviderFactory/sysbta when persist.bluetooth.system_audio_hal.enabled
 * is set; Samsung's stack has no such switch and only looks for ".../default" (renoir's vendor has no AIDL provider,
 * only HIDL bluetooth.audio@2.0 -> the stack aborted as soon as A2DP audio started). servicemanager stores binder
 * references, so the sysbta object can simply be added a second time under the default name. Own code; the
 * TrebleDroid binary stays unmodified.
 */
#include <android/binder_ibinder.h>
#include <android/binder_status.h>
#include <android/log.h>

/* platform (non-NDK) libbinder_ndk API, see frameworks/native/libs/binder/ndk/include_platform */
AIBinder *AServiceManager_waitForService(const char *instance);
binder_exception_t AServiceManager_addService(AIBinder *binder, const char *instance);
bool ABinderProcess_setThreadPoolMaxThreadCount(uint32_t numThreads);
void ABinderProcess_joinThreadPool(void);

#define TAG "btaudio_alias"
#define FACTORY "android.hardware.bluetooth.audio.IBluetoothAudioProviderFactory"

int main(void) {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    AIBinder *b = AServiceManager_waitForService(FACTORY "/sysbta");
    if (!b) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "%s/sysbta not available", FACTORY);
        return 1;
    }
    binder_exception_t e = AServiceManager_addService(b, FACTORY "/default");
    if (e != EX_NONE) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "addService %s/default failed: %d", FACTORY, e);
        return 1;
    }
    __android_log_print(ANDROID_LOG_INFO, TAG, "%s/default -> sysbta", FACTORY);
    ABinderProcess_joinThreadPool();   /* stay alive with the sysbta service (restarted together, see rc) */
    return 0;
}
