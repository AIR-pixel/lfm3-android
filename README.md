# LFM3 on Android

在安卓手机上跑本地 LLM 的一套现成方案：**预编译 arm64 二进制 + 内置聊天页 + 模型选择菜单**，以 **Liquid AI LFM3-1.7B** 为验证对象，针对 **骁龙 8 Gen 1（SM8250）** 调过参。

Redmi K50 / 12GB / Android 17 实测：**19.5 tok/s 生成，60 tok/s prompt**（Q4_K_M，8192 上下文，4 线程）。

<img src="docs/screenshot.png" width="300" alt="手机浏览器打开 127.0.0.1:8080 的聊天界面，顶部显示当前模型名">

脚本不绑定具体模型——`~/models` 里放几个 `.gguf`，启动时菜单选。但也别指望 7B 能跑得快，见[实测数据](#实测数据)。

---

## 先说清楚：这个东西和已有项目的区别

安卓上跑本地模型，已经有人做过，而且做得不错：

| 项目 | 做法 | 差异 |
|---|---|---|
| [orailnoor/termux-llm](https://github.com/orailnoor/termux-llm) | 一键脚本装 llama.cpp，`llama-server` 在 `127.0.0.1:8080` 同时托管聊天页和 OpenAI API | 架构与本项目相同 |
| [cycloarcane/llama-termux-setup](https://github.com/cycloarcane/llama-termux-setup) | Termux 内原生编译，配 `serve.sh`/`stop.sh` | 要在手机上编译 10–15 分钟 |
| [paragon83114/llama-adreno](https://github.com/paragon83114/llama-adreno) | Adreno GPU OpenCL 加速 | 走 GPU 路线 |

另外 **上游 llama.cpp 自带 webui**（编译时 assets 齐全即可），所以「server 顺带托管聊天页」本身不是任何人的原创。

本仓库不重复那部分。它只解决三个别人没覆盖的问题：

1. **不需要在手机上编译。** 全部产物是 NDK 交叉编译 + strip 过的 arm64 二进制，解压即用。
2. **能跑 LFM3。** `lfm3` 架构 2026-10-27 17:06 才进 llama.cpp master（[PR #31252](https://github.com/ggml-org/llama.cpp/pull/31252)），Termux 仓库版本和所有基于 `llama.rn` 的 App（PocketPal、Maid）都还没跟上，加载必报 `unknown model architecture`。
3. **骁龙 8 Gen 1 的正确参数，以及两个会让速度掉到 0.2 tok/s 的坑。** 见 [docs/PERFORMANCE.md](docs/PERFORMANCE.md)。

---

## 30 秒上手

前置：手机已装 Termux（**必须 F-Droid 版**，Play Store 版已废弃）、已 `termux-setup-storage`。

```bash
# 1. 模型（约 1.1GB）— 放 ~/models，不要放 /sdcard
#    官方 GGUF：https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF
#    国内走 ModelScope（实测 14MB/s，hf-mirror 只有 34KB/s）
mkdir -p ~/models
curl -L -o ~/models/LFM3-1.7B-Q4_K_M.gguf \
  "https://modelscope.cn/models/LiquidAI/LFM3-1.7B-GGUF/resolve/master/LFM3-1.7B-Q4_K_M.gguf"

# 2. 二进制 + 启动脚本（zip 里已带好，扁平解压到 ~/lfm3）
mkdir -p ~/lfm3 && cd ~/lfm3
curl -L -o lfm3.zip \
  https://github.com/AIR-pixel/lfm3-android/releases/download/v0.2.0/lfm3-android-arm64.zip
unzip -o lfm3.zip     # 没有 unzip 先 pkg install unzip

# 3. 跑
bash ~/lfm3/start-server.sh
```

手机浏览器打开 **`http://127.0.0.1:8080`** —— 直接就是聊天界面，不用装 App，不用 `file://`。顶部会显示当前加载的模型名。

想连外部客户端（SillyTavern / Open WebUI / GPTMobile 等），OpenAI 兼容端点在 `http://127.0.0.1:8080/v1`。

---

## 换模型

不需要改脚本。启动时自动扫描下面这些目录里的 `.gguf`：

```
$LFM3_MODELS_DIR（如果设了）、~/models、~/、~/lfm3、
/sdcard/AI_Models、/sdcard/Download、/sdcard/models
```

找到多个就出菜单：

```
找到 3 个模型：

   1) LFM3-1.7B-Q4_K_M.gguf                      1.0GB   ~/models
   2) Qwen2.5-1.5B-Instruct-Q4_K_M.gguf          1.0GB   ~/models
   3) gemma-3-4b-it-Q4_K_M.gguf                  2.3GB   /sdcard/Download  [sdcard]

输入编号（q 退出）: 
```

只有一个模型时直接用它，不出菜单。也可以完全跳过交互：

```bash
bash ~/lfm3/start-server.sh --list                        # 只列模型
bash ~/lfm3/start-server.sh -m ~/models/qwen.gguf         # 指定模型
bash ~/lfm3/start-server.sh -m ~/models/qwen.gguf -c 4096 -t 3
bash ~/lfm3/start-server.sh -- --jinja                    # 额外参数透传给 llama-server
```

| 参数 | 说明 | 默认 |
|---|---|---|
| `-m, --model` | 模型路径 | 扫描后选择 |
| `-c, --ctx` | 上下文长度 | 服务器 8192 / CLI 4096 |
| `-t, --threads` | 线程数 | 4 |
| `-p, --port` | 端口 | 8080 |
| `--list` | 只列模型 | — |
| `--` | 之后原样透传给 llama 二进制 | — |

**切换模型需要重启进程**（Ctrl+C 后重跑），没有网页内热切换——llama-server 一次只加载一个模型。1.1GB 的模型重新加载大约 2 秒。

几个提醒：

- **大模型要降上下文**。7B Q4 约 4.4GB，`-c 8192` 的 KV cache 还要额外几 GB，12GB 机器上容易 OOM。超 4GB 的模型脚本会自动从 `-lm none` 退回 `-lm auto`，别再加 `-c` 了。
- **模型放 `/sdcard` 会强制 `-lm none` 并给出警告**，但仍然建议挪到 `~/models`，原因见 [docs/PERFORMANCE.md](docs/PERFORMANCE.md) 坑 1。
- 聊天页顶部显示的模型名来自 `/v1/models` 返回的 id，换完模型刷新一下就更新。

---

## 目录

```
app/lfm3-chat.html        聊天页源码（流式输出、思考折叠、tok/s、模型名、localStorage 历史）
app/chat_page.h           上述页面的 C++ 原始字符串常量版，由脚本生成，勿手改
patches/                  把聊天页塞进 llama-server 的改法
scripts/build-android.sh  NDK 交叉编译脚本
scripts/gen-chat-page.py  html -> chat_page.h
termux/lib.sh             公共函数：模型扫描、菜单、参数解析（被下面两个 source）
termux/start-server.sh    起 HTTP 服务 + 内置聊天页（release zip 里也带了一份）
termux/start-chat.sh      纯终端对话
docs/BUILD.md             构建细节与踩坑
docs/PERFORMANCE.md       实测性能、线程数对比、两个致命坑
```

改聊天页的正确姿势：改 `app/lfm3-chat.html` → `python3 scripts/gen-chat-page.py` → 重编。直接改 `chat_page.h` 会和源页面漂移。

---

## 实测数据

Redmi K50（SM8250，X2@3.0GHz ×1 + A710 ×3 + A510 ×4），LFM3-1.7B-Q4_K_M，8192 ctx：

| 线程 | 生成 tok/s | prompt tok/s |
|---|---|---|
| 3 | 19.4 | 52 |
| **4** | **19.5** | **60** |
| 5 | 13.5 | — |
| 6 | 13.1 | — |
| 8 | 14.3 | — |

**4 线程最优。** 上到 8 线程会被 4 颗 A510 小核拖累，反而更慢。

只测过 LFM3。换别的模型速度不一样，看每条回答下面的 `tok/s` 自己比。

---

## 已知限制

- 只验证了 arm64-v8a + `armv8.2-a+dotprod`。**不要加 `i8mm`**，SD 8 Gen 1 没有这个扩展，会 `Illegal instruction`。
- 一次只能跑一个模型，换模型要重启进程。
- LFM3 即使传 `chat_template_kwargs={"enable_thinking":false}` 仍会输出思考内容并残留 `</think>`，聊天页里按 `</think>` 做切分处理。换成别的模型后思考块可能不再出现，页面逻辑不受影响。
- Termux 进程通常被 MIUI 限在 `Cpus_allowed_list: 4-6`，3.0GHz 的 X2 用不上。这是手机端 2 tok/s 和 19.5 tok/s 的真正差别，详见性能文档。
- 2026 年后的 llama-server 已移除 `--path` 静态托管和内嵌 webui，所以本项目的聊天页是靠 [patches/](patches/) 里的源码补丁挂上去的。上游升级会覆盖补丁。

## 许可

本项目脚本与页面 MIT。预编译二进制由 [llama.cpp](https://github.com/ggml-org/llama.cpp)（MIT）编译而来，遵循其许可。

模型权重不包含在本仓库内。各模型遵循各自许可——LFM3 是 **LFM Open License v1.0**，年营收低于 1000 万美元可商用，达到或超过需与 Liquid AI 单独签约。
