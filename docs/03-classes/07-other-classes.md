# 其他核心类详解

## 1. Stamp — 时间戳修复器

**文件：** `src/Common/Stamp.h/cpp`

### 1.1 功能

处理推流端时间戳的各种异常情况：
- 时间戳跳跃（如从 1000ms 突然跳到 100000ms）
- 时间戳回退（如从 5000ms 回退到 1000ms）
- 时间戳不连续（如推流重连后时间戳重置）

### 1.2 三种时间戳模式

| 模式 | 值 | 说明 |
|------|-----|------|
| `kModifyStampOff` | 0 | 使用原始时间戳，不做任何修改 |
| `kModifyStampSystem` | 1 | 使用系统时间（ZLMediaKit 接收数据时的时间），有平滑处理 |
| `kModifyStampRelative` | 2 | 使用相对时间戳（增量），修正跳跃和回退（**默认**） |

### 1.3 核心方法

```cpp
class Stamp {
    // 修正时间戳
    // dts_in/pts_in: 输入时间戳
    // dts_out/pts_out: 输出修正后的时间戳
    void revise(int64_t dts_in, int64_t pts_in, int64_t &dts_out, int64_t &pts_out, bool modifyStamp = false);
    
    // 获取相对时间戳（流时长）
    int64_t getRelativeStamp() const;
    
    // 设置最大时间戳跳跃阈值（超过则认为是跳跃）
    void setMaxGap(uint32_t max_gap);
};
```

### 1.4 SmoothTicker — 平滑时间戳

在 `kModifyStampSystem` 模式下，使用 `SmoothTicker` 对系统时间进行平滑处理，避免因系统时钟精度导致的时间戳抖动。

---

## 2. PacketCache — GOP 缓存

**文件：** `src/Common/PacketCache.h`

### 2.1 功能

缓存最近一个或多个 GOP（Group of Pictures）的数据，使新加入的播放器能够立即获取到关键帧，实现秒开效果。

### 2.2 实现原理

```cpp
template <typename T>
class PacketCache {
    // 写入数据包
    void inputPacket(bool is_key, const std::shared_ptr<T> &pkt);
    // 获取缓存的 GOP 数据
    void getCache(const std::function<void(const std::list<std::shared_ptr<T>> &)> &cb) const;
    // 清空缓存
    void clearCache();
};
```

**缓存策略：**
1. 收到关键帧时，开始新的 GOP 缓存
2. 保留最近 N 个 GOP（N 由配置决定，默认 1）
3. 新播放器加入时，从最近的关键帧开始发送

### 2.3 GOP 缓存与 RingBuffer 的关系

```
推流数据 → RingBuffer::write()
                ↓
         PacketCache::inputPacket()
                ↓
         缓存最近 GOP

新播放器加入 → RingBuffer::attach()
                ↓
         PacketCache::getCache() 获取 GOP 缓存
                ↓
         先发送 GOP 缓存数据
                ↓
         再订阅 RingBuffer 实时数据
```

---

## 3. RtpReceiver — RTP 包排序重组

**文件：** `src/Rtsp/RtpReceiver.h/cpp`

### 3.1 功能

处理 RTP 包的乱序和丢包问题：
- 按 sequence number 排序
- 缓存乱序包，等待缺失包
- 超时后丢弃缺失包，继续处理后续包

### 3.2 核心逻辑

```cpp
class RtpReceiver {
    // 输入 RTP 包（可能乱序）
    bool handleOneRtp(int track_idx, TrackType type, uint8_t interleaved, 
                      const RtpPacket::Ptr &rtp);
    // 排序完成后的回调（子类实现）
    virtual void onRtpSorted(RtpPacket::Ptr rtp, int track_idx) = 0;
};
```

**排序算法：**
1. 维护一个按 seq 排序的 map
2. 收到包后插入 map
3. 从 map 头部取出连续的包（seq 连续）
4. 若 map 大小超过阈值（默认 200），强制输出最旧的包

---

## 4. RtcpContext — RTCP 统计

**文件：** `src/Rtcp/RtcpContext.h`

### 4.1 功能

统计 RTP 流的质量指标，用于生成 RTCP 报文：
- 发送端报告（SR）：发送包数、字节数、NTP 时间戳
- 接收端报告（RR）：丢包率、抖动、最大 seq

### 4.2 关键指标

| 指标 | 说明 |
|------|------|
| 丢包率 | `(expected - received) / expected` |
| 抖动 | RTP 包到达时间间隔的方差 |
| 往返时延 | 通过 SR/RR 的时间戳计算 |

---

## 5. RtpSender — RTP 发送器

**文件：** `src/Rtp/RtpSender.h/cpp`

### 5.1 功能

将 ZLMediaKit 内部的 Frame 数据重新打包为 RTP 流，发送给 GB28181 平台。

### 5.2 支持的封装格式

| 格式 | 说明 |
|------|------|
| PS（Program Stream） | GB28181 标准格式，最常用 |
| ES（Elementary Stream） | 裸 H264/H265 流 |
| TS（Transport Stream） | MPEG-TS 格式 |

### 5.3 连接模式

| 模式 | 说明 |
|------|------|
| TCP 主动 | ZLMediaKit 主动连接 GB28181 平台 |
| UDP 主动 | ZLMediaKit 主动发送 UDP 包 |
| TCP 被动 | ZLMediaKit 监听端口，等待平台连接 |
| UDP 被动 | 等待平台发送 NAT 打洞包 |
| 语音对讲 | 通过推流链路回传 RTP |

---

## 6. FFmpegSource — FFmpeg 拉流代理

**文件：** `server/FFmpegSource.h/cpp`

### 6.1 功能

通过启动 FFmpeg 子进程，将任意 FFmpeg 支持的流拉取并推入 ZLMediaKit。

### 6.2 工作流程

```
addFFmpegSource API 调用
    → 创建 FFmpegSource 对象
    → 构造 FFmpeg 命令行
      (ffmpeg -re -i <src_url> -c copy -f flv rtmp://127.0.0.1/app/stream)
    → 启动 FFmpeg 子进程
    → 监控子进程输出
    → 子进程退出时自动重启（可配置）
```

### 6.3 支持的源格式

FFmpeg 支持的所有格式，包括：
- RTSP/RTMP/HTTP-FLV/HLS
- 本地文件（MP4/MKV/AVI 等）
- 摄像头设备
- 屏幕录制

---

## 7. VideoStack — 视频合流

**文件：** `server/VideoStack.h/cpp`

### 7.1 功能

将多路视频流合并为一路（画中画、四分屏等），通过 FFmpeg 实现。

### 7.2 布局支持

- 单路：1x1
- 四分屏：2x2
- 九分屏：3x3
- 自定义布局

---

## 8. PlayerProxy — 拉流代理

**文件：** `src/Player/PlayerProxy.h`

### 8.1 功能

将外部流（RTSP/RTMP/HLS 等）拉取到 ZLMediaKit 内部，作为一路媒体源供播放器消费。

### 8.2 工作流程

```
addStreamProxy API 调用
    → 创建 PlayerProxy
    → 根据 URL 协议创建对应 Player（RtspPlayer/RtmpPlayer/HlsPlayer）
    → Player 拉流成功后，创建 MultiMediaSourceMuxer
    → 将拉取的流转换为各种协议供播放
    → 断流时自动重连（retry_count 次）
```

### 8.3 断流重连策略

1. 首次断流：立即重连
2. 重连失败：等待 `retry_delay` 秒后重试
3. 超过 `retry_count` 次：触发 `kBroadcastPlayerProxyFailed` 事件
4. `retry_count=-1`：无限重连

---

## 9. MediaSink — 媒体数据消费者

**文件：** `src/Common/MediaSink.h/cpp`

### 9.1 功能

`MediaSink` 是所有媒体数据消费者的基类，定义了接收 Track 和 Frame 的接口。

### 9.2 Track 就绪等待机制

```cpp
class MediaSink : public FrameWriterInterface {
    // 添加 Track
    bool addTrack(const Track::Ptr &track);
    // 输入帧数据
    bool inputFrame(const Frame::Ptr &frame) override;
    // 刷新缓存
    void flush() override;
    
protected:
    // Track 就绪回调（子类实现）
    virtual bool onTrackReady(const Track::Ptr &track) = 0;
    // 所有 Track 就绪回调（子类实现）
    virtual void onAllTrackReady() = 0;
    // 帧数据回调（子类实现）
    virtual bool onTrackFrame(const Frame::Ptr &frame) = 0;
};
```

**等待逻辑：**
- 收到 Track 后，缓存帧数据（最多 `kUnreadyFrameCache` 帧）
- 等待 Track `ready()` 返回 true
- 超时（`kWaitTrackReadyMS`）后强制触发 `onAllTrackReady()`
- 触发后，将缓存的帧数据重放给 `onTrackFrame()`
