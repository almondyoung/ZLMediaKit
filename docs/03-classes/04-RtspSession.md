# RtspSession 类详解

## 1. 类概述

`RtspSession` 是 RTSP 服务器的核心会话类，位于 `src/Rtsp/RtspSession.h`，同时处理：
- **RTSP 推流**（ANNOUNCE + RECORD）
- **RTSP 播放**（DESCRIBE + SETUP + PLAY）
- **RTP over TCP/UDP/组播**
- **RTSP over HTTP**（QuickTime 兼容）
- **RTSP 认证**（Basic/Digest）

---

## 2. 继承关系

```
toolkit::Session          (网络会话基类，管理 Socket)
    └── RtspSession
            ├── RtspSplitter      (RTSP 报文分割)
            ├── RtpReceiver       (RTP 包排序重组)
            └── MediaSourceEvent  (媒体源事件接口)
```

---

## 3. 成员变量

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `_push_src` | `RtspMediaSourceImp::Ptr` | 推流时创建的媒体源 |
| `_push_src_ownership` | `shared_ptr<void>` | 推流源所有权（防止被替换） |
| `_play_src` | `weak_ptr<RtspMediaSource>` | 播放时绑定的媒体源 |
| `_play_reader` | `RingReader::Ptr` | 播放时的环形缓冲读取器 |
| `_sdp_track` | `vector<SdpTrack::Ptr>` | SDP 中的轨道描述 |
| `_rtp_type` | `eRtpType` | RTP 传输方式（TCP/UDP/组播） |
| `_sessionid` | `string` | RTSP Session ID |
| `_cseq` | `int` | 当前请求的 CSeq |
| `_media_info` | `MediaInfo` | 解析后的 URL 信息 |
| `_rtp_socks[2]` | `Socket::Ptr` | RTP over UDP 的 Socket（视频/音频） |
| `_rtcp_socks[2]` | `Socket::Ptr` | RTCP over UDP 的 Socket |
| `_rtcp_context` | `vector<RtcpContext::Ptr>` | RTCP 统计上下文 |
| `_rtsp_realm` | `string` | RTSP 认证 realm |
| `_auth_nonce` | `string` | Digest 认证 nonce |
| `_alive_ticker` | `Ticker` | 心跳超时计时器 |
| `_continue_push_ms` | `uint32_t` | 断连续推等待时间 |
| `_bytes_usage` | `uint64_t` | 累计流量 |
| `_emit_on_play` | `bool` | 是否已触发 on_play 事件 |
| `_multicaster` | `RtpMultiCaster::Ptr` | 组播对象 |

---

## 4. 核心函数详解

### 4.1 RTSP 方法处理

#### `handleReq_Options()`
处理 `OPTIONS` 请求，返回服务器支持的方法列表：
```
OPTIONS, DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE, ANNOUNCE, RECORD, SET_PARAMETER, GET_PARAMETER
```

#### `handleReq_Describe()`
处理 `DESCRIBE` 请求（播放流程第一步）：
1. 解析 URL，提取 vhost/app/stream
2. 调用 `MediaSource::findAsync()` 查找流（支持等待）
3. 触发 `kBroadcastMediaPlayed` 事件（WebHook on_play 鉴权）
4. 鉴权成功后，返回 `200 OK` + SDP

#### `handleReq_ANNOUNCE()`
处理 `ANNOUNCE` 请求（推流流程第一步）：
1. 解析 SDP，提取轨道信息
2. 触发 `kBroadcastMediaPublish` 事件（WebHook on_publish 鉴权）
3. 鉴权成功后，创建 `RtspMediaSourceImp`

#### `handleReq_Setup()`
处理 `SETUP` 请求（协商 RTP 传输方式）：
1. 解析 `Transport` 头，确定传输方式（TCP/UDP/组播）
2. TCP 模式：分配 interleaved channel
3. UDP 模式：创建 UDP Socket，绑定端口
4. 组播模式：分配组播地址和端口
5. 返回 `200 OK` + Transport 信息

#### `handleReq_Play()`
处理 `PLAY` 请求（开始播放）：
1. 查找 `RtspMediaSource`
2. 创建 `RingReader`，从 GOP 缓存开始读取
3. 设置回调：新数据到来时调用 `sendRtpPacket()`
4. 返回 `200 OK` + RTP-Info

#### `handleReq_RECORD()`
处理 `RECORD` 请求（开始推流）：
1. 确认 `_push_src` 已创建
2. 开始接收 RTP 包

#### `handleReq_Teardown()`
处理 `TEARDOWN` 请求（结束会话）：
1. 关闭 RTP/RTCP Socket
2. 触发流量统计事件
3. 关闭 Session

---

### 4.2 RTP 数据处理

#### `onRtpPacket()` — 收到 RTP 包（TCP 模式）

```cpp
void onRtpPacket(const char *data, size_t len) override;
```

处理 RTP over TCP 的 interleaved 数据，提取 RTP 包并传给 `RtpReceiver`。

#### `onRtpSorted()` — RTP 包排序完成

```cpp
void onRtpSorted(RtpPacket::Ptr rtp, int track_idx) override;
```

RTP 包经过排序重组后的回调，将 RTP 包传给 `_push_src`（推流媒体源）进行解码。

#### `sendRtpPacket()` — 发送 RTP 包给播放器

```cpp
void sendRtpPacket(const RtspMediaSource::RingDataType &pkt);
```

从 `RingBuffer` 读取 RTP 包，通过 TCP 或 UDP 发送给播放器。

---

### 4.3 RTSP 认证

ZLMediaKit 支持两种 RTSP 认证方式：

**Basic 认证（Base64）：**
```
Authorization: Basic base64(username:password)
```

**Digest 认证（MD5）：**
```
Authorization: Digest username="xxx", realm="xxx", nonce="xxx", uri="xxx", response="md5hash"
```

**认证流程：**
```
客户端请求 DESCRIBE
    → 服务器触发 kBroadcastOnGetRtspRealm 事件
    → WebHook on_rtsp_realm 返回 realm（非空则需要认证）
    → 服务器返回 401 Unauthorized + WWW-Authenticate
    → 客户端重新请求，携带 Authorization 头
    → 服务器触发 kBroadcastOnRtspAuth 事件
    → WebHook on_rtsp_auth 返回密码
    → 服务器验证密码
    → 认证成功/失败
```

---

### 4.4 RTSP over HTTP

QuickTime 等客户端使用 RTSP over HTTP 方式：
1. 客户端发送 HTTP GET 请求，携带 `x-sessioncookie` 头
2. 客户端发送 HTTP POST 请求，携带相同的 `x-sessioncookie`
3. 服务器通过 `x-sessioncookie` 将两个 TCP 连接关联
4. GET 连接用于接收 RTSP 响应，POST 连接用于发送 RTSP 请求

---

## 5. RTP 传输模式

| 模式 | 说明 | 优缺点 |
|------|------|--------|
| `RTP_TCP` | RTP over TCP（interleaved） | 穿透性好，延迟稍高 |
| `RTP_UDP` | RTP over UDP | 低延迟，可能被防火墙阻断 |
| `RTP_MULTICAST` | RTP 组播 | 适合大规模分发，需要网络支持 |

---

## 6. 调用链

### 推流调用链
```
TCP连接建立 → RtspSession 构造
    → 收到 ANNOUNCE → handleReq_ANNOUNCE()
        → kBroadcastMediaPublish → WebHook on_publish
        → 创建 RtspMediaSourceImp
    → 收到 SETUP → handleReq_Setup()
        → 协商 RTP 传输方式
    → 收到 RECORD → handleReq_RECORD()
        → 开始接收 RTP
    → 收到 RTP 数据 → onRtpPacket()
        → RtpReceiver 排序 → onRtpSorted()
        → RtspMediaSourceImp::onRtp()
        → RtpCodec 解码 → Frame
        → Track::inputFrame()
        → MultiMediaSourceMuxer::onTrackFrame()
```

### 播放调用链
```
TCP连接建立 → RtspSession 构造
    → 收到 DESCRIBE → handleReq_Describe()
        → MediaSource::findAsync()
        → kBroadcastMediaPlayed → WebHook on_play
        → 返回 SDP
    → 收到 SETUP → handleReq_Setup()
    → 收到 PLAY → handleReq_Play()
        → 创建 RingReader
        → 设置数据回调
    → RingBuffer 有新数据 → sendRtpPacket()
        → 发送 RTP 给播放器
```
