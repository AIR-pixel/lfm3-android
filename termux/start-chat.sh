#!/data/data/com.termux/files/usr/bin/bash
# 纯终端对话，不起 HTTP 服务
#
# 用法: bash ~/lfm3/termux/start-chat.sh [模型路径] [上下文] [线程数]
set -e

HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
BIN_DIR="$HOME_DIR/lfm3"
MODEL="${1:-$HOME_DIR/LFM3-1.7B-Q4_K_M.gguf}"
CTX="${2:-4096}"
THREADS="${3:-4}"

[ -f "$MODEL" ] || { echo "找不到模型: $MODEL"; exit 1; }
[ -x "$BIN_DIR/llama-cli" ] || { echo "找不到 llama-cli: $BIN_DIR/llama-cli"; exit 1; }

# -lm none: 关 mmap（新版 llama.cpp 已移除 --no-mmap）
# -st: 单轮模式（替代已移除的 -no-cnv）
# --jinja: 用 GGUF 里的 chat template
exec env LD_LIBRARY_PATH="$BIN_DIR" "$BIN_DIR/llama-cli" \
    -m "$MODEL" -c "$CTX" -t "$THREADS" -lm none -st --jinja
