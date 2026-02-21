# RtmpSession 类详解

## 1. 类概述

`RtmpSession` 是 RTMP 服务器的核心会话类，位于 `src/Rtmp/RtmpSession.h`，同时处理：
- **RTMP 推流**（publish 命令）
- **RTMP 播放**（play 命令）
- **RTMP 握手**（C0C1C2/S0S1S2）
- **AMF 命令解析**（connect/createStream/publish/play 等）

---

## 2. 继承关系

```
toolkit::Session    (网络会话基类)
    └── RtmpSession
            ├── RtmpProtocol    (RTMP chunk 协议解析)
            └── MediaSourceEvent (媒体源事件接口)
```

---

## 3. 成员变量

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `_push_src` | `RtmpMediaSourceImp::Ptr` | 推流时创建的媒体源 |
| `_push_src_ownership` | `shared_ptr<void>` | 推流源所有权 |
| `_play_src` | `weak_ptr<RtmpMediaSource>` | 播放时绑定的媒体源 |
| `_ring_reader` | `RingReader::Ptr` | 播放时的环形缓冲读取器 |
| `_push_metadata` | `AMFValue` | 推流的 metadata |
| `_push_config_packets` | `map<uint8_t, RtmpPacket::Ptr>` | 推流的配置包（SPS/PPS/AAC config） |
| `_recv_req_id` | `double` | 当前请求的 transaction ID |
| `_ticker` | `Ticker` | 超时计时器 |
| `_media_info` | `MediaInfo` | 解析后的 URL 信息 |
| `_total_bytes` | `uint64_t` | 累计流量 |
| `_continue_push_ms` | `uint32_t` | 断连续推等待时间 |
| `_set_meta_data` | `bool` | 是否已设置 metadata |

---

## 4. RTMP 握手流程

```
客户端 → C0(1字节版本) + C1(1536字节随机数+时间戳)
服务端 → S0(1字节版本) + S1(1536字节) + S2(echo C1)
客户端 → C2(echo S1)
握手完成
```

ZLMediaKit 的握手实现在 `RtmpProtocol` 中，支持简单握手和复杂握手（带 HMAC 验证）。

---

## 5. RTMP Chunk 协议

RTMP 将数据分割为 Chunk 传输，每个 Chunk 包含：
- **Basic Header**（1-3 字节）：Chunk Stream ID + Chunk Type
- **Message Header**（0/3/7/11 字节）：时间戳、消息长度、消息类型、Stream ID
- **Extended Timestamp**（可选 4 字节）
- **Chunk Data**：实际数据（最大 `chunk_size` 字节）

`RtmpProtocol::onRtmpChunk()` 负责将 Chunk 重组为完整的 RTMP 消息。

---

## 6. 核心函数详解

### 6.1 `onCmd_connect()` — 处理 connect 命令

```cpp
void onCmd_connect(AMFDecoder &dec);
```

**处理逻辑：**
1. 解析 AMF 对象，提取 `app`、`tcUrl` 等字段
2. 解析 `tcUrl` 获取 vhost/app 信息
3. 回复 `_result`（连接成功）
4. 发送 `Window Acknowledgement Size` 和 `Set Peer Bandwidth`

---

### 6.2 `onCmd_publish()` — 处理 publish 命令

```cpp
void onCmd_publish(AMFDecoder &dec);
```

**处理逻辑：**
1. 解析 stream name（可能包含 `?` 参数）
2. 触发 `kBroadcastMediaPublish` 事件（WebHook on_publish 鉴权）
3. 鉴权成功后，创建 `RtmpMediaSourceImp`
4. 回复 `onStatus(NetStream.Publish.Start)`

---

### 6.3 `onCmd_play()` — 处理 play 命令

```cpp
void onCmd_play(AMFDecoder &dec);
```

**处理逻辑：**
1. 解析 stream name
2. 调用 `MediaSource::findAsync()` 查找流
3. 触发 `kBroadcastMediaPlayed` 事件（WebHook on_play 鉴权）
4. 鉴权成功后，创建 `RingReader`
5. 发送 `onStatus(NetStream.Play.Start)` + metadata + 配置包（SPS/PPS/AAC config）
6. 开始发送 FLV Tag 数据

---

### 6.4 `onCmd_seek()` — 处理 seek 命令

```cpp
void onCmd_seek(AMFDecoder &dec);
```

**处理逻辑：**
1. 提取 seek 时间戳（毫秒）
2. 调用 `MediaSource::seekTo(stamp)` 通知推流端（点播用）
3. 重新创建 `RingReader`，从新位置开始读取

---

### 6.5 `onCmd_pause()` — 处理 pause 命令

```cpp
void onCmd_pause(AMFDecoder &dec);
```

**处理逻辑：**
1. 解析暂停/恢复标志
2. 调用 `MediaSource::pause(pause)` 通知推流端
3. 暂停时停止发送数据，恢复时重新开始

---

### 6.6 `onSendMedia()` — 发送媒体数据给播放器

```cpp
void onSendMedia(const RtmpPacket::Ptr &pkt);
```

从 `RingBuffer` 读取 FLV Tag，通过 RTMP Chunk 发送给播放器。

---

### 6.7 `setMetaData()` — 处理 metadata

```cpp
void setMetaData(AMFDecoder &dec);
```

解析推流端发送的 `@setDataFrame` 命令，提取 metadata（宽高、帧率、编码类型等）。

---

## 7. AMF 编解码

RTMP 使用 AMF（Action Message Format）编码命令和数据：

**AMF0 数据类型：**
| 类型 | 标识 | 说明 |
|------|------|------|
| Number | 0x00 | 64位浮点数 |
| Boolean | 0x01 | 布尔值 |
| String | 0x02 | UTF-8 字符串 |
| Object | 0x03 | 键值对对象 |
| Null | 0x05 | 空值 |
| Array | 0x08 | 混合数组 |
| StrictArray | 0x0A | 严格数组 |

**示例：** `connect` 命令的 AMF 编码：
```
"connect"  (String)
1.0        (Number, transaction ID)
{          (Object)
  "app": "live",
  "tcUrl": "rtmp://localhost/live",
  "flashVer": "FMLE/3.0"
}
```

---

## 8. 断连续推机制

ZLMediaKit 支持推流断开后在一定时间内重新连接，播放器不会断开：

1. 推流断开时，`_push_src` 不立即销毁，而是等待 `continue_push_ms` 毫秒
2. 在等待期间，播放器继续播放（可能会卡顿）
3. 若在等待时间内重新推流，`_push_src` 被复用，播放器无感知
4. 超时后，`_push_src` 销毁，播放器断开

---

## 9. 调用链

### 推流调用链
```
TCP连接 → RtmpSession 构造
    → RTMP握手
    → 收到 connect → onCmd_connect()
    → 收到 createStream → onCmd_createStream()
    → 收到 publish → onCmd_publish()
        → kBroadcastMediaPublish → WebHook on_publish
        → 创建 RtmpMediaSourceImp
    → 收到 @setDataFrame → setMetaData()
    → 收到 Video/Audio Chunk → onRtmpChunk()
        → RtmpDemuxer::inputRtmp()
        → 解码为 Frame
        → Track::inputFrame()
        → MultiMediaSourceMuxer::onTrackFrame()
```

### 播放调用链
```
TCP连接 → RtmpSession 构造
    → RTMP握手
    → 收到 connect → onCmd_connect()
    → 收到 createStream → onCmd_createStream()
    → 收到 play → onCmd_play()
        → MediaSource::findAsync()
        → kBroadcastMediaPlayed → WebHook on_play
        → 创建 RingReader
        → 发送 metadata + 配置包
    → RingBuffer 有新数据 → onSendMedia()
        → 发送 RTMP Chunk 给播放器
```
