# 把聊天页挂到 llama-server 的 `/`

2026 年后的 llama-server 已经没有内嵌 webui，也没有 `--path` 静态托管——访问 `/` 直接返回 404 JSON：

```json
{"error":{"code":404,"message":"File Not Found","type":"not_found_error"}}
```

所以想让 `http://127.0.0.1:8080` 直接是个聊天界面，只能自己挂路由。改动只有两处，**不需要 fork 整个项目**。

## 改动 1：加页面文件

把 [`../app/chat_page.h`](../app/chat_page.h) 复制到 `llama.cpp/tools/server/chat_page.h`。

它就是一个 C++ 原始字符串常量：

```cpp
static const char * CHAT_PAGE_HTML = R"LFMPAGE(<!DOCTYPE html>
...
</html>
)LFMPAGE";
```

改页面内容的流程：改 `../app/lfm3-chat.html` → 重新生成 `chat_page.h` → 重编。别直接改 `chat_page.h`，两份会漂移，而真正编进二进制的是后者。

重新生成（仓库自带脚本）：

```bash
python3 scripts/gen-chat-page.py           # app/lfm3-chat.html -> app/chat_page.h
python3 scripts/gen-chat-page.py --check   # 只校验是否同步，已过期返回 1
```

脚本会检查页面里有没有和分隔符冲突的 `)LFMPAGE"`，并强制写 LF 换行。

## 改动 2：注册路由

`llama.cpp/tools/server/server.cpp`，文件顶部加：

```cpp
#include "chat_page.h"
```

然后在 `server_register_routes()` 的**最开头**加一个 `/` 路由：

```cpp
static void server_register_routes(server_http_context & ctx_http, server_routes & routes) {
    // 内嵌聊天页：浏览器打开 http://<host>:<port>/ 直接就是对话界面
    ctx_http.get("/", [](const server_http_req &) {
        auto res = std::make_unique<server_http_res>();
        res->content_type = "text/html; charset=utf-8";
        res->data = CHAT_PAGE_HTML;
        return res;
    });

    ctx_http.get("/health", /* ... 原有的 ... */);
    // ...
}
```

要点：

- 必须放在 `server_register_routes()` 最前面。路由是顺序匹配的，后面注册的 `/` 不会生效。
- handler 的签名是 `std::unique_ptr<server_http_res>(const server_http_req &)`，用 `ctx_http.get` 而不是 `routes.`——`routes` 那套是给带参数的路由用的。
- `res->data` 直接接 `const char *` 就行，handler 返回时框架会自己拷。

## 页面里的配套改动

聊天页要让 API 走同源，否则从 `127.0.0.1:8080` 打开时也会去连绝对地址：

```js
// 同源访问（页面由 llama-server 托管）；若从本地文件打开则回退到固定端口
const API = location.protocol === 'http:' ? '' : 'http://127.0.0.1:8080';
```

这样两种打开方式都能用：服务托管的走同源，`file://` 打开的走绝对地址。

## CORS 说明

llama-server 的 CORS 是**回显 Origin**（不是发 `*`）。`file://` 页面的 Origin 是 `null`，会被回显成 `null`，浏览器能放行。`--cors-origins` 默认值已经是 `*`，一般不用动。

## 维护提醒

这个补丁**只在本地源码树里**。`git pull` 上游更新时 `server.cpp` 会被覆盖，需要重新打。建议：

- 把改动做成 `.patch` 存到仓库里，每次 `git apply`；
- 或者干脆用 `--host` + 独立的静态文件服务（但手机上多开一个进程不值得）。

编完的验证：

```bash
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' http://127.0.0.1:8080/
# 期望：200 加上 app/lfm3-chat.html 的字节数
```
