# addStreamProxy Webhook 回调扩展

## 背景

ZLMediaKit 原生不支持在 `addStreamProxy` 拉流成功或 `delStreamProxy` 关闭时触发 HTTP 回调。本次二次开发在 `dev_yt` 分支上新增了两个独立 webhook：

- `on_stream_proxy_started`：拉流代理建立成功时触发
- `on_stream_proxy_stopped`：拉流代理结束时触发（超时、主动关闭、网络断开重试耗尽均会触发）

这两个 hook **不依赖** `hook.enable` 全局开关，只要配置了 URL 就会触发。

---

## 改动文件

### `server/WebHook.cpp` / `server/WebHook.h`

- 新增配置 key：`Hook::kOnStreamProxyStarted`、`Hook::kOnStreamProxyStopped`
- 在 `onceToken` 初始化块中注册默认空值
- 实现 `do_stream_proxy_hook()` 函数：
  - 直接读取 `mINI::Instance()[config_key]`（绕开 `GET_CONFIG` 宏不支持运行时 key 的限制）
  - `is_start=true` 时额外构造 `flv_url` 字段（使用 `SockUtil::get_local_ip()` 获取本机非 loopback IP + `http.port` 配置）

### `server/WebApi.cpp`

- `addStreamProxy()` 的 `setPlayCallbackOnce` 回调中，拉流成功时调用 `do_stream_proxy_hook(true, ...)`
- `setOnClose` 回调中，拉流结束时调用 `do_stream_proxy_hook(false, ...)`

### `src/Player/PlayerProxy.cpp`

- 修复 `delStreamProxy` 直接 `erase` 时不触发 `setOnClose` 回调的 bug
- 在析构函数中补调 `_on_close`，并用 `fireAndClear` 辅助函数确保所有路径（`close()`、重试耗尽、析构）只触发一次，不重复回调

### `conf/config.ini`

新增两个配置项（默认为空，不触发）：

```ini
[hook]
on_stream_proxy_started=
on_stream_proxy_stopped=
```

---

## 回调 Body 字段

### `on_stream_proxy_started`

| 字段 | 类型 | 说明 |
|------|------|------|
| `key` | string | proxy key，格式 `vhost/app/stream` |
| `vhost` | string | 虚拟主机 |
| `app` | string | 应用名 |
| `stream` | string | 流名 |
| `url` | string | 源流地址（拉流的上游 URL） |
| `flv_url` | string | ZLM 对外提供的 FLV 播放地址，使用本机非 loopback IP |
| `mediaServerId` | string | ZLM 实例 ID |
| `hook_index` | int | hook 序号 |

示例：

```json
{
  "key": "defaultVhost/live/test1",
  "vhost": "defaultVhost",
  "app": "live",
  "stream": "test1",
  "url": "http://127.0.0.1/live/test/hls.m3u8",
  "flv_url": "http://192.168.1.100/live/test1.live.flv",
  "mediaServerId": "your-server-id",
  "hook_index": 1
}
```

### `on_stream_proxy_stopped`

同上，去掉 `flv_url`，新增：

| 字段 | 类型 | 说明 |
|------|------|------|
| `err` | string | 结束原因，主动关闭时为 `"closed by user"` 或 `"player proxy destroyed"` |

---

## 配置方法

编辑 ZLM 的 `config.ini`（运行目录下的 `config.ini`，通常是 `release/darwin/Debug/config.ini`）：

```ini
[hook]
enable=0
on_stream_proxy_started=http://127.0.0.1:8088/on_stream_proxy_started
on_stream_proxy_stopped=http://127.0.0.1:8088/on_stream_proxy_stopped
on_stream_none_reader=http://127.0.0.1:8088/on_stream_none_reader
```

> `enable=0` 时推拉流鉴权不生效，但 `on_stream_proxy_started` / `on_stream_proxy_stopped` 仍然正常触发。

---

## 测试方法

### 1. 启动调试服务

```bash
cd zlm-webhook-debug
go run main.go
# 监听 :8088，支持所有 ZLM webhook 回调
```

### 2. 启动 ZLM

```bash
./release/darwin/Debug/MediaServer
```

### 3. 推一路循环测试流

```bash
ffmpeg -re -stream_loop -1 -i "juediqiusheng.mp4" \
  -c copy -f flv rtmp://127.0.0.1:1935/live/test
```

### 4. 添加 HLS 拉流代理

以 `http://127.0.0.1/live/test/hls.m3u8` 为源，创建一个新的代理流 `live/test1`：

```bash
curl -X POST "http://localhost/index/api/addStreamProxy" \
  -H "Content-Type: application/json" \
  -d '{
    "secret": "035c73f7-bb6b-4889-a715-d9eb2d1925cc",
    "vhost": "__defaultVhost__",
    "app": "live",
    "stream": "test1",
    "url": "http://127.0.0.1/live/test/hls.m3u8",
    "retry_count": 3
  }'
```

拉流成功后，调试服务会收到 `on_stream_proxy_started` 回调，并打印 `flv_url`。3 秒后自动用 `ffprobe` 分析该地址并打印编码/分辨率/码率信息。

### 5. 验证 FLV 播放

```
http://127.0.0.1/live/test1.live.flv
```

或使用回调中的 `flv_url`（包含本机局域网 IP，其他机器可直接访问）。

### 6. 主动关闭（触发 stopped 回调）

```bash
curl "http://localhost/index/api/delStreamProxy?secret=035c73f7-bb6b-4889-a715-d9eb2d1925cc&key=__defaultVhost__/live/test1"
```

调试服务会收到 `on_stream_proxy_stopped` 回调，`err` 字段为 `"closed by user"` 或 `"player proxy destroyed"`。

---

## 预期日志输出

```
[/on_stream_proxy_started]
  {
    "app": "live",
    "flv_url": "http://192.168.1.100/live/test1.live.flv",
    "key": "__defaultVhost__/live/test1",
    "stream": "test1",
    "url": "http://127.0.0.1/live/test/hls.m3u8",
    ...
  }
[ffprobe] start  key=__defaultVhost__/live/test1  url=http://192.168.1.100/live/test1.live.flv
[ffprobe] key=__defaultVhost__/live/test1
  {
    "streams": [...],
    "format": {...}
  }

[/on_stream_proxy_stopped]
  {
    "err": "closed by user",
    "key": "__defaultVhost__/live/test1",
    ...
  }
```
