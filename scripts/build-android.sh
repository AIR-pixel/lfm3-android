#!/usr/bin/env bash
# 用 Android NDK 交叉编译 llama.cpp（arm64），针对骁龙 8 Gen 1 调参
#
# 用法:
#   ANDROID_NDK_ROOT=/path/to/android-ndk-r27c ./scripts/build-android.sh [llama.cpp 源码目录]
#
# 默认源码目录为 ./llama.cpp，不存在则自动 clone master。
set -euo pipefail

SRC="${1:-llama.cpp}"
BUILD="build-android"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 8)}"

if [ -z "${ANDROID_NDK_ROOT:-}" ]; then
    echo "错误: 需要设置 ANDROID_NDK_ROOT" >&2
    echo "  export ANDROID_NDK_ROOT=/path/to/android-ndk-r27c" >&2
    exit 1
fi

if [ ! -d "$SRC" ]; then
    echo "==> clone llama.cpp master"
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$SRC"
fi

# lfm3 架构是 2026-10-27 17:06 之后才有的（PR #31252）
if ! grep -q '"lfm3"' "$SRC/src/llama-arch.cpp" 2>/dev/null; then
    echo "警告: 源码里没有 lfm3 架构字符串，加载 LFM3 模型会报 unknown architecture" >&2
    echo "      请 git pull 到 2026-10-27 之后的 master" >&2
fi

echo "==> configure"
# 关键: GGML_CPU_ARM_ARCH 只能开 dotprod。
# SD 8 Gen 1 (SM8250) 没有 i8mm / bf16，加了会在第一个矩阵乘上 Illegal instruction。
cmake -B "$BUILD" -S "$SRC" \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-28 \
    -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=ON \
    -DCMAKE_BUILD_TYPE=Release

echo "==> build (-j$JOBS)"
cmake --build "$BUILD" --config Release -j"$JOBS"

STRIP="$(find "$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt" -maxdepth 3 -name llvm-strip -type f 2>/dev/null | head -1 || true)"
[ -n "$STRIP" ] || STRIP="$(command -v llvm-strip || command -v strip || true)"

if [ -n "$STRIP" ] && [ -x "$STRIP" ]; then
    echo "==> strip ($STRIP)"
    find "$BUILD/bin" -maxdepth 1 \( -name 'llama-*' -o -name '*.so' \) -exec "$STRIP" --strip-all {} +
fi

echo
echo "==> 产物: $BUILD/bin"
ls -lh "$BUILD/bin" | head -20
echo
echo "推送到手机（注意 MSYS_NO_PATHCONV，否则 Git Bash 会篡改 /sdcard 路径）:"
echo "  MSYS_NO_PATHCONV=1 adb push $BUILD/bin/. /data/data/com.termux/files/home/lfm3/"
