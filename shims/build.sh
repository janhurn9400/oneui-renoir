#!/usr/bin/env bash
# Build our shims with NDK r27c (NDK=<dir>, default work/tools-dl/android-ndk-r27c) -> input/shims/ (committed, so a
# ROM build needs no NDK). Run it after changing shims/; macOS or Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NDK=${NDK:-$ROOT/work/tools-dl/android-ndk-r27c}
CC=$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/aarch64-linux-android30-clang | head -1)
"${CC}++" -shared -fPIC -O2 -Wall -Werror -fno-exceptions -fno-rtti -nostdlib++ \
  -o "$ROOT/input/shims/libfpc_timeout_shim.so" \
  -x c "$ROOT/shims/fpc_timeout/fpc_timeout_shim.c" -x c++ "$ROOT/shims/fpc_timeout/fpc_enroll_progress.cpp" -ldl -llog
echo "built input/shims/libfpc_timeout_shim.so"
# Link-only libbinder_ndk.so with the platform (non-NDK) symbols too, e.g. AServiceManager_addService, in the version
# nodes the phone's library uses (shims/stubs/libbinder_ndk.syms)
STUBS=$ROOT/work/input/stubs; mkdir -p "$STUBS"
grep -v '^#' "$ROOT/shims/stubs/libbinder_ndk.syms" | awk -F@ '{print "void " $1 "(void) {}"}' > "$STUBS/libbinder_ndk.c"
grep -v '^#' "$ROOT/shims/stubs/libbinder_ndk.syms" | awk -F@ '{v[$2] = v[$2] " " $1 ";"} END {for (n in v) print n " {" v[n] " };"}' \
  > "$STUBS/libbinder_ndk.map"
"$CC" -shared -fPIC -nostdlib -Wl,-soname,libbinder_ndk.so -Wl,--version-script,"$STUBS/libbinder_ndk.map" \
  -o "$STUBS/libbinder_ndk.so" "$STUBS/libbinder_ndk.c"
"${CC/android30-clang/android31-clang}" -O2 -Wall -Werror -o "$ROOT/input/shims/btaudio_alias" \
  "$ROOT/shims/btaudio_alias/btaudio_alias.c" -L"$ROOT/work/input/stubs" -lbinder_ndk -llog
echo "built input/shims/btaudio_alias"
"$CC" -shared -fPIC -O2 -Wall -Werror -D_FORTIFY_SOURCE=0 -o "$ROOT/input/shims/liblights_scale_shim.so" \
  "$ROOT/shims/lights_scale/lights_scale_shim.c" -ldl -llog
echo "built input/shims/liblights_scale_shim.so"
"${CC/android30-clang/android31-clang}" -O2 -Wall -Werror -o "$ROOT/input/shims/vibrator_proxy" \
  "$ROOT/shims/vibrator_proxy/vibrator_proxy.c" -L"$ROOT/work/input/stubs" -lbinder_ndk -llog
echo "built input/shims/vibrator_proxy"
