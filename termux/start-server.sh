#!/data/data/com.termux/files/usr/bin/bash
# 启动 llama-server（内置聊天页 + OpenAI 兼容 API）
#
# 用法: bash ~/lfm3/termux/start-server.sh [模型路径] [上下文] [线程数]
set -e

HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
BIN_DIR="$HOME_DIR/lfm3"
MODEL="${1:-$HOME_DIR/LFM3-1.7B-Q4_K_M.gguf}"
CTX="${2:-8192}"
THREADS="${3:-4}"

if [ ! -f "$MODEL" ]; then
    echo "找不到模型: $MODEL"
    echo "用法: bash $0 [模型路径] [上下文] [线程数]"
    echo
    echo "模型可从 ModelScope 下载（国内快）:"
    echo "  curl -L -o ~/LFM3-1.7B-Q4_K_M.gguf \\"
    echo "    https://modelscope.cn/models/LiquidAI/LFM3-1.7B-GGUF/resolve/master/LFM3-1.7B-Q4_K_M.gguf"
    exit 1
fi

if [ ! -x "$BIN_DIR/llama-server" ]; then
    echo "找不到 llama-server: $BIN_DIR/llama-server"
    echo "请把 release 里的 lfm3-android-arm64.zip 解压到 $BIN_DIR"
    exit 1
fi

# 模型在 /sdcard（FUSE）上时必须 -lm none，否则每个 token 都会重读整份权重
case "$MODEL" in
    /sdcard/*|/storage/*)
        echo "警告: 模型在 /sdcard 上（FUSE 文件系统），速度会掉到 0.2 tok/s"
        echo "      建议: mv \"$MODEL\" ~/  然后加 -lm none"
        ;;
esac

chmod +x "$BIN_DIR/llama-server" "$BIN_DIR"/llama-* 2>/dev/null || true

echo "模型:   $MODEL"
echo "上下文: $CTX"
echo "线程:   $THREADS"
echo
echo "浏览器打开 http://127.0.0.1:8080 直接聊天（页面已内嵌）"
echo "OpenAI 端点: http://127.0.0.1:8080/v1"
echo "停止: Ctrl+C"
echo

# -lm none = 原来的 --no-mmap，整份权重读进内存
exec env LD_LIBRARY_PATH="$BIN_DIR" "$BIN_DIR/llama-server" \
    -m "$MODEL" -c "$CTX" -t "$THREADS" -lm none \
    --host 127.0.0.1 --port 8080
