#!/usr/bin/env python3
"""把 app/lfm3-chat.html 转成可内嵌进 llama-server 的 C++ 头文件。

用法:
    python3 scripts/gen-chat-page.py            # 写到 app/chat_page.h
    python3 scripts/gen-chat-page.py -o /tmp/x.h
    python3 scripts/gen-chat-page.py --check    # 只校验是否同源，不写文件（返回 1 表示已过期）

改页面的正确流程是改 lfm3-chat.html 再跑本脚本，不要直接手改 chat_page.h ——
两份会漂移，而真正编进二进制的是 chat_page.h。
"""

import argparse
import io
import pathlib
import sys

DELIM = "LFMPAGE"
ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "app" / "lfm3-chat.html"
DEFAULT_OUT = ROOT / "app" / "chat_page.h"

HEADER = (
    "// 由 scripts/gen-chat-page.py 从 app/lfm3-chat.html 生成，请勿手改\n"
    "// 内嵌的本地聊天页（由 tools/server 的 \"/\" 路由直接返回）\n"
)


def render(html: str) -> str:
    if f"){DELIM}\"" in html:
        raise SystemExit(f"页面里出现了与原始字符串分隔符冲突的 `){DELIM}\"`，换个分隔符")
    return HEADER + f'static const char * CHAT_PAGE_HTML = R"{DELIM}(' + html + f'){DELIM}";\n'


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 chat_page.h")
    ap.add_argument("-o", "--output", type=pathlib.Path, default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true", help="只检查是否与 html 同步")
    args = ap.parse_args()

    if not SRC.is_file():
        raise SystemExit(f"找不到源页面: {SRC}")

    html = SRC.read_text(encoding="utf-8")
    content = render(html)

    if args.check:
        current = args.output.read_text(encoding="utf-8") if args.output.is_file() else ""
        if current != content:
            print(f"{args.output} 已过期，请重新生成", file=sys.stderr)
            return 1
        print(f"{args.output} 与 {SRC.name} 一致")
        return 0

    # 固定 LF + UTF-8：Windows 上用 text 模式写会被换成 CRLF
    with io.open(args.output, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)

    print(f"{SRC.name} -> {args.output}  ({len(content)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
