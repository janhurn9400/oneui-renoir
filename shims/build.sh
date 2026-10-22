#!/usr/bin/env bash
# Build our vendor shims with the NDK (work/tools-dl/android-ndk-r27c) -> work/input/<name>.so. Runs on the Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC=$ROOT/work/tools-dl/android-ndk-r27c/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang
"$CC" -shared -fPIC -O2 -Wall -Werror -o "$ROOT/work/input/libfpc_timeout_shim.so" \
  "$ROOT/shims/fpc_timeout/fpc_timeout_shim.c" -ldl -llog
echo "built work/input/libfpc_timeout_shim.so"
