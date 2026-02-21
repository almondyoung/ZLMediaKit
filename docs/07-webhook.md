# WebHook 回调事件

## 1. WebHook 概述

WebHook 是 ZLMediaKit 与业务服务器交互的核心机制。当特定事件发生时，ZLMediaKit 会向配置的 URL 发送 HTTP POST 请求，业务服务器通过响应来控制 ZLMediaKit 的行为（如鉴权、关闭流等）。

### 1.1 通用请求格式

所有 WebHook 请求均为 HTTP POST，Content-Type 为 `application/json`。

**通用字段（所有请求都包含）：**
```json
{
  "mediaServerId": "your-server-id",
  "hook_index": 12345
}
```

### 1.2 通用响应格式

```json
{
  "code": 0,
  "msg": "success"
}
```

- `code = 0`：操作成功/允许
- `code != 0`：操作失败/拒绝，`msg` 为错误原因

### 1.3 配置方式

```ini
[hook]
enable=1
timeoutSec=10
retry=1
retry_delay=3.0
on_publish=http://your-server/on_publish
on_play=http://your-server/on_play
# ... 其他事件
```

---

## 2. 所有 WebHook 事件

### 2.1 on_publish — 推流鉴权

**触发时机：** 推流端（RTSP/RTMP/RTP/WebRTC/SRT）开始推流时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtmp",
  "protocol": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "params": "token=abc123",
  "ip": "192.168.1.100",
  "port": 12345,
  "id": "session-id",
  "originType": 1,
  "originTypeStr": "rtmp_push"
}
```

**响应体：**
```json
{
  "code": 0,
  "msg": "success",
  // 可选：覆盖转协议配置
  "enable_hls": 1,
  "enable_mp4": 0,
  "enable_rtsp": 1,
  "enable_rtmp": 1,
  "mp4_save_path": "/data/record",
  "mp4_max_second": 3600,
  "modify_stamp": 2,
  "stream_replace": ""  // 可替换 stream_id
}
```

**鉴权失败响应：**
```json
{
  "code": -1,
  "msg": "unauthorized"
}
```

---

### 2.2 on_play — 播放鉴权

**触发时机：** 播放器（RTSP/RTMP/HTTP-FLV/WebRTC 等）开始播放时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtsp",
  "protocol": "rtsp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "params": "token=abc123",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id"
}
```

**响应体：**
```json
{
  "code": 0,
  "msg": "success"
}
```

---

### 2.3 on_stream_changed — 流注册/注销

**触发时机：** 流注册（推流成功）或注销（推流结束）时

**注册请求体：**
```json
{
  "mediaServerId": "xxx",
  "regist": true,
  "schema": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "originType": 1,
  "originTypeStr": "rtmp_push",
  "originUrl": "rtmp://localhost/live/mystream",
  "createStamp": 1700000000,
  "aliveSecond": 0,
  "bytesSpeed": 0,
  "tracks": [
    {
      "codec_id": 0,
      "codec_id_name": "H264",
      "ready": true,
      "frames": 0,
      "key_frames": 0,
      "type": 0,
      "width": 1920,
      "height": 1080,
      "fps": 25.0,
      "bit_rate": 2000000
    },
    {
      "codec_id": 2,
      "codec_id_name": "mpeg4-generic",
      "ready": true,
      "type": 1,
      "sample_rate": 44100,
      "channels": 2,
      "sample_bit": 16,
      "bit_rate": 128000
    }
  ]
}
```

**注销请求体：**
```json
{
  "mediaServerId": "xxx",
  "regist": false,
  "schema": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream"
}
```

**响应体：** 无需特定响应，返回 `{"code": 0}` 即可

**配置过滤协议：**
```ini
[hook]
# 只监听 rtsp 和 rtmp 的流变化，忽略 hls/fmp4/ts 等
stream_changed_schemas=rtsp/rtmp
```

---

### 2.4 on_stream_not_found — 流未找到

**触发时机：** 播放器请求的流不存在时（等待超时后触发）

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "params": "",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id"
}
```

**响应体：**
```json
{
  "code": 0,
  "close": false  // true=立即关闭播放器，false=继续等待
}
```

**典型用法：** 收到此事件后，调用 `addStreamProxy` API 拉流，然后返回 `{"code": 0, "close": false}`，播放器会等待流就绪。

---

### 2.5 on_stream_none_reader — 无人观看

**触发时机：** 流无人观看超过 `streamNoneReaderDelayMS`（默认 20 秒）后触发

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream"
}
```

**响应体：**
```json
{
  "code": 0,
  "close": true  // true=关闭流，false=保持流
}
```

**典型用法：** 对于拉流代理，无人观看时关闭拉流，节省带宽。

---

### 2.6 on_record_mp4 — MP4 录制完成

**触发时机：** 一个 MP4 文件录制完成时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "start_time": 1700000000,
  "time_len": 3600.0,
  "file_size": 1073741824,
  "file_path": "/data/record/live/mystream/2024-01-01/10-00-00.mp4",
  "file_name": "10-00-00.mp4",
  "folder": "/data/record/live/mystream/2024-01-01/",
  "url": "live/mystream/2024-01-01/10-00-00.mp4"
}
```

**响应体：** 无需特定响应

---

### 2.7 on_record_ts — HLS TS 切片录制完成

**触发时机：** 一个 HLS TS 切片文件写入完成时

**请求体：** 与 `on_record_mp4` 格式相同

---

### 2.8 on_flow_report — 流量统计

**触发时机：** 播放器或推流端断开连接，且流量超过 `flowThreshold`（默认 1MB）时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtmp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "params": "",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id",
  "totalBytes": 10485760,
  "duration": 120,
  "player": true
}
```

**字段说明：**
- `totalBytes`：总流量（字节）
- `duration`：连接时长（秒）
- `player`：true=播放器，false=推流端

---

### 2.9 on_rtsp_realm — RTSP 认证域

**触发时机：** RTSP 客户端请求时，决定是否需要认证

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtsp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "params": "",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id"
}
```

**响应体：**
```json
{
  "code": 0,
  "realm": "ZLMediaKit"  // 非空则需要认证，空则不需要
}
```

---

### 2.10 on_rtsp_auth — RTSP 认证密码

**触发时机：** RTSP 客户端提供认证信息后，需要验证密码时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "schema": "rtsp",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id",
  "user_name": "admin",
  "must_no_encrypt": false,
  "realm": "ZLMediaKit"
}
```

**响应体：**
```json
{
  "code": 0,
  "encrypted": false,  // false=明文密码，true=MD5密码
  "passwd": "123456"   // 密码
}
```

---

### 2.11 on_http_access — HTTP 文件访问鉴权

**触发时机：** HTTP 客户端访问文件或目录时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "ip": "192.168.1.200",
  "port": 54321,
  "id": "session-id",
  "path": "/www/record/live/test/2024-01-01/",
  "is_dir": true,
  "params": "token=abc123"
}
```

**响应体：**
```json
{
  "code": 0,
  "err": "",
  "path": "",        // 可选：重定向到其他路径
  "second": 300      // Cookie 有效期（秒），0=不使用 Cookie
}
```

---

### 2.12 on_server_started — 服务器启动

**触发时机：** ZLMediaKit 服务器启动完成时

**请求体：** 包含所有配置项的 JSON 对象（config.ini 的内容）

---

### 2.13 on_server_exited — 服务器退出

**触发时机：** ZLMediaKit 服务器正常退出时

**请求体：** 空 JSON 对象 `{}`

---

### 2.14 on_server_keepalive — 服务器保活

**触发时机：** 每隔 `alive_interval`（默认 30 秒）触发一次

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "data": {
    "Buffer": {"BufferList": 0, "BufferRaw": 100, ...},
    "Frame": {"FrameImp": 500, ...},
    "MediaSource": {"HlsMediaSource": 2, "RtmpMediaSource": 1, ...},
    "Session": {"HttpSession": 5, "RtmpSession": 1, ...},
    "TcpServer": {"TcpServer": 4}
  }
}
```

---

### 2.15 on_send_rtp_stopped — RTP 发送停止

**触发时机：** GB28181 RTP 发送任务停止时（正常停止或异常断开）

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "mystream",
  "ssrc": "1",
  "originType": 1,
  "originTypeStr": "rtmp_push",
  "originUrl": "rtmp://localhost/live/mystream",
  "msg": "Connection reset by peer",
  "err": 104
}
```

---

### 2.16 on_rtp_server_timeout — RTP 服务器超时

**触发时机：** 通过 `openRtpServer` 开启的 RTP 接收端口超时无数据时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "local_port": 10001,
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "camera01",
  "tcp_mode": 0,
  "re_use_port": false,
  "ssrc": 0
}
```

---

### 2.17 on_shell_login — Shell 登录鉴权

**触发时机：** 通过 Shell 接口（端口 9000）登录时

**请求体：**
```json
{
  "mediaServerId": "xxx",
  "ip": "127.0.0.1",
  "port": 12345,
  "id": "session-id",
  "user_name": "admin",
  "passwd": "123456"
}
```

**响应体：**
```json
{
  "code": 0,
  "msg": ""  // 空=允许，非空=拒绝原因
}
```

---

## 3. WebHook 配置示例

### 3.1 完整配置

```ini
[hook]
enable=1
timeoutSec=10
retry=1
retry_delay=3.0
alive_interval=30

on_publish=http://localhost:8080/on_publish
on_play=http://localhost:8080/on_play
on_stream_changed=http://localhost:8080/on_stream_changed
on_stream_not_found=http://localhost:8080/on_stream_not_found
on_stream_none_reader=http://localhost:8080/on_stream_none_reader
on_record_mp4=http://localhost:8080/on_record_mp4
on_record_ts=http://localhost:8080/on_record_ts
on_flow_report=http://localhost:8080/on_flow_report
on_rtsp_realm=http://localhost:8080/on_rtsp_realm
on_rtsp_auth=http://localhost:8080/on_rtsp_auth
on_http_access=http://localhost:8080/on_http_access
on_server_started=http://localhost:8080/on_server_started
on_server_exited=http://localhost:8080/on_server_exited
on_server_keepalive=http://localhost:8080/on_server_keepalive
on_send_rtp_stopped=http://localhost:8080/on_send_rtp_stopped
on_rtp_server_timeout=http://localhost:8080/on_rtp_server_timeout
on_shell_login=http://localhost:8080/on_shell_login

# 只监听 rtsp 和 rtmp 的流变化事件
stream_changed_schemas=rtsp/rtmp
```

### 3.2 业务服务器示例（Python/Flask）

```python
from flask import Flask, request, jsonify
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# 推流鉴权：验证 token
@app.route('/on_publish', methods=['POST'])
def on_publish():
    data = request.json
    token = data.get('params', '').replace('token=', '')
    
    if token == 'valid_token':
        return jsonify({
            "code": 0,
            "enable_mp4": 1,  # 开启 MP4 录制
            "mp4_save_path": f"/data/record/{data['app']}"
        })
    else:
        return jsonify({"code": -1, "msg": "Invalid token"})

# 播放鉴权：验证 token
@app.route('/on_play', methods=['POST'])
def on_play():
    data = request.json
    token = data.get('params', '').replace('token=', '')
    
    if token == 'valid_token':
        return jsonify({"code": 0})
    else:
        return jsonify({"code": -1, "msg": "Unauthorized"})

# 流变化通知：记录日志
@app.route('/on_stream_changed', methods=['POST'])
def on_stream_changed():
    data = request.json
    action = "上线" if data['regist'] else "下线"
    logging.info(f"流{action}: {data['schema']}://{data['app']}/{data['stream']}")
    return jsonify({"code": 0})

# 流未找到：触发按需拉流
@app.route('/on_stream_not_found', methods=['POST'])
def on_stream_not_found():
    data = request.json
    stream = data['stream']
    
    # 根据 stream_id 查找对应的摄像头 RTSP 地址
    camera_url = get_camera_url(stream)
    if camera_url:
        # 调用 ZLMediaKit API 拉流
        import requests
        requests.post('http://localhost/index/api/addStreamProxy', json={
            "secret": "your-secret",
            "vhost": "__defaultVhost__",
            "app": data['app'],
            "stream": stream,
            "url": camera_url,
            "retry_count": -1
        })
        return jsonify({"code": 0, "close": False})
    else:
        return jsonify({"code": 0, "close": True})

# 无人观看：关闭拉流
@app.route('/on_stream_none_reader', methods=['POST'])
def on_stream_none_reader():
    data = request.json
    logging.info(f"无人观看: {data['app']}/{data['stream']}")
    return jsonify({"code": 0, "close": True})

# MP4 录制完成：移动文件
@app.route('/on_record_mp4', methods=['POST'])
def on_record_mp4():
    data = request.json
    logging.info(f"录制完成: {data['file_path']}, 时长: {data['time_len']}秒")
    # 可以在这里移动文件、更新数据库等
    return jsonify({"code": 0})

# 流量统计：计费
@app.route('/on_flow_report', methods=['POST'])
def on_flow_report():
    data = request.json
    role = "播放" if data['player'] else "推流"
    logging.info(f"{role}流量: {data['totalBytes']} bytes, 时长: {data['duration']}秒, IP: {data['ip']}")
    return jsonify({"code": 0})

def get_camera_url(stream_id):
    # 从数据库查询摄像头地址
    camera_map = {
        "camera01": "rtsp://192.168.1.101/stream",
        "camera02": "rtsp://192.168.1.102/stream",
    }
    return camera_map.get(stream_id)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

---

## 4. WebHook 重试机制

当 WebHook 请求失败时（网络错误或 HTTP 状态码非 200），ZLMediaKit 会按以下策略重试：

```ini
[hook]
retry=1          # 重试次数（0=不重试，1=重试1次）
retry_delay=3.0  # 重试间隔（秒）
```

**注意：** 对于鉴权类 WebHook（`on_publish`、`on_play`），若所有重试都失败，ZLMediaKit 会**允许**操作（默认行为），以避免因 WebHook 服务器故障导致服务中断。

---

## 5. WebHook 与 Python 插件的优先级

若同时启用了 Python 插件和 WebHook，Python 插件优先处理：

```python
def on_publish(type, args, invoker, sender):
    # 如果 Python 插件返回 True，则不再触发 WebHook
    if some_condition:
        invoker('', {})  # 允许推流
        return True      # 阻止 WebHook 触发
    return False         # 继续触发 WebHook
```
