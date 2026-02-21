# 协议与格式专项分析

## 1. 支持的协议总览

| 协议 | 推流 | 播放 | 默认端口 | 说明 |
|------|------|------|----------|------|
| RTSP | ✅ | ✅ | 554 | 支持 TCP/UDP/组播 |
| RTSPS | ✅ | ✅ | 332 | RTSP over TLS |
| RTMP | ✅ | ✅ | 1935 | 支持 H264/H265/AAC/Opus |
| RTMPS | ✅ | ✅ | 19350 | RTMP over TLS |
| HTTP-FLV | ❌ | ✅ | 80 | 基于 HTTP 长连接 |
| HTTPS-FLV | ❌ | ✅ | 443 | FLV over HTTPS |
| WS-FLV | ❌ | ✅ | 80 | FLV over WebSocket |
| WSS-FLV | ❌ | ✅ | 443 | FLV over WSS |
| HLS | ❌ | ✅ | 80 | m3u8 + ts 切片 |
| HLS-FMP4 | ❌ | ✅ | 80 | m3u8 + fmp4 切片 |
| HTTP-FMP4 | ❌ | ✅ | 80 | Fragmented MP4 |
| WS-FMP4 | ❌ | ✅ | 80 | FMP4 over WebSocket |
| HTTP-TS | ❌ | ✅ | 80 | MPEG-TS over HTTP |
| WS-TS | ❌ | ✅ | 80 | TS over WebSocket |
| WebRTC | ✅ | ✅ | UDP | 超低延迟 |
| SRT | ✅ | ✅ | 9000 | 可靠 UDP 传输 |
| GB28181 RTP | ✅ | ❌ | 10000 | 国标 RTP 接收 |
| GB28181 RTP 发送 | ❌ | ✅ | 动态 | 国标 RTP 回传 |

---

## 2. 各协议支持的编解码格式

### 2.1 视频编解码

| 编解码 | RTSP | RTMP | HLS | WebRTC | SRT | GB28181 |
|--------|------|------|-----|--------|-----|---------|
| H.264 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| H.265/HEVC | ✅ | ✅(增强) | ✅ | ❌ | ✅ | ✅ |
| VP8 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| VP9 | ✅ | ✅(增强) | ❌ | ✅ | ❌ | ❌ |
| AV1 | ✅ | ✅(增强) | ❌ | ❌ | ❌ | ❌ |
| JPEG | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |

### 2.2 音频编解码

| 编解码 | RTSP | RTMP | HLS | WebRTC | SRT | GB28181 |
|--------|------|------|-----|--------|-----|---------|
| AAC | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| G.711A (PCMA) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| G.711U (PCMU) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Opus | ✅ | ✅(增强) | ❌ | ✅ | ✅ | ❌ |
| MP3 | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| G.722 | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| G.729 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 3. RTSP 协议实现

### 3.1 协议概述

RTSP（Real Time Streaming Protocol）是一个应用层协议，用于控制媒体流的传输。RTSP 本身不传输媒体数据，而是通过 RTP/RTCP 传输。

### 3.2 RTSP 方法

| 方法 | 说明 | 推流/播放 |
|------|------|-----------|
| OPTIONS | 查询服务器支持的方法 | 两者 |
| DESCRIBE | 获取流的 SDP 描述 | 播放 |
| ANNOUNCE | 推送 SDP 描述 | 推流 |
| SETUP | 协商 RTP 传输参数 | 两者 |
| PLAY | 开始播放 | 播放 |
| RECORD | 开始推流 | 推流 |
| PAUSE | 暂停 | 播放 |
| TEARDOWN | 结束会话 | 两者 |
| SET_PARAMETER | 设置参数（心跳） | 两者 |
| GET_PARAMETER | 获取参数（心跳） | 两者 |

### 3.3 RTP 传输模式

**TCP 模式（Interleaved）：**
```
SETUP rtsp://host/app/stream/track0 RTSP/1.0
Transport: RTP/AVP/TCP;unicast;interleaved=0-1

# RTP 数据通过 RTSP TCP 连接传输
# 格式: $ + channel(1字节) + length(2字节) + RTP数据
```

**UDP 模式：**
```
SETUP rtsp://host/app/stream/track0 RTSP/1.0
Transport: RTP/AVP;unicast;client_port=8000-8001

# 服务器回复分配的端口
Transport: RTP/AVP;unicast;client_port=8000-8001;server_port=9000-9001
```

**组播模式：**
```
SETUP rtsp://host/app/stream/track0 RTSP/1.0
Transport: RTP/AVP;multicast

# 服务器回复组播地址和端口
Transport: RTP/AVP;multicast;destination=239.1.1.1;port=5000-5001;ttl=32
```

### 3.4 SDP 格式示例

```sdp
v=0
o=- 0 0 IN IP4 127.0.0.1
s=ZLMediaKit
c=IN IP4 0.0.0.0
t=0 0
a=control:*

m=video 0 RTP/AVP 96
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1;sprop-parameter-sets=Z0IAKeKQFAe2AtwEBAaQeJEV,aM48gA==
a=control:track0

m=audio 0 RTP/AVP 97
a=rtpmap:97 mpeg4-generic/44100/2
a=fmtp:97 streamtype=5;profile-level-id=1;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3;config=1210
a=control:track1
```

### 3.5 H264 RTP 打包模式

| 模式 | 说明 | 适用场景 |
|------|------|----------|
| Single NAL Unit | 一个 RTP 包含一个 NALU | NALU < MTU |
| STAP-A | 一个 RTP 包含多个小 NALU | 多个小 NALU 合并 |
| FU-A | 一个 NALU 分割为多个 RTP 包 | NALU > MTU |

ZLMediaKit 默认使用 FU-A 模式分割大 NALU，可通过 `rtp.h264StapA=1` 启用 STAP-A 模式。

---

## 4. RTMP 协议实现

### 4.1 协议概述

RTMP（Real-Time Messaging Protocol）是 Adobe 开发的流媒体协议，基于 TCP，使用 Chunk 分块传输。

### 4.2 Chunk 结构

```
Basic Header (1-3 字节)
    ├── fmt (2 bits): Chunk Type (0/1/2/3)
    └── cs_id (6 bits): Chunk Stream ID

Message Header (0/3/7/11 字节，取决于 fmt)
    ├── timestamp (3 字节)
    ├── message_length (3 字节)
    ├── message_type_id (1 字节)
    └── message_stream_id (4 字节, 仅 fmt=0)

Extended Timestamp (4 字节, 可选)

Chunk Data (最大 chunk_size 字节)
```

### 4.3 消息类型

| 类型 ID | 说明 |
|---------|------|
| 1 | Set Chunk Size |
| 2 | Abort Message |
| 3 | Acknowledgement |
| 4 | User Control Message |
| 5 | Window Acknowledgement Size |
| 6 | Set Peer Bandwidth |
| 8 | Audio Data |
| 9 | Video Data |
| 15 | AMF3 Data Message |
| 17 | AMF3 Command Message |
| 18 | AMF0 Data Message |
| 20 | AMF0 Command Message |

### 4.4 H265 RTMP 扩展

标准 RTMP 不支持 H265，ZLMediaKit 支持两种扩展方式：

**国内扩展（codecId=12）：**
```
Video Tag Header:
    FrameType (4 bits) + CodecID (4 bits, 12=H265)
```

**增强型 RTMP（Enhanced RTMP）：**
```
Video Tag Header:
    IsExHeader (1 bit) = 1
    FrameType (3 bits)
    PacketType (4 bits)
    FourCC (4 bytes) = "hvc1"
```

配置 `rtmp.enhanced=1` 使用增强型 RTMP。

---

## 5. HLS 协议实现

### 5.1 协议概述

HLS（HTTP Live Streaming）是 Apple 开发的流媒体协议，将流切割为 TS 文件，通过 HTTP 传输。

### 5.2 文件结构

```
直播 m3u8（滚动窗口）:
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-ALLOW-CACHE:NO
    #EXT-X-TARGETDURATION:2
    #EXT-X-MEDIA-SEQUENCE:100
    #EXTINF:2.000,
    100.ts
    #EXTINF:2.000,
    101.ts
    #EXTINF:2.000,
    102.ts

点播 m3u8（完整列表）:
    #EXTM3U
    #EXT-X-VERSION:3
    #EXT-X-TARGETDURATION:2
    #EXT-X-MEDIA-SEQUENCE:0
    #EXTINF:2.000,
    0.ts
    ...
    #EXT-X-ENDLIST
```

### 5.3 TS 文件格式

每个 TS 文件是 MPEG-TS 格式：
- 固定 188 字节的 TS 包
- 包含 PAT（Program Association Table）和 PMT（Program Map Table）
- 视频使用 PID 256，音频使用 PID 257

### 5.4 HLS-FMP4

ZLMediaKit 也支持 HLS-FMP4（`enable_hls_fmp4=1`）：
- 切片文件为 `.mp4` 格式（Fragmented MP4）
- m3u8 中包含 `#EXT-X-MAP` 指向初始化段
- 更好的浏览器兼容性，支持 H265

---

## 6. WebRTC 协议实现

### 6.1 协议栈

```
应用层: 媒体数据 (H264/VP8/Opus)
    ↓
SRTP/SRTCP (加密 RTP)
    ↓
DTLS (密钥协商)
    ↓
ICE (NAT 穿透)
    ↓
UDP
```

### 6.2 信令流程

```
浏览器 → ZLMediaKit: HTTP POST /index/api/webrtc (SDP Offer)
ZLMediaKit → 浏览器: SDP Answer
浏览器 ↔ ZLMediaKit: ICE 候选交换
浏览器 ↔ ZLMediaKit: DTLS 握手
浏览器 ↔ ZLMediaKit: SRTP 媒体传输
```

### 6.3 WebRTC 播放示例

```javascript
// 浏览器端 WebRTC 播放
const pc = new RTCPeerConnection();
pc.addTransceiver('video', {direction: 'recvonly'});
pc.addTransceiver('audio', {direction: 'recvonly'});

const offer = await pc.createOffer();
await pc.setLocalDescription(offer);

const response = await fetch('/index/api/webrtc?app=live&stream=test', {
    method: 'POST',
    body: offer.sdp
});
const answer = await response.text();
await pc.setRemoteDescription({type: 'answer', sdp: answer});

pc.ontrack = (event) => {
    document.getElementById('video').srcObject = event.streams[0];
};
```

---

## 7. SRT 协议实现

### 7.1 协议概述

SRT（Secure Reliable Transport）是基于 UDP 的可靠传输协议，具有：
- 低延迟（可配置）
- 丢包重传
- 加密支持（AES-128/256）
- 带宽估计和拥塞控制

### 7.2 推流 URL

```
srt://host:9000?streamid=live/mystream&latency=200&passphrase=secret
```

**参数说明：**
- `streamid`：流标识（格式：app/stream）
- `latency`：延迟缓冲（毫秒，默认 120ms）
- `passphrase`：加密密码（可选）

### 7.3 与 RTMP 的对比

| 特性 | RTMP | SRT |
|------|------|-----|
| 传输层 | TCP | UDP |
| 延迟 | 1-3 秒 | 0.1-1 秒 |
| 丢包处理 | TCP 重传 | SRT 重传 |
| 加密 | 无（RTMPS 有） | 内置 AES |
| 防火墙穿透 | 好（TCP） | 一般（UDP） |
| 带宽利用率 | 一般 | 高 |

---

## 8. GB28181 RTP 实现

### 8.1 协议概述

GB28181 是中国国家标准，定义了视频监控系统的互联互通规范。ZLMediaKit 支持：
- 接收摄像头推送的 RTP 流（PS/TS 封装）
- 将流转换为 RTSP/RTMP/HLS 等协议
- 将流以 RTP 方式回传给 GB28181 平台

### 8.2 PS 流解封装

GB28181 摄像头通常使用 PS（Program Stream）封装：
```
RTP 包
    └── PS 包
            ├── PS Header
            ├── System Header
            ├── PSM (Program Stream Map)
            └── PES 包
                    ├── PES Header
                    └── ES 数据 (H264/H265/AAC/G711)
```

`PSDecoder` 负责解析 PS 流，提取 ES 数据，创建对应的 Track 和 Frame。

### 8.3 RTP 发送（回传）

ZLMediaKit 可以将内部流以 RTP 方式发送给 GB28181 平台：

```bash
# API 调用
POST /index/api/startSendRtp
{
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "camera01",
  "ssrc": "1",
  "dst_url": "192.168.1.100",
  "dst_port": 10000,
  "is_udp": 1,
  "pt": 96,
  "data_type": 1  # 1=PS, 0=ES, 2=TS
}
```
