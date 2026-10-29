#!/data/data/com.termux/files/usr/bin/bash
# 纯终端对话，不起 HTTP 服务
#
# 不带 -m 时自动扫描模型目录并让你选；只有一个模型则直接用。
set -e

. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

lfm3_usage() {
    cat <<'EOF'
用法: bash start-chat.sh [选项] [-- llama-cli 额外参数]

  -m, --model <路径>    指定模型（省略则扫描目录后交互选择）
  -c, --ctx <数字>      上下文长度，默认 4096
  -t, --threads <数字>  线程数，默认 4
      --list            只列出扫描到的模型，不启动
  -h, --help            显示帮助

示例:
  bash start-chat.sh
  bash start-chat.sh -m ~/models/qwen.gguf -c 2048 -t 3
  bash start-chat.sh -- --jinja
EOF
}

MODEL=""
LFM3_CTX=4096
LFM3_THREADS=4
LFM3_PORT=""
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
lfm3_require llama-cli

size="$(lfm3_size_of "$MODEL")"

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
echo "上下文: $LFM3_CTX    线程: $LFM3_THREADS    加载: $load_mode"
echo

# -st / --single-turn：单轮模式，替代已移除的 -no-cnv
exec env LD_LIBRARY_PATH="$LFM3_DIR" "$LFM3_DIR/llama-cli" \
    -m "$MODEL" -c "$LFM3_CTX" -t "$LFM3_THREADS" -lm "$load_mode" -st \
    "${EXTRA_ARGS[@]}"
