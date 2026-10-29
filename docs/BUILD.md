# 构建

## 环境

| 项 | 值 |
|---|---|
| 主机 | Windows 11 + Git Bash（Linux/macOS 同理） |
| NDK | r27c |
| 源码 | [llama.cpp](https://github.com/ggml-org/llama.cpp) master，**commit 必须 ≥ 2026-10-27 17:06**（`lfm3` 架构在此之后才存在） |
| 目标 | arm64-v8a / Android 28 |

`lfm3` 架构的合入点是 PR #31252。早于这个时间的 master 编译出来的二进制加载 LFM3 会直接报：

```
error: unknown model architecture: 'lfm3'
```

## 编译

```bash
export ANDROID_NDK_ROOT=/path/to/android-ndk-r27c

cmake -B build-android -S llama.cpp \
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

cmake --build build-android --config Release -j
```

关键参数只有两个需要解释：

- **`GGML_CPU_ARM_ARCH=armv8.2-a+dotprod`**
  `dotprod` 是必须的（SD 8 Gen 1 的 `/proc/cpuinfo` Features 里有 `asimddp`）。
  **绝对不要加 `i8mm` 或 `bf16`** —— 这两个扩展要 Cortex-X3 / ARMv9 才有，SD 8 Gen 1 没有，加上会 `Illegal instruction` 直接崩，而且崩在第一个矩阵乘上，日志看不出原因。
- **`-DBUILD_SHARED_LIBS=ON`**
  产物是一堆 `.so` + 很薄的 `llama-cli`/`llama-server` 启动器。好处是升级只换 `.so`，坏处是必须设 `LD_LIBRARY_PATH`。想做成单体二进制就设 `OFF`。

编完：

```bash
strip --strip-all build-android/bin/llama-cli build-android/bin/llama-server
# .so 也一起 strip
```

## 推送到手机

Git Bash 下有两个坑：

```bash
# 坑 1：MSYS 会把 /sdcard/... 自动转成 Windows 路径，必须关掉
# 坑 2：本地路径写成 C:/... 形式，不要写成 /c/...
MSYS_NO_PATHCONV=1 adb push C:/path/to/build-android/bin/ /sdcard/Download/lfm3-bin/
```

更好的做法是**直接推到 Termux 私有目录**，避开 `/sdcard` 的 FUSE（见 [PERFORMANCE.md](PERFORMANCE.md)）：

```bash
adb push C:/path/to/bin/. /data/data/com.termux/files/home/lfm3/
```

## 运行

```bash
export LD_LIBRARY_PATH=$HOME/lfm3
$HOME/lfm3/llama-server \
  -m ~/LFM3-1.7B-Q4_K_M.gguf \
  -c 8192 -t 4 -lm none \
  --host 127.0.0.1 --port 8080
```

参数变更提醒（2026 后的 master）：

| 旧参数 | 现状 |
|---|---|
| `--no-mmap` / `--mlock` / `--direct-io` | 合并为 `-lm, --load-mode {auto,none,mmap,mlock,mmap+mlock,dio}` |
| `-no-cnv` | 改为 `-st, --single-turn` |
| `--path`（静态文件托管） | 已移除 |
| 内嵌 webui | 已移除，需自行挂路由（见 [../patches/](../patches/)） |

## 验证是否编对了

```bash
# 架构字符串应该在二进制里
strings libllama.so | grep -x lfm3

# 指令集：不应该出现 i8mm 相关指令导致的崩溃
adb logcat | grep -i "illegal instruction"
```
