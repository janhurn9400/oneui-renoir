#!/usr/bin/env bash
# Build our shims with the NDK (work/tools-dl/android-ndk-r27c) -> work/input/<name>.so. Runs on the Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC=$ROOT/work/tools-dl/android-ndk-r27c/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang
"${CC}++" -shared -fPIC -O2 -Wall -Werror -fno-exceptions -fno-rtti -nostdlib++ \
  -o "$ROOT/work/input/libfpc_timeout_shim.so" \
  -x c "$ROOT/shims/fpc_timeout/fpc_timeout_shim.c" -x c++ "$ROOT/shims/fpc_timeout/fpc_enroll_progress.cpp" -ldl -llog
echo "built work/input/libfpc_timeout_shim.so"
"${CC/android30-clang/android31-clang}" -O2 -Wall -Werror -o "$ROOT/work/input/btaudio_alias" \
  "$ROOT/shims/btaudio_alias/btaudio_alias.c" -L"$ROOT/work/input/stubs" -lbinder_ndk -llog
# (work/input/stubs/libbinder_ndk.so: pulled from the phone for the platform-only AServiceManager_* symbols)
echo "built work/input/btaudio_alias"
"$CC" -shared -fPIC -O2 -Wall -Werror -D_FORTIFY_SOURCE=0 -o "$ROOT/work/input/liblights_scale_shim.so" \
  "$ROOT/shims/lights_scale/lights_scale_shim.c" -ldl -llog
echo "built work/input/liblights_scale_shim.so"
"${CC/android30-clang/android31-clang}" -O2 -Wall -Werror -o "$ROOT/work/input/vibrator_proxy" \
  "$ROOT/shims/vibrator_proxy/vibrator_proxy.c" -L"$ROOT/work/input/stubs" -lbinder_ndk -llog
echo "built work/input/vibrator_proxy"
