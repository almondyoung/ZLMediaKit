# Track / Frame 类详解

## 1. Frame 类体系

### 1.1 Frame 抽象基类

`Frame` 继承自 `toolkit::Buffer` 和 `CodecInfo`，是所有媒体帧的抽象接口。

**核心接口：**

| 方法 | 返回类型 | 说明 |
|------|----------|------|
| `dts()` | `uint64_t` | 解码时间戳（毫秒） |
| `pts()` | `uint64_t` | 显示时间戳（毫秒），默认等于 dts |
| `prefixSize()` | `size_t` | 帧前缀长度（H264 为 4 字节 0x00000001） |
| `keyFrame()` | `bool` | 是否为关键帧（IDR） |
| `configFrame()` | `bool` | 是否为配置帧（SPS/PPS/VPS） |
| `cacheAble()` | `bool` | 是否可缓存（指针帧不可缓存） |
| `dropAble()` | `bool` | 是否可丢弃（SEI/AUD 帧） |
| `decodeAble()` | `bool` | 是否可解码（配置帧不可解码） |
| `data()` | `char*` | 数据指针（继承自 Buffer） |
| `size()` | `size_t` | 数据长度（继承自 Buffer） |

### 1.2 Frame 派生类

```
Frame (抽象)
├── FrameImp          — 通用帧实现，内部持有 BufferLikeString
├── FrameFromPtr      — 包装外部指针，不可缓存
│   ├── FrameAutoDelete   — 自动 delete[] 指针
│   └── FrameInternalBase — 子帧（零拷贝切割复合帧）
├── FrameCacheAble    — 将不可缓存帧转为可缓存帧（深拷贝）
├── FrameStamp        — 覆盖帧的时间戳
└── FrameFromBuffer   — 从 Buffer 对象构造帧（持有 Buffer 生命周期）
```

### 1.3 FrameImp — 通用帧

最常用的帧实现，内部使用 `BufferLikeString` 存储数据。

```cpp
class FrameImp : public Frame {
public:
    CodecId _codec_id;      // 编解码类型
    uint64_t _dts;          // 解码时间戳
    uint64_t _pts;          // 显示时间戳
    size_t _prefix_size;    // 前缀长度
    BufferLikeString _buffer; // 数据缓冲
};
```

### 1.4 FrameMerger — 帧合并器

用于将多个时间戳相同的帧合并为一个输出帧（如 H264 的多 NALU 合并）。

```cpp
class FrameMerger {
    enum { none, h264_prefix, mp4_nal_size };
    void flush();
    bool inputFrame(const Frame::Ptr &frame, onOutput cb, BufferLikeString *buffer = nullptr);
};
```

**合并模式：**
- `none`：不合并，直接输出
- `h264_prefix`：以 `0x00000001` 分隔合并
- `mp4_nal_size`：以 4 字节长度前缀合并（MP4 格式）

### 1.5 FrameDispatcher — 帧分发器

`Track` 继承自 `FrameDispatcher`，实现帧的一对多分发。

```cpp
class FrameDispatcher : public FrameWriterInterface {
    // 添加消费者
    FrameWriterInterface* addDelegate(FrameWriterInterface::Ptr delegate);
    // 删除消费者
    void delDelegate(FrameWriterInterface *ptr);
    // 写入帧并分发给所有消费者
    bool inputFrame(const Frame::Ptr &frame) override;
    // 统计信息
    uint64_t getVideoKeyFrames() const;  // 关键帧数
    size_t getVideoGopSize() const;      // GOP 大小
    size_t getVideoGopInterval() const;  // GOP 间隔(ms)
    int64_t getDuration() const;         // 流时长
};
```

---

## 2. CodecId 枚举

```cpp
typedef enum {
    CodecH264  = 0,   // H.264/AVC
    CodecH265  = 1,   // H.265/HEVC
    CodecAAC   = 2,   // AAC
    CodecG711A = 3,   // G.711 A-law (PCMA)
    CodecG711U = 4,   // G.711 μ-law (PCMU)
    CodecOpus  = 5,   // Opus
    CodecL16   = 6,   // L16 PCM
    CodecVP8   = 7,   // VP8
    CodecVP9   = 8,   // VP9
    CodecAV1   = 9,   // AV1
    CodecJPEG  = 10,  // JPEG
    CodecH266  = 11,  // H.266/VVC
    CodecTS    = 12,  // MPEG-TS
    CodecPS    = 13,  // MPEG-PS
    CodecMP3   = 14,  // MP3
    // ...
} CodecId;
```

---

## 3. Track 类体系

### 3.1 Track 抽象基类

`Track` 继承自 `FrameDispatcher`（帧分发）和 `CodecInfo`（编解码信息）。

**核心接口：**

| 方法 | 说明 |
|------|------|
| `ready()` | 是否就绪（已获取 SPS/PPS 等配置信息） |
| `clone()` | 克隆 Track（不复制环形缓存和代理关系） |
| `getSdp(pt)` | 生成 SDP 描述 |
| `getExtraData()` | 获取 extra data（用于 RTMP/MP4） |
| `setExtraData(data, size)` | 设置 extra data |
| `getBitRate()` | 获取比特率 |
| `update()` | 更新 Track 信息（触发 SPS/PPS 解析） |

### 3.2 VideoTrack

```cpp
class VideoTrack : public Track {
    virtual int getVideoHeight() const;   // 视频高度
    virtual int getVideoWidth() const;    // 视频宽度
    virtual float getVideoFps() const;    // 帧率
    virtual vector<Frame::Ptr> getConfigFrames() const; // SPS/PPS/VPS
};
```

### 3.3 AudioTrack

```cpp
class AudioTrack : public Track {
    virtual int getAudioSampleRate() const;  // 采样率（Hz）
    virtual int getAudioSampleBit() const;   // 采样位数（8/16）
    virtual int getAudioChannel() const;     // 声道数
};
```

### 3.4 具体 Track 实现（ext-codec/）

| 类名 | 编解码 | 特殊说明 |
|------|--------|----------|
| `H264Track` | H.264 | 解析 SPS 获取宽高/fps，管理 SPS/PPS |
| `H265Track` | H.265 | 解析 VPS/SPS/PPS |
| `AACTrack` | AAC | 解析 AudioSpecificConfig，获取采样率/声道 |
| `G711Track` | G.711 A/U | 固定采样率 8000Hz |
| `OpusTrack` | Opus | 支持 8k/16k/48kHz |
| `VP8Track` | VP8 | WebRTC 常用 |
| `VP9Track` | VP9 | WebRTC 常用 |
| `AV1Track` | AV1 | 新一代视频编码 |

---

## 4. TrackSource 接口

```cpp
class TrackSource {
    // 获取所有 Track（ready=true 只返回已就绪的）
    virtual vector<Track::Ptr> getTracks(bool ready = true) const = 0;
    // 获取特定类型的 Track
    Track::Ptr getTrack(TrackType type, bool ready = true) const;
};
```

`MediaSource` 继承自 `TrackSource`，播放器通过此接口获取流的音视频轨道信息。

---

## 5. 帧数据流水线

```
推流端数据
    ↓
RTP/RTMP 解包器（ext-codec/H264Rtp.cpp 等）
    ↓ inputFrame(Frame)
Track::inputFrame()  ← FrameDispatcher
    ↓ 分发给所有消费者
    ├── MultiMediaSourceMuxer::onTrackFrame()
    │       ↓ 时间戳修复(Stamp)
    │       ↓ 写入 RingBuffer
    │       ↓ 分发给各协议 Muxer
    │           ├── RtspMediaSourceMuxer → RTP 打包 → RtspMediaSource
    │           ├── RtmpMediaSourceMuxer → FLV Tag → RtmpMediaSource
    │           ├── HlsRecorder → TS 切片 → 文件
    │           └── MP4Recorder → MP4 文件
    └── 其他消费者（如 WebRTC、SRT）
```

---

## 6. 零拷贝帧切割

ZLMediaKit 大量使用零拷贝技术处理复合帧（一个 Buffer 包含多个 NALU）：

```cpp
// FrameInternal: 子帧持有父帧的 shared_ptr，不复制数据
template <typename Parent>
class FrameInternal : public FrameInternalBase<Parent> {
    Frame::Ptr _parent_frame;  // 持有父帧生命周期
    // data() 返回父帧数据的偏移指针
};
```

**应用场景：**
- H264 一个 RTP 包包含多个 NALU（STAP-A 模式）
- AAC 一个 ADTS 帧包含多个 AU
- 切割时只创建子帧对象，不复制数据内存
