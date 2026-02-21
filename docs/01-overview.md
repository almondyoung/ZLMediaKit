# 整体模块说明

## 1. 系统概述

ZLMediaKit 是一个基于 C++11 的高性能流媒体服务器框架，支持 RTSP、RTMP、HLS、HTTP-FLV、WebSocket-FLV、HTTP-TS、FMP4、WebRTC、SRT、GB28181 等主流流媒体协议。其核心设计目标是：

- **高性能**：基于异步 IO（ZLToolKit 事件驱动框架），单机支持数千路并发
- **低延迟**：支持 GOP 缓存、按需转协议、平滑发送等机制
- **易扩展**：模块化设计，支持 Python 插件、WebHook 回调、REST API
- **多协议**：一路推流，自动转换为多种协议供不同客户端消费

---

## 2. 主要模块列表

| 模块 | 目录 | 职责 |
|------|------|------|
| 公共基础层 | `src/Common/` | MediaSource、MediaSink、配置管理、时间戳处理 |
| 编解码扩展层 | `ext-codec/` | H264/H265/AAC/Opus/VP8/VP9/AV1 等编解码封装 |
| 帧与轨道层 | `src/Extension/` | Frame、Track、Factory、CodecInfo 抽象 |
| RTSP 协议层 | `src/Rtsp/` | RTSP 服务器/客户端、RTP 收发、RTCP、组播 |
| RTMP 协议层 | `src/Rtmp/` | RTMP 服务器/客户端、AMF 编解码、FLV 封装 |
| HTTP 协议层 | `src/Http/` | HTTP/WebSocket 服务器、HLS 播放、FLV 播放 |
| RTP 代理层 | `src/Rtp/` | GB28181 RTP 接收、PS/TS 解封装、RTP 发送 |
| 录制模块 | `src/Record/` | HLS 切片、MP4 录制/点播、MPEG-TS 录制 |
| FMP4 模块 | `src/FMP4/` | Fragmented MP4 封装（HTTP-FMP4/WS-FMP4） |
| TS 模块 | `src/TS/` | MPEG-TS 封装（HTTP-TS/WS-TS） |
| RTCP 模块 | `src/Rtcp/` | RTCP 报文解析与统计 |
| Codec 模块 | `src/Codec/` | 编解码器基础接口 |
| Shell 模块 | `src/Shell/` | Telnet 风格的 Shell 管理接口 |
| Onvif 模块 | `src/Onvif/` | Onvif 设备发现与控制 |
| Player 模块 | `src/Player/` | 拉流代理（PlayerProxy） |
| Pusher 模块 | `src/Pusher/` | 推流代理 |
| WebRTC 模块 | `webrtc/` | WebRTC 信令、ICE、DTLS、SRTP |
| SRT 模块 | `srt/` | SRT 协议支持 |
| 服务器入口 | `server/` | main、WebAPI、WebHook、FFmpegSource |
| C API 层 | `api/` | 对外暴露的 C 语言 SDK 接口 |

---

## 3. 模块职责详述

### 3.1 公共基础层（`src/Common/`）

**核心文件：**
- `MediaSource.h/cpp`：所有媒体流的抽象基类，管理流的注册/注销、查找、观看人数统计
- `MediaSink.h/cpp`：媒体数据消费者接口，负责接收 Track 和 Frame
- `MultiMediaSourceMuxer.h/cpp`：核心转协议引擎，将一路输入流同时转换为 RTSP/RTMP/HLS/FMP4/TS/MP4 等多种协议
- `config.h/cpp`：全局配置管理，基于 INI 文件，支持热重载
- `Stamp.h/cpp`：时间戳修复与平滑处理
- `PacketCache.h`：GOP 缓存模板类

**依赖关系：** 被所有协议层依赖，是整个系统的核心枢纽。

### 3.2 帧与轨道层（`src/Extension/`）

**核心文件：**
- `Frame.h/cpp`：帧数据抽象（DTS/PTS/关键帧/配置帧），支持零拷贝切割
- `Track.h/cpp`：音视频轨道描述（编码类型、采样率、分辨率等）
- `Factory.h/cpp`：根据编码类型创建对应 Track/RTP 打包器的工厂类
- `CodecInfo`：编解码信息接口（CodecId、TrackType）

**依赖关系：** 被 ext-codec、Rtsp、Rtmp、Record 等所有上层模块依赖。

### 3.3 编解码扩展层（`ext-codec/`）

为每种编解码格式提供：
- 具体 Track 实现（如 `H264Track`、`AACTrack`）
- RTP 打包/解包器（如 `H264RtpEncoder`、`H264RtpDecoder`）
- RTMP 打包/解包器（如 `H264RtmpEncoder`、`H264RtmpDecoder`）

支持的编解码格式：H264、H265、AAC、G711A/U、Opus、L16、VP8、VP9、AV1、JPEG、MP3

### 3.4 RTSP 协议层（`src/Rtsp/`）

- `RtspSession`：RTSP 服务器会话，处理 OPTIONS/DESCRIBE/SETUP/PLAY/ANNOUNCE/RECORD/TEARDOWN 等方法
- `RtspPlayer`：RTSP 拉流客户端
- `RtspPusher`：RTSP 推流客户端
- `RtspMediaSource`：RTSP 媒体源（RTP 环形缓冲区）
- `RtspMuxer`：将 Track 打包为 RTP 流
- `RtpReceiver`：RTP 包排序与重组
- `RtpMultiCaster`：RTP 组播支持
- `UDPServer`：RTP over UDP 服务

### 3.5 RTMP 协议层（`src/Rtmp/`）

- `RtmpSession`：RTMP 服务器会话，处理 connect/publish/play/seek/pause 等命令
- `RtmpPlayer`：RTMP 拉流客户端
- `RtmpPusher`：RTMP 推流客户端
- `RtmpProtocol`：RTMP chunk 分块协议解析
- `RtmpMediaSource`：RTMP 媒体源（FLV Tag 环形缓冲区）
- `FlvMuxer`：FLV 封装器（用于 HTTP-FLV 输出）
- `amf.h/cpp`：AMF0/AMF3 编解码

### 3.6 HTTP 协议层（`src/Http/`）

- `HttpSession`：HTTP/1.1 服务器会话，支持文件服务、API 路由、FLV/TS/FMP4 直播
- `WebSocketSession`：WebSocket 升级与帧处理
- `HttpClient`：HTTP 客户端（用于 WebHook 回调）
- `HlsPlayer`：HLS 播放客户端
- `HttpFileManager`：HTTP 静态文件服务

### 3.7 RTP 代理层（`src/Rtp/`）

- `RtpServer`：GB28181 RTP 服务器（TCP/UDP）
- `RtpProcess`：RTP 流处理，支持 PS/TS 解封装
- `PSDecoder`：PS（Program Stream）解封装
- `TSDecoder`：TS（Transport Stream）解封装
- `RtpSender`：将媒体流重新打包为 RTP 发送（用于 GB28181 回传）
- `GB28181Process`：GB28181 专用处理逻辑

### 3.8 录制模块（`src/Record/`）

- `HlsMaker`：HLS 切片生成核心逻辑
- `HlsMakerImp`：HLS 切片文件写入实现
- `HlsMediaSource`：HLS 媒体源（供 HTTP 服务器读取 m3u8/ts）
- `MP4Recorder`：MP4 录制（基于 media-server 库）
- `MP4Reader`：MP4 文件点播读取
- `MP4Demuxer`：MP4 解封装
- `Recorder`：录制管理接口（统一 HLS/MP4 录制开关）

### 3.9 服务器入口（`server/`）

- `main.cpp`：程序入口，启动各协议服务器（RTSP/RTMP/HTTP/Shell/RTP/WebRTC/SRT）
- `WebApi.cpp`：REST API 注册与实现（约 100+ 个 API 接口）
- `WebHook.cpp`：WebHook 事件监听与 HTTP 回调触发
- `FFmpegSource.cpp`：通过 FFmpeg 进程拉流并推入 ZLMediaKit
- `VideoStack.cpp`：视频合流/画面叠加功能

---

## 4. 模块依赖关系

```
server/main.cpp
    ├── WebApi / WebHook
    │       └── Common/MediaSource (查询/管理流)
    ├── Rtsp/RtspSession
    │       ├── Common/MultiMediaSourceMuxer (推流时创建)
    │       ├── Rtsp/RtspMediaSource (播放时读取)
    │       └── Extension/Track + Frame
    ├── Rtmp/RtmpSession
    │       ├── Common/MultiMediaSourceMuxer
    │       ├── Rtmp/RtmpMediaSource
    │       └── ext-codec/H264Rtmp, AACRtmp ...
    ├── Http/HttpSession
    │       ├── Rtmp/FlvMuxer (HTTP-FLV)
    │       ├── Record/HlsMediaSource (HLS)
    │       ├── FMP4/FMP4MediaSource (HTTP-FMP4)
    │       └── TS/TSMediaSource (HTTP-TS)
    ├── Rtp/RtpServer (GB28181)
    │       └── Rtp/RtpProcess → Common/MultiMediaSourceMuxer
    ├── webrtc/WebRtcSession
    └── srt/SrtSession

Common/MultiMediaSourceMuxer
    ├── Rtsp/RtspMediaSourceMuxer
    ├── Rtmp/RtmpMediaSourceMuxer
    ├── Record/HlsRecorder
    ├── Record/MP4Recorder
    ├── FMP4/FMP4MediaSourceMuxer
    └── TS/TSMediaSourceMuxer
```

---

## 5. 关键设计模式

| 模式 | 应用场景 |
|------|----------|
| 观察者模式 | `NoticeCenter` 广播事件（推流、播放、录制完成等） |
| 工厂模式 | `Factory` 根据 CodecId 创建 Track/RTP 编解码器 |
| 代理模式 | `MediaSourceEventInterceptor` 拦截并转发事件 |
| 环形缓冲区 | `RingBuffer<T>` 用于 RTP/FLV 包的生产者-消费者模型 |
| 模板方法 | `MediaSink::onTrackReady/onTrackFrame` 定义处理骨架 |
| 策略模式 | `ProtocolOption` 控制各协议的转换策略 |
| RAII | `shared_ptr` + `getOwnership()` 管理流的独占所有权 |
