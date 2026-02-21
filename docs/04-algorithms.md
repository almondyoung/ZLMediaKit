# 算法说明

## 1. GOP 缓存管理算法

### 1.1 原理

GOP（Group of Pictures）是视频编码中从一个关键帧（IDR）到下一个关键帧之间的帧序列。GOP 缓存的目的是让新加入的播放器能够立即获取到最近的关键帧，实现"秒开"效果。

### 1.2 实现位置

`src/Common/PacketCache.h` — `PacketCache<T>` 模板类

### 1.3 算法流程

```
输入帧
    ↓
是关键帧？
    ├── 是：开始新 GOP，将旧 GOP 移入历史缓存
    └── 否：追加到当前 GOP

历史缓存超过 N 个 GOP？
    └── 是：删除最旧的 GOP

新播放器加入
    ↓
从历史缓存中取最近的 GOP
    ↓
先发送 GOP 缓存数据（从关键帧开始）
    ↓
再订阅实时数据流
```

### 1.4 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| GOP 缓存个数 | 1 | 缓存最近 1 个 GOP |
| 最大缓存帧数 | 由 GOP 大小决定 | 通常 25-150 帧 |

### 1.5 优化考虑

- **内存控制**：只缓存最近 N 个 GOP，防止内存无限增长
- **零拷贝**：缓存的是 `shared_ptr<Frame>`，不复制数据
- **线程安全**：通过 `RingBuffer` 的锁机制保证

---

## 2. 时间戳修复算法

### 2.1 原理

推流端的时间戳可能存在以下问题：
- **跳跃**：时间戳突然增大（如推流重连后时间戳重置为 0，但服务器认为是跳跃）
- **回退**：时间戳减小（如 B 帧导致 PTS < DTS）
- **不连续**：时间戳增量不均匀

### 2.2 实现位置

`src/Common/Stamp.h/cpp` — `Stamp` 类

### 2.3 相对时间戳算法（模式 2，默认）

```
输入: dts_in（当前帧解码时间戳）
输出: dts_out（修正后的时间戳）

初始化:
    _last_dts = 0（上一帧时间戳）
    _relative_stamp = 0（相对时间戳累计值）

每帧处理:
    delta = dts_in - _last_dts（时间戳增量）
    
    if delta < 0:
        // 时间戳回退，使用最小增量（1ms）
        delta = 1
    elif delta > MAX_GAP（默认 10 秒）:
        // 时间戳跳跃，使用最小增量
        delta = 1
    
    _relative_stamp += delta
    dts_out = _relative_stamp
    _last_dts = dts_in
```

### 2.4 系统时间戳算法（模式 1）

使用 ZLMediaKit 接收数据时的系统时间作为时间戳，通过 `SmoothTicker` 平滑处理：

```
dts_out = 系统时间 - 流开始时间
```

**平滑处理：** 避免因系统时钟精度（毫秒级）导致的时间戳抖动，通过线性插值平滑输出。

---

## 3. RTP 包排序算法

### 3.1 原理

UDP 传输的 RTP 包可能乱序到达，需要按 sequence number 重新排序。

### 3.2 实现位置

`src/Rtsp/RtpReceiver.h/cpp` — `RtpReceiver` 类

### 3.3 算法

```
维护一个 map<uint16_t, RtpPacket::Ptr>（按 seq 排序）

收到 RTP 包:
    插入 map

尝试输出:
    while map 不为空:
        取 map 中最小 seq 的包
        if seq == 期望的下一个 seq:
            输出该包
            期望 seq++
            从 map 删除
        else:
            break（等待缺失的包）

超时处理:
    if map.size() > MAX_CACHE（默认 200）:
        强制输出最旧的包（丢弃缺失包）
```

### 3.4 Seq 回绕处理

RTP seq 是 16 位无符号整数（0-65535），需要处理回绕：
```cpp
// 判断 seq_a 是否在 seq_b 之后
bool isSeqAfter(uint16_t seq_a, uint16_t seq_b) {
    return (int16_t)(seq_a - seq_b) > 0;
}
```

---

## 4. 媒体流调度算法（RingBuffer）

### 4.1 原理

`RingBuffer<T>` 是 ZLMediaKit 的核心数据结构，实现了高效的生产者-消费者模型。

### 4.2 实现位置

`ZLToolKit/src/Util/RingBuffer.h`（第三方库）

### 4.3 设计特点

- **无锁读取**：消费者读取时不需要加锁（基于 `shared_ptr` 的原子操作）
- **多消费者**：支持任意数量的 `RingReader`（播放器）
- **GOP 缓存集成**：新消费者加入时自动从 GOP 缓存开始
- **背压控制**：消费者太慢时，可以选择丢帧或等待

### 4.4 数据流

```
生产者（推流 Session）
    ↓ write(pkt)
RingBuffer
    ├── 更新 GOP 缓存
    └── 通知所有 RingReader

消费者（播放 Session）
    ↑ 订阅 RingBuffer
    ↑ 收到新数据回调
    ↑ 发送给播放器
```

---

## 5. 音视频同步算法

### 5.1 原理

在转协议时，需要保证音视频的时间戳同步，避免音画不同步。

### 5.2 实现位置

`src/Common/Stamp.h` — `DtsComparator` 类

### 5.3 算法

ZLMediaKit 使用 DTS（解码时间戳）作为同步基准：

```
视频帧: DTS 单调递增
音频帧: DTS 单调递增

同步策略:
    以视频 DTS 为基准
    音频 DTS 与视频 DTS 对齐
    若音频超前视频超过阈值，等待视频追上
    若视频超前音频超过阈值，等待音频追上
```

### 5.4 PTS 与 DTS 的处理

对于 H264/H265 的 B 帧，PTS（显示时间戳）可能小于 DTS（解码时间戳）：
- `FrameStamp` 类负责正确传递 PTS 和 DTS
- RTSP 的 RTP 时间戳使用 DTS
- HLS/MP4 的时间戳使用 DTS，但 ctts box 记录 PTS-DTS 的差值

---

## 6. HLS 切片算法

### 6.1 原理

HLS 将直播流切割为固定时长的 TS 文件，通过 m3u8 播放列表管理。

### 6.2 实现位置

`src/Record/HlsMaker.h/cpp`

### 6.3 切片策略

```
收到视频关键帧
    ↓
当前切片时长 >= kSegmentDuration（默认 2 秒）？
    ├── 是：关闭当前 TS 文件，开始新切片
    │       更新 m3u8 播放列表
    │       删除超出 kSegmentNum 的旧切片
    └── 否：继续写入当前 TS 文件
```

**关键点：** 切片必须从关键帧开始，确保播放器能够正确解码。

### 6.4 m3u8 格式

```m3u8
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-ALLOW-CACHE:NO
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:100

#EXTINF:2.000,
http://host/app/stream/100.ts
#EXTINF:2.000,
http://host/app/stream/101.ts
#EXTINF:2.000,
http://host/app/stream/102.ts
```

---

## 7. 拥塞控制算法

### 7.1 TCP 发送缓冲区控制

ZLMediaKit 通过以下机制控制 TCP 发送速率：

**合并写（Merge Write）：**
- 配置 `kMergeWriteMS`（默认 0，关闭）
- 开启后，将多个小包合并为一个大包发送
- 减少系统调用次数，提高吞吐量
- 代价：增加延迟

**TCP_NODELAY：**
- 默认开启，禁用 Nagle 算法
- 减少延迟，但可能增加网络包数量

### 7.2 UDP 发送速率控制

对于 RTP over UDP，ZLMediaKit 不做主动拥塞控制，依赖：
- RTCP RR（接收端报告）中的丢包率反馈
- 应用层的重传机制（可选）

### 7.3 平滑发送（Paced Sender）

配置 `kPacedSenderMS`（默认 0，关闭）：
- 开启后，按固定时间间隔发送数据
- 避免突发大量数据导致网络拥塞
- 代价：增加 CPU 和内存开销

---

## 8. 按需转协议优化算法

### 8.1 原理

当某种协议没有播放器时，不需要进行该协议的转换，节省 CPU 和内存。

### 8.2 实现

```
推流到来 → 创建 MultiMediaSourceMuxer
    ↓
检查各协议的 demand 配置
    ├── demand=0（立即转换）：立即创建对应 Muxer
    └── demand=1（按需转换）：暂不创建 Muxer

播放器请求某协议
    ↓
对应 Muxer 不存在？
    ├── 是：创建 Muxer，等待下一个关键帧后开始输出
    └── 否：直接从 GOP 缓存开始输出

所有播放器断开
    ↓
等待 kStreamNoneReaderDelayMS 后
    ↓
触发 kBroadcastStreamNoneReader 事件
    ↓
WebHook on_stream_none_reader 决定是否关闭流
```

### 8.3 第一个播放者体验

按需转协议时，第一个播放者需要等待下一个关键帧才能开始播放（可能有 1-2 秒延迟）。若需要最佳体验，应关闭按需转协议（`demand=0`）。
