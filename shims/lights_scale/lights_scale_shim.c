/*
 * oneui-renoir: LD_PRELOAD shim for renoir's lights HAL (android.hardware.lights-service.qti -> lights.qcom.so).
 *
 * lights.qcom.so picks its backlight math from ro.product.manufacturer (verified in its set_light_backlight):
 *  - "Xiaomi": MIUI path, the low 12 bits of the colour already are the panel level (color & 0xfff)
 *  - otherwise: AOSP path, level = rgb_to_brightness(color), scaled linearly per node ((v+1) * factor - 1)
 * Under One UI ro.product.manufacturer is inherited from the Xiaomi vendor, but Samsung passes an AOSP colour
 * (0xFFvvvvvv): the panel got (v * 257) & 0xfff -> zig-zag brightness, black at the low end (boots 20/21; measured
 * brightness_clone <- 257, 2570, 3614 for levels 1, 10, 30). This shim answers "samsung" (what One UI reports on
 * Samsung devices) for that one property inside the lights HAL only; camera, DRM, display keep seeing "Xiaomi".
 * property_get is reached through lights.qcom.so's PLT, so the preloaded definition wins. It is implemented here
 * on libc's __system_property_get (like libcutils does): libcutils is only loaded later with the module, so
 * dlsym(RTLD_NEXT) found nothing and the service crashed on a null call (boot 23).
 */
#include <string.h>
#include <sys/system_properties.h>
#include <android/log.h>

#define TAG "lights_scale_shim"

int property_get(const char *key, char *value, const char *default_value) {
    if (key && !strcmp(key, "ro.product.manufacturer")) {
        strcpy(value, "samsung");
        __android_log_print(ANDROID_LOG_DEBUG, TAG, "ro.product.manufacturer -> samsung (AOSP backlight path)");
        return (int)strlen(value);
    }
    int len = __system_property_get(key, value);
    if (len == 0 && default_value) {
        len = (int)strlen(default_value);
        if (len >= PROP_VALUE_MAX) len = PROP_VALUE_MAX - 1;
        memcpy(value, default_value, len);
        value[len] = 0;
    }
    return len;
}
