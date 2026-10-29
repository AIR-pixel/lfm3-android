#!/data/data/com.termux/files/usr/bin/bash
# 公共函数：模型目录探测、交互式选择、参数解析
#
# 由 start-server.sh / start-chat.sh source，不单独执行。

# 脚本所在目录（release 包解压后，这里同时是二进制目录）
LFM3_DIR="${LFM3_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"

# 模型搜索目录，按优先级排列。可用 LFM3_MODELS_DIR 覆盖第一项。
lfm3_model_dirs() {
    printf '%s\n' \
        "${LFM3_MODELS_DIR:-$HOME/models}" \
        "$HOME" \
        "$LFM3_DIR" \
        "/sdcard/AI_Models" \
        "/sdcard/Download" \
        "/sdcard/models"
}

# 逐目录列出 .gguf（非递归，避免扫 /sdcard 卡死）
lfm3_find_models() {
    local d
    while IFS= read -r d; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f -name '*.gguf' 2>/dev/null
    done < <(lfm3_model_dirs) | sort -u
}

lfm3_size_of() {
    stat -c %s "$1" 2>/dev/null || echo 0
}

lfm3_human_size() {
    awk -v b="${1:-0}" 'BEGIN{
        n = split("B KB MB GB TB", u, " "); i = 1
        while (b >= 1024 && i < n) { b /= 1024; i++ }
        printf "%.1f%s", b, u[i]
    }'
}

# /sdcard 与 /storage 是 FUSE，mmap 在这里会退化成每次重读磁盘
lfm3_on_sdcard() {
    case "${1:-}" in
        /sdcard/*|/storage/*) return 0 ;;
        *) return 1 ;;
    esac
}

lfm3_short_path() {
    local p="${1:-}"
    printf '%s\n' "${p/#$HOME/~}"
}

lfm3_die() {
    printf '错误: %s\n' "$*" >&2
    exit 1
}

# 检查二进制是否就位，顺手补执行权限
lfm3_require() {
    local n
    chmod +x "$LFM3_DIR"/llama-* 2>/dev/null || true
    for n in "$@"; do
        [ -x "$LFM3_DIR/$n" ] || lfm3_die "找不到 $LFM3_DIR/$n —— release 包是否完整解压到了 $LFM3_DIR ？"
    done
}

lfm3_print_menu() {
    local -a list=("$@")
    local i p loc
    printf '找到 %d 个模型：\n\n' "${#list[@]}"
    for i in "${!list[@]}"; do
        p="${list[$i]}"
        loc="$(lfm3_short_path "$(dirname "$p")")"
        if lfm3_on_sdcard "$p"; then
            loc="$loc  [sdcard]"
        fi
        printf '  %2d) %-42.42s %7s   %s\n' \
            "$((i + 1))" "$(basename "$p")" \
            "$(lfm3_human_size "$(lfm3_size_of "$p")")" "$loc"
    done
    printf '\n'
}

# 找到并选定一个模型，路径输出到 stdout，菜单等提示一律走 stderr
lfm3_pick_model() {
    local -a list
    mapfile -t list < <(lfm3_find_models)

    if [ "${#list[@]}" -eq 0 ]; then
        {
            echo "没找到任何 .gguf 模型。"
            echo "把模型放到以下任一目录后重试（可用 LFM3_MODELS_DIR 指定第一个）："
            lfm3_model_dirs | sed 's/^/  /'
            echo
            echo "LFM3-1.7B，约 1.1GB，国内走 ModelScope："
            echo "  mkdir -p ~/models && curl -L -o ~/models/LFM3-1.7B-Q4_K_M.gguf \\"
            echo "    https://modelscope.cn/models/LiquidAI/LFM3-1.7B-GGUF/resolve/master/LFM3-1.7B-Q4_K_M.gguf"
        } >&2
        return 1
    fi

    if [ "${#list[@]}" -eq 1 ]; then
        echo "使用唯一找到的模型（多个模型时会显示选择菜单）" >&2
        printf '%s\n' "${list[0]}"
        return 0
    fi

    lfm3_print_menu "${list[@]}" >&2

    if [ ! -t 0 ]; then
        echo "当前不是交互终端，请用 -m <路径> 直接指定模型" >&2
        return 1
    fi

    local choice
    while :; do
        printf '输入编号（q 退出）: ' >&2
        IFS= read -r choice || return 1
        case "$choice" in
            q|Q)
                echo "已取消" >&2
                return 1
                ;;
            ''|*[!0-9]*)
                printf '请输入 1-%d 之间的数字\n' "${#list[@]}" >&2
                continue
                ;;
        esac
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#list[@]}" ]; then
            printf '%s\n' "${list[$((choice - 1))]}"
            return 0
        fi
        printf '超出范围，请输入 1-%d\n' "${#list[@]}" >&2
    done
}

# 调用前先给 LFM3_CTX / LFM3_THREADS / LFM3_PORT 赋默认值
# 「--」之后的参数原样透传给 llama-server / llama-cli
lfm3_parse_args() {
    EXTRA_ARGS=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -m|--model)
                [ "$#" -ge 2 ] || lfm3_die "$1 需要一个模型路径"
                MODEL="$2"
                shift 2
                ;;
            -c|--ctx)
                [ "$#" -ge 2 ] || lfm3_die "$1 需要一个数字"
                LFM3_CTX="$2"
                shift 2
                ;;
            -t|--threads)
                [ "$#" -ge 2 ] || lfm3_die "$1 需要一个数字"
                LFM3_THREADS="$2"
                shift 2
                ;;
            -p|--port)
                [ "$#" -ge 2 ] || lfm3_die "$1 需要一个数字"
                LFM3_PORT="$2"
                shift 2
                ;;
            --list)
                LFM3_LIST=1
                shift
                ;;
            -h|--help)
                lfm3_usage
                exit 0
                ;;
            --)
                shift
                EXTRA_ARGS=("$@")
                break
                ;;
            *)
                # v0.1.x 是位置参数式，顺手给个迁移提示
                if [ -f "$1" ]; then
                    lfm3_die "模型要用 -m 指定: -m $1"
                fi
                lfm3_die "未知参数: $1（-h 查看帮助）"
                ;;
        esac
    done

    case "$LFM3_CTX" in
        ''|*[!0-9]*) lfm3_die "上下文必须是正整数: $LFM3_CTX" ;;
    esac
    case "$LFM3_THREADS" in
        ''|*[!0-9]*) lfm3_die "线程数必须是正整数: $LFM3_THREADS" ;;
    esac
    if [ -n "${LFM3_PORT:-}" ]; then
        case "$LFM3_PORT" in
            ''|*[!0-9]*) lfm3_die "端口必须是数字: $LFM3_PORT" ;;
        esac
    fi
}

# 打印模型清单，供 --list 使用
lfm3_list_models() {
    local p
    local found=0
    while IFS= read -r p; do
        found=1
        printf '%7s  %s\n' "$(lfm3_human_size "$(lfm3_size_of "$p")")" "$p"
    done < <(lfm3_find_models)
    if [ "$found" -eq 0 ]; then
        echo "没找到任何 .gguf 模型" >&2
        return 1
    fi
}
