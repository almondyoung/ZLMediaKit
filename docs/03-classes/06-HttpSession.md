# HttpSession 类详解

## 1. 类概述

`HttpSession` 是 HTTP/WebSocket 服务器的核心会话类，位于 `src/Http/HttpSession.h`，负责：
- HTTP/1.1 请求解析与响应
- 静态文件服务
- REST API 路由（WebAPI）
- HTTP-FLV 直播流
- HTTP-TS 直播流
- HTTP-FMP4 直播流
- WebSocket 升级（WebSocket-FLV/TS/FMP4）
- HLS 播放（m3u8 + ts 文件）

---

## 2. 继承关系

```
toolkit::Session
    └── HttpSession
            └── WebSocketSession<HttpSession>  (WebSocket 支持)
```

---

## 3. HTTP 直播流输出

### 3.1 HTTP-FLV

**URL 格式：** `http://host/app/stream.flv`

**实现流程：**
1. 客户端请求 `.flv` 后缀的 URL
2. `HttpSession` 查找对应的 `RtmpMediaSource`
3. 触发 `kBroadcastMediaPlayed` 鉴权
4. 发送 FLV 文件头（`FLV header`）
5. 创建 `RingReader`，持续发送 FLV Tag

**FLV 文件结构：**
```
FLV Header (9字节)
    ├── Signature: "FLV"
    ├── Version: 1
    ├── Flags: 0x05 (有音视频)
    └── DataOffset: 9

PreviousTagSize0 (4字节, 值为0)

FLV Tag (重复)
    ├── TagType: 8(音频)/9(视频)/18(脚本)
    ├── DataSize: 3字节
    ├── Timestamp: 3字节
    ├── TimestampExtended: 1字节
    ├── StreamID: 3字节 (总为0)
    └── Data: 音视频数据

PreviousTagSize (4字节)
```

### 3.2 HTTP-TS

**URL 格式：** `http://host/app/stream.ts`

发送 MPEG-TS 格式的直播流，适合 VLC 等播放器。

### 3.3 HTTP-FMP4

**URL 格式：** `http://host/app/stream.mp4`

发送 Fragmented MP4 格式，适合 MSE（Media Source Extensions）播放器。

### 3.4 HLS

**URL 格式：** `http://host/app/stream/hls.m3u8`

返回 HLS m3u8 播放列表，客户端按需请求 `.ts` 切片文件。

---

## 4. WebSocket 直播流

WebSocket 升级后，可以传输 FLV/TS/FMP4 格式的直播流：

| URL 格式 | 说明 |
|----------|------|
| `ws://host/app/stream.flv` | WebSocket-FLV |
| `ws://host/app/stream.ts` | WebSocket-TS |
| `ws://host/app/stream.mp4` | WebSocket-FMP4 |

---

## 5. HttpFileManager — 静态文件服务

`HttpFileManager` 处理静态文件请求：
- 支持 Range 请求（断点续传）
- 支持 ETag 缓存验证
- 支持目录浏览（`kDirMenu=1`）
- 触发 `kBroadcastHttpAccess` 事件（文件访问鉴权）
- 支持虚拟目录映射（`kVirtualPath`）

---

## 6. WebSocketSplitter — WebSocket 帧解析

```cpp
class WebSocketSplitter {
    // 输入原始数据，解析 WebSocket 帧
    void decode(uint8_t *data, size_t len);
    // 收到完整 WebSocket 帧的回调
    virtual void onWebSocketDecodeComplete(const WebSocketHeader &header, Buffer::Ptr &buffer);
    // 发送 WebSocket 帧
    void encode(const WebSocketHeader &header, const Buffer::Ptr &buffer);
};
```

**WebSocket 帧格式：**
```
Byte 0: FIN(1) + RSV(3) + Opcode(4)
Byte 1: MASK(1) + Payload Length(7)
[Extended Payload Length: 2 or 8 bytes]
[Masking Key: 4 bytes, if MASK=1]
Payload Data
```

---

## 7. HttpCookieManager — Cookie 管理

用于 HTTP 文件访问鉴权的 Cookie 管理：
- 基于 Cookie 缓存鉴权结果，避免每次请求都触发 WebHook
- Cookie 有效期可配置
- 支持按 URL 参数区分不同的鉴权状态

---

## 8. HlsPlayer — HLS 拉流客户端

`HlsPlayer` 实现了 HLS 协议的客户端：
1. 下载并解析 m3u8 播放列表
2. 按顺序下载 ts 切片
3. 解析 TS 流，提取音视频帧
4. 支持直播（持续刷新 m3u8）和点播

---

## 9. 关键配置项

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `http.port` | 80 | HTTP 监听端口 |
| `http.sslport` | 443 | HTTPS 监听端口 |
| `http.rootPath` | `./www` | HTTP 根目录 |
| `http.keepAliveSecond` | 30 | Keep-Alive 超时（秒） |
| `http.maxReqSize` | 4096 | 最大请求体大小（字节） |
| `http.sendBufSize` | 65536 | 文件发送缓冲大小 |
| `http.dirMenu` | 1 | 是否显示目录列表 |
| `http.allowCrossDomains` | 1 | 是否允许跨域 |
| `http.charSet` | `utf-8` | 字符编码 |
