# 架构图与设计图

所有图表均使用 Mermaid 语法。

---

## 1. 系统整体分层架构图

```mermaid
graph TB
    subgraph 客户端层
        P1[推流端<br/>OBS/FFmpeg/摄像头]
        P2[播放端<br/>VLC/浏览器/App]
    end

    subgraph 协议接入层
        S1[RTSP Server<br/>:554]
        S2[RTMP Server<br/>:1935]
        S3[HTTP/WS Server<br/>:80/:443]
        S4[RTP/GB28181<br/>:10000]
        S5[WebRTC<br/>UDP]
        S6[SRT Server<br/>:9000]
    end

    subgraph 核心处理层
        M1[MultiMediaSourceMuxer<br/>转协议引擎]
        M2[MediaSource<br/>流注册中心]
        M3[Track/Frame<br/>帧数据流水线]
        M4[Stamp<br/>时间戳修复]
        M5[PacketCache/RingBuffer<br/>GOP缓存]
    end

    subgraph 协议输出层
        O1[RtspMediaSource<br/>RTP环形缓冲]
        O2[RtmpMediaSource<br/>FLV Tag缓冲]
        O3[HlsMediaSource<br/>m3u8/ts切片]
        O4[FMP4MediaSource<br/>fmp4分片]
        O5[TSMediaSource<br/>TS流]
    end

    subgraph 录制存储层
        R1[HLS录制<br/>ts切片文件]
        R2[MP4录制<br/>mp4文件]
    end

    subgraph 管理层
        A1[WebAPI<br/>REST接口]
        A2[WebHook<br/>事件回调]
        A3[配置管理<br/>config.ini]
    end

    P1 -->|推流| S1
    P1 -->|推流| S2
    P1 -->|推流| S4
    P1 -->|推流| S5
    P1 -->|推流| S6

    S1 & S2 & S4 & S5 & S6 --> M3
    M3 --> M1
    M1 --> M2
    M1 --> O1 & O2 & O3 & O4 & O5
    M1 --> R1 & R2
    M4 --> M3
    M5 --> O1 & O2

    O1 -->|RTSP播放| P2
    O2 -->|RTMP/HTTP-FLV播放| P2
    O3 -->|HLS播放| P2
    O4 -->|HTTP-FMP4播放| P2
    O5 -->|HTTP-TS播放| P2
    S3 --> O2 & O3 & O4 & O5

    A1 & A2 --> M2
    A3 --> M1
```

---

## 2. 核心组件依赖图

```mermaid
graph LR
    subgraph 输入
        RtspSession
        RtmpSession
        RtpProcess
        WebRtcTransport
        SrtSession
    end

    subgraph 核心
        MultiMediaSourceMuxer
        MediaSource
        MediaSink
        Track
        Frame
        RingBuffer
    end

    subgraph 输出
        RtspMediaSourceMuxer
        RtmpMediaSourceMuxer
        HlsRecorder
        MP4Recorder
        FMP4MediaSourceMuxer
        TSMediaSourceMuxer
    end

    RtspSession -->|inputFrame| MultiMediaSourceMuxer
    RtmpSession -->|inputFrame| MultiMediaSourceMuxer
    RtpProcess -->|inputFrame| MultiMediaSourceMuxer
    WebRtcTransport -->|inputFrame| MultiMediaSourceMuxer
    SrtSession -->|inputFrame| MultiMediaSourceMuxer

    MultiMediaSourceMuxer --> RtspMediaSourceMuxer
    MultiMediaSourceMuxer --> RtmpMediaSourceMuxer
    MultiMediaSourceMuxer --> HlsRecorder
    MultiMediaSourceMuxer --> MP4Recorder
    MultiMediaSourceMuxer --> FMP4MediaSourceMuxer
    MultiMediaSourceMuxer --> TSMediaSourceMuxer

    MultiMediaSourceMuxer --> MediaSink
    MediaSink --> Track
    Track --> Frame
    RtspMediaSourceMuxer --> RingBuffer
    RtmpMediaSourceMuxer --> RingBuffer
    MediaSource --> RingBuffer
```

---

## 3. RtspServer 组合结构图

```mermaid
graph TB
    subgraph TcpServer
        RtspSession
    end

    subgraph RtspSession内部
        RtspSplitter[RtspSplitter<br/>RTSP报文分割]
        RtpReceiver[RtpReceiver<br/>RTP排序重组]
        MediaSourceEvent[MediaSourceEvent<br/>事件接口]
        SdpTrack[SdpTrack<br/>SDP轨道描述]
        RtcpContext[RtcpContext<br/>RTCP统计]
    end

    subgraph 推流路径
        RtspMediaSourceImp[RtspMediaSourceImp<br/>推流媒体源]
        MultiMediaSourceMuxer[MultiMediaSourceMuxer<br/>转协议]
    end

    subgraph 播放路径
        RtspMediaSource[RtspMediaSource<br/>RTP环形缓冲]
        RingReader[RingReader<br/>消费者]
    end

    RtspSession --> RtspSplitter
    RtspSession --> RtpReceiver
    RtspSession --> MediaSourceEvent
    RtspSession --> SdpTrack
    RtspSession --> RtcpContext

    RtspSession -->|推流时创建| RtspMediaSourceImp
    RtspMediaSourceImp --> MultiMediaSourceMuxer

    RtspSession -->|播放时查找| RtspMediaSource
    RtspMediaSource --> RingReader
    RingReader -->|sendRtpPacket| RtspSession
```

---

## 4. 核心类 UML 类图

```mermaid
classDiagram
    class CodecInfo {
        +getCodecId() CodecId
        +getCodecName() string
        +getTrackType() TrackType
        +getIndex() int
        -_index int
    }

    class Frame {
        <<abstract>>
        +dts() uint64_t
        +pts() uint64_t
        +prefixSize() size_t
        +keyFrame() bool
        +configFrame() bool
        +cacheAble() bool
        +dropAble() bool
        +decodeAble() bool
    }

    class FrameImp {
        +_codec_id CodecId
        +_dts uint64_t
        +_pts uint64_t
        +_prefix_size size_t
        +_buffer BufferLikeString
    }

    class FrameDispatcher {
        +addDelegate(delegate) FrameWriterInterface*
        +delDelegate(ptr)
        +inputFrame(frame) bool
        +size() size_t
        +getVideoKeyFrames() uint64_t
        +getVideoGopSize() size_t
        -_delegates map
        -_frames uint64_t
        -_video_key_frames uint64_t
    }

    class Track {
        <<abstract>>
        +ready() bool
        +clone() Track::Ptr
        +getSdp(pt) Sdp::Ptr
        +getExtraData() Buffer::Ptr
        +getBitRate() int
        -_bit_rate int
    }

    class VideoTrack {
        +getVideoHeight() int
        +getVideoWidth() int
        +getVideoFps() float
        +getConfigFrames() vector~Frame::Ptr~
    }

    class AudioTrack {
        +getAudioSampleRate() int
        +getAudioSampleBit() int
        +getAudioChannel() int
    }

    class TrackSource {
        <<abstract>>
        +getTracks(ready) vector~Track::Ptr~
        +getTrack(type, ready) Track::Ptr
    }

    class MediaSource {
        +getSchema() string
        +getMediaTuple() MediaTuple
        +getTracks(ready) vector~Track::Ptr~
        +readerCount() int
        +totalReaderCount() int
        +seekTo(stamp) bool
        +close(force) bool
        +setupRecord(type, start, path, sec) bool
        +startSendRtp(args, cb)
        +find(schema, vhost, app, id) Ptr
        +findAsync(info, session, cb)
        +for_each_media(cb, ...)
        #regist()
        -unregist() bool
        -_schema string
        -_tuple MediaTuple
        -_listener weak_ptr~MediaSourceEvent~
        -_create_stamp time_t
        -_speed BytesSpeed[]
    }

    class MediaSourceEvent {
        +getOriginType(sender) MediaOriginType
        +getOriginUrl(sender) string
        +seekTo(sender, stamp) bool
        +close(sender) bool
        +totalReaderCount(sender) int
        +onReaderChanged(sender, size)
        +onRegist(sender, regist)
        +getLossRate(sender, type) float
        +getOwnerPoller(sender) EventPoller::Ptr
    }

    class MultiMediaSourceMuxer {
        +setMediaListener(listener)
        +setTrackListener(listener)
        +totalReaderCount() int
        +isEnabled() bool
        +setupRecord(type, start, path, sec) bool
        +startSendRtp(args, cb)
        +stopSendRtp(ssrc) bool
        #onTrackReady(track) bool
        #onAllTrackReady()
        #onTrackFrame(frame) bool
        -_rtsp RtspMediaSourceMuxer::Ptr
        -_rtmp RtmpMediaSourceMuxer::Ptr
        -_hls HlsRecorder::Ptr
        -_mp4 MediaSinkInterface::Ptr
        -_fmp4 FMP4MediaSourceMuxer::Ptr
        -_ts TSMediaSourceMuxer::Ptr
        -_ring RingType::Ptr
        -_option ProtocolOption
    }

    class RtspSession {
        +onRecv(buf)
        +onError(err)
        +onManager()
        -handleReq_Options(parser)
        -handleReq_Describe(parser)
        -handleReq_ANNOUNCE(parser)
        -handleReq_RECORD(parser)
        -handleReq_Setup(parser)
        -handleReq_Play(parser)
        -handleReq_Teardown(parser)
        -sendRtpPacket(pkt)
        -_push_src RtspMediaSourceImp::Ptr
        -_play_src weak_ptr~RtspMediaSource~
        -_play_reader RingReader::Ptr
        -_sdp_track vector~SdpTrack::Ptr~
        -_rtp_type eRtpType
    }

    class RtmpSession {
        +onRecv(buf)
        +onError(err)
        +onManager()
        -onCmd_connect(dec)
        -onCmd_publish(dec)
        -onCmd_play(dec)
        -onCmd_seek(dec)
        -onSendMedia(pkt)
        -_push_src RtmpMediaSourceImp::Ptr
        -_play_src weak_ptr~RtmpMediaSource~
        -_ring_reader RingReader::Ptr
    }

    CodecInfo <|-- Frame
    CodecInfo <|-- Track
    Frame <|-- FrameImp
    FrameDispatcher <|-- Track
    Track <|-- VideoTrack
    Track <|-- AudioTrack
    TrackSource <|-- MediaSource
    MediaSourceEvent <|-- MediaSourceEventInterceptor
    MediaSourceEventInterceptor <|-- MultiMediaSourceMuxer
    MediaSource --> MediaSourceEvent : listener
    MultiMediaSourceMuxer --> Track : manages
    RtspSession --> MultiMediaSourceMuxer : creates(push)
    RtspSession --> MediaSource : reads(play)
    RtmpSession --> MultiMediaSourceMuxer : creates(push)
    RtmpSession --> MediaSource : reads(play)
```

---

## 5. 推流流程序列图（RTMP 推流）

```mermaid
sequenceDiagram
    participant Client as 推流客户端(OBS)
    participant RtmpSession
    participant NoticeCenter
    participant WebHook
    participant MultiMediaSourceMuxer
    participant RtmpMediaSource
    participant RtspMediaSource
    participant HlsRecorder

    Client->>RtmpSession: TCP连接
    RtmpSession->>RtmpSession: RTMP握手(C0C1C2/S0S1S2)
    Client->>RtmpSession: connect命令
    RtmpSession->>Client: _result(连接成功)
    Client->>RtmpSession: createStream命令
    RtmpSession->>Client: _result(streamId)
    Client->>RtmpSession: publish命令
    RtmpSession->>NoticeCenter: kBroadcastMediaPublish事件
    NoticeCenter->>WebHook: on_publish HTTP回调
    WebHook-->>NoticeCenter: 鉴权结果(允许/拒绝)
    NoticeCenter-->>RtmpSession: invoker(err, ProtocolOption)
    RtmpSession->>MultiMediaSourceMuxer: 创建Muxer
    MultiMediaSourceMuxer->>RtmpMediaSource: 创建RTMP媒体源
    MultiMediaSourceMuxer->>RtspMediaSource: 创建RTSP媒体源
    MultiMediaSourceMuxer->>HlsRecorder: 创建HLS录制器
    RtmpSession->>NoticeCenter: kBroadcastMediaChanged(注册)
    NoticeCenter->>WebHook: on_stream_changed HTTP回调

    loop 推流数据
        Client->>RtmpSession: RTMP Chunk(音视频数据)
        RtmpSession->>RtmpSession: onRtmpChunk解析
        RtmpSession->>MultiMediaSourceMuxer: inputFrame(Frame)
        MultiMediaSourceMuxer->>RtmpMediaSource: 写入FLV Tag
        MultiMediaSourceMuxer->>RtspMediaSource: 写入RTP包
        MultiMediaSourceMuxer->>HlsRecorder: 写入TS切片
    end

    Client->>RtmpSession: 断开连接
    RtmpSession->>NoticeCenter: kBroadcastMediaChanged(注销)
    NoticeCenter->>WebHook: on_stream_changed HTTP回调
```

---

## 6. 拉流播放序列图（RTSP 播放）

```mermaid
sequenceDiagram
    participant Player as 播放器(VLC)
    participant RtspSession
    participant NoticeCenter
    participant WebHook
    participant MediaSource
    participant RingBuffer

    Player->>RtspSession: TCP连接
    Player->>RtspSession: OPTIONS
    RtspSession->>Player: 200 OK (支持的方法列表)
    Player->>RtspSession: DESCRIBE rtsp://host/app/stream
    RtspSession->>MediaSource: findAsync(查找流)
    MediaSource-->>RtspSession: 找到流(或等待超时)
    RtspSession->>NoticeCenter: kBroadcastMediaPlayed事件
    NoticeCenter->>WebHook: on_play HTTP回调
    WebHook-->>NoticeCenter: 鉴权结果
    RtspSession->>Player: 200 OK + SDP
    Player->>RtspSession: SETUP (协商RTP传输方式)
    RtspSession->>Player: 200 OK (Session ID)
    Player->>RtspSession: PLAY
    RtspSession->>RingBuffer: 创建RingReader(从GOP缓存开始)
    RtspSession->>Player: 200 OK

    loop 播放数据
        RingBuffer->>RtspSession: 新RTP包到达回调
        RtspSession->>Player: 发送RTP包
        Player->>RtspSession: RTCP RR(接收报告)
        RtspSession->>Player: RTCP SR(发送报告)
    end

    Player->>RtspSession: TEARDOWN
    RtspSession->>NoticeCenter: kBroadcastFlowReport(流量统计)
    NoticeCenter->>WebHook: on_flow_report HTTP回调
```

---

## 7. WebHook 触发流程序列图

```mermaid
sequenceDiagram
    participant Event as 内部事件
    participant NoticeCenter
    participant WebHook
    participant HttpRequester
    participant UserServer as 用户业务服务器

    Event->>NoticeCenter: 广播事件(如kBroadcastMediaPublish)
    NoticeCenter->>WebHook: 回调函数触发
    WebHook->>WebHook: 构造JSON请求体
    WebHook->>HttpRequester: 异步POST请求
    HttpRequester->>UserServer: HTTP POST /on_publish
    UserServer-->>HttpRequester: {"code":0,"msg":"success"}
    HttpRequester-->>WebHook: 解析响应
    WebHook->>WebHook: 调用invoker(err, option)
    Note over WebHook: 若HTTP失败，按retry配置重试
    Note over WebHook: 若code!=0，鉴权失败，断开连接
```

---

## 8. MediaSource 与 Track 数据结构关系图

```mermaid
graph TB
    subgraph MediaSource
        schema[schema: rtsp/rtmp/hls...]
        tuple[MediaTuple: vhost/app/stream]
        listener[listener: MediaSourceEvent]
        speed[_speed: BytesSpeed x4]
    end

    subgraph TrackSource
        getTracks[getTracks()]
        getTrack[getTrack(type)]
    end

    subgraph Track
        codecId[CodecId: H264/AAC...]
        trackType[TrackType: Video/Audio]
        bitRate[_bit_rate]
        delegates[FrameDispatcher::_delegates]
    end

    subgraph VideoTrack
        width[width]
        height[height]
        fps[fps]
        configFrames[configFrames: SPS/PPS/VPS]
    end

    subgraph AudioTrack
        sampleRate[sampleRate]
        channels[channels]
        sampleBit[sampleBit]
    end

    subgraph Frame
        dts[dts: 解码时间戳]
        pts[pts: 显示时间戳]
        data[data: 裸数据指针]
        size[size: 数据长度]
        prefixSize[prefixSize: 前缀长度]
        keyFrame[keyFrame: 是否关键帧]
        configFrame[configFrame: 是否配置帧]
    end

    MediaSource --> TrackSource
    TrackSource --> Track
    Track --> VideoTrack
    Track --> AudioTrack
    Track -->|dispatch| Frame
    VideoTrack -->|H264Track| Frame
    AudioTrack -->|AACTrack| Frame
```

---

## 9. 转协议引擎内部结构图

```mermaid
graph LR
    subgraph 输入
        InputFrame[Frame输入<br/>onTrackFrame]
    end

    subgraph MultiMediaSourceMuxer
        Stamp[Stamp时间戳修复]
        PacedSender[PacedSender平滑发送]
        GopCache[GOP缓存<br/>PacketCache]
        Ring[RingBuffer<br/>帧环形缓冲]
    end

    subgraph 输出Muxer
        RtspMuxer[RtspMediaSourceMuxer<br/>→ RTP打包]
        RtmpMuxer[RtmpMediaSourceMuxer<br/>→ FLV Tag]
        HlsMuxer[HlsRecorder<br/>→ TS切片]
        Mp4Muxer[MP4Recorder<br/>→ MP4文件]
        Fmp4Muxer[FMP4MediaSourceMuxer<br/>→ fmp4分片]
        TsMuxer[TSMediaSourceMuxer<br/>→ TS流]
    end

    InputFrame --> Stamp
    Stamp --> PacedSender
    PacedSender --> GopCache
    GopCache --> Ring
    Ring --> RtspMuxer
    Ring --> RtmpMuxer
    Ring --> HlsMuxer
    Ring --> Mp4Muxer
    Ring --> Fmp4Muxer
    Ring --> TsMuxer
```
