# 性能实测与两个致命坑

设备：Redmi K50（`munch` / SM8250 / 骁龙 8 Gen 1 / 12GB / Android 17）
模型：`LFM3-1.7B-Q4_K_M.gguf`（1.1GB）
上下文：8192

---

## 坑 1：模型放 `/sdcard` 会让速度掉到 0.2 tok/s

### 现象

```
prompt eval time = 31858.06 ms / 51 tokens (624.67 ms per token, 1.60 tokens per second)
eval time     = 13477.78 ms / 4 tokens  (4492.59 ms per token, 0.22 tokens per second)
```

生成一个 token 要 4.5 秒。

### 原因

`/sdcard` 在安卓上不是真文件系统，是 **FUSE 挂载的 sdcardfs**（用户态文件系统，走 mediaprovider 转发）。llama.cpp 默认 mmap 加载权重，mmap 的页回收策略在 FUSE 上不生效——页被回收后不会走正常的 page cache 补回路径，而是每次访问都重新向 FUSE 发 IO 请求。

算一下就对上了：4492ms × 约 244MB/s ≈ 1.1GB，正好是整个模型大小。**每个 token 都在把 1.1GB 权重从磁盘重读一遍。**

### 解决

两件事一起做：

```bash
# 1. 模型和二进制都挪到 Termux 私有目录（ext4/f2fs，真文件系统）
mv /sdcard/Download/LFM3-1.7B-Q4_K_M.gguf ~/

# 2. 关掉 mmap，整份权重一次性读进内存
llama-server -m ~/LFM3-1.7B-Q4_K_M.gguf -lm none ...
```

现代 llama.cpp 已经把 `--no-mmap` / `--mlock` / `--direct-io` 合并成：

```
-lm, --load-mode {auto,none,mmap,mlock,mmap+mlock,dio}
```

`-lm none` 就是原来的 `--no-mmap`。模型只有 1.1GB，12GB 内存完全放得下，没必要省这点。

> 顺带：`--no-mmap`、`-no-cnv` 这些老参数在新版里已经不存在，会直接报 `invalid argument`。单轮对话改用 `-st / --single-turn`。

---

## 坑 2：Termux 被限在 3 颗 A710 上，X2 大核用不上

### 现象

同样的二进制、同样的模型，adb shell 里跑 19.5 tok/s，Termux 里跑 2 tok/s。

### 诊断

```bash
cat /proc/self/status | grep Cpus_allowed_list
# Cpus_allowed_list:	4-6
```

SM8250 的 CPU 拓扑：

| CPU | 核心 | 最高频 |
|---|---|---|
| cpu0–3 | Cortex-A510 ×4 | 1.8GHz |
| cpu4–6 | Cortex-A710 ×3 | 2.5GHz |
| cpu7 | **Cortex-X2 ×1** | **3.0GHz** |

Termux 的进程被 cpuset 限制在 `4-6`，**唯一那颗 3.0GHz 的 X2 被排除在外**。adb shell 的 cpuset 更宽，所以同一个二进制在 adb 下快 10 倍。

再叠加一层：MIUI 的 cgroup CPU quota 会在后台限制 Termux 的 CPU 时间片。

同时能看到 `cpu7` 被限到 `844800 kHz`（约 845MHz），温度 45.7°C，governor `schedutil`。手机在轻度负载下就已经在压 X2 的频率了。

### 试过 / 可以试的办法

按有效性排序：

1. **用 `-t 3` 而不是 `-t 4`** —— 进程只有 3 颗核可用，开 4 线程会有一个线程在核间反复迁移。实测 3 线程生成速度与 4 线程持平，prompt 略慢（52 vs 60 t/s），但更稳定。
2. **`termux-wake-lock`** —— 防止 Termux 进入后台被降优先级。
3. **设置 → 应用 → Termux → 电池 → 无限制** —— 解除 MIUI 的后台 CPU 限制。
4. **绕开 Termux 的 cpuset**：`adb shell` 直接起服务（cpuset 更宽），但这样模型只能放 `/data/local/tmp`，且需要每次插线。
5. 想彻底解决要 root 改 cpuset，或者换 `taskset`/`chrt` 提优先级——一般不值得。

---

## 线程数实测

LFM3-1.7B-Q4_K_M，8192 ctx，同一份二进制：

| 线程 | 生成 tok/s | prompt tok/s |
|---|---|---|
| 3 | 19.4 | 52 |
| **4** | **19.5** | **60** |
| 5 | 13.5 | — |
| 6 | 13.1 | — |
| 8 | 14.3 | — |

超过 4 线程后急剧下降——`-t 8` 会把任务派给 A510 小核，而 llama.cpp 的同步屏障要等最慢的那个线程，小核直接拖垮整条流水线。

**结论：`-t 4` 起步，被 cpuset 限制时改 `-t 3`。**

---

## 其他观测

- 温度 45.7°C 时 `MemAvailable` 4.8GB、`SwapFree` 8.5GB，内存不是瓶颈。8192 上下文对 1.7B 模型足够宽松，可以往上试到 16384。
- LFM3 的架构设计本来就走低 KV cache 路线（128K 上下文约 1.6GB KV），比同级 Qwen 系列省一半以上，这是它适合手机的核心原因。
- 手机端长时间推理主要受热限制，`schedutil` 会在 45°C 附近开始压频。要连续跑就摘壳、别边充边跑。
