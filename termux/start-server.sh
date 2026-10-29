#!/data/data/com.termux/files/usr/bin/bash
# 启动 llama-server：内置聊天页 + OpenAI 兼容 API
#
# 不带 -m 时自动扫描模型目录并让你选；只有一个模型则直接用。
set -e

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

lfm3_usage() {
    cat <<'EOF'
用法: bash start-server.sh [选项] [-- llama-server 额外参数]

  -m, --model <路径>    指定模型（省略则扫描目录后交互选择）
  -c, --ctx <数字>      上下文长度，默认 8192
  -t, --threads <数字>  线程数，默认 4
  -p, --port <数字>     端口，默认 8080
      --list            只列出扫描到的模型，不启动
  -h, --help            显示帮助

模型搜索目录（按优先级）:
  $LFM3_MODELS_DIR、~/models、~/、脚本所在目录、/sdcard/AI_Models、/sdcard/Download、/sdcard/models

示例:
  bash start-server.sh                          # 菜单选模型
  bash start-server.sh -m ~/models/qwen.gguf -c 4096 -t 3
  bash start-server.sh -- --mlock               # 额外参数透传
EOF
}

MODEL=""
LFM3_CTX=8192
LFM3_THREADS=4
LFM3_PORT=8080
LFM3_LIST=0

lfm3_parse_args "$@"

if [ "$LFM3_LIST" -eq 1 ]; then
    lfm3_list_models || exit 1
    exit 0
fi

if [ -z "$MODEL" ]; then
    MODEL="$(lfm3_pick_model)" || exit 1
fi

[ -f "$MODEL" ] || lfm3_die "模型不存在: $MODEL"
lfm3_require llama-server

size="$(lfm3_size_of "$MODEL")"

# 加载方式：
#   FUSE（/sdcard）上 mmap 会让每个 token 重读整份权重，必须 none
#   模型超过 4GB 时退回 auto，避免把内存一次性吃满
if [ -n "${LFM3_LOAD_MODE:-}" ]; then
    load_mode="$LFM3_LOAD_MODE"
elif lfm3_on_sdcard "$MODEL"; then
    load_mode=none
elif [ "$size" -gt 4294967296 ]; then
    load_mode=auto
else
    load_mode=none
fi

echo "模型:   $(basename "$MODEL")  $(lfm3_human_size "$size")"
echo "路径:   $MODEL"
echo "上下文: $LFM3_CTX    线程: $LFM3_THREADS    加载: $load_mode"
if lfm3_on_sdcard "$MODEL"; then
    echo
    echo "警告: 模型在 /sdcard（FUSE）上，已强制 -lm none。"
    echo "      仍建议 mv 到 ~/models —— 见 docs/PERFORMANCE.md 坑 1。"
fi
echo
echo "聊天页 http://127.0.0.1:$LFM3_PORT"
echo "API    http://127.0.0.1:$LFM3_PORT/v1"
echo "停止:  Ctrl+C"
echo

exec env LD_LIBRARY_PATH="$LFM3_DIR" "$LFM3_DIR/llama-server" \
    -m "$MODEL" -c "$LFM3_CTX" -t "$LFM3_THREADS" -lm "$load_mode" \
    --host 127.0.0.1 --port "$LFM3_PORT" \
    "${EXTRA_ARGS[@]}"
