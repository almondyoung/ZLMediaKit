# MediaSource 类详解

## 1. 类概述

`MediaSource` 是 ZLMediaKit 中所有媒体流的抽象基类，位于 `src/Common/MediaSource.h`。它代表一路正在运行的媒体流（如一路 RTSP 推流、一路 RTMP 推流、一个 HLS 流等），负责：

- 流的注册与注销（全局流注册表）
- 流的查找（同步/异步）
- 观看人数统计
- 录制控制（HLS/MP4）
- RTP 发送控制（GB28181 回传）
- 事件通知（通过 `MediaSourceEvent` 接口）

---

## 2. 继承关系

```
TrackSource          (提供 getTracks 接口)
    └── MediaSource  (流注册/管理/查找)
            ├── RtspMediaSource   (RTSP 流，RTP 环形缓冲)
            ├── RtmpMediaSource   (RTMP 流，FLV Tag 环形缓冲)
            ├── HlsMediaSource    (HLS 流，m3u8/ts 文件)
            ├── FMP4MediaSource   (HTTP-FMP4 流)
            └── TSMediaSource     (HTTP-TS 流)
```

---

## 3. 成员变量

| 变量名 | 类型 | 用途 |
|--------|------|------|
| `_schema` | `string` | 协议类型（rtsp/rtmp/hls/fmp4/ts） |
| `_tuple` | `MediaTuple` | 流标识（vhost/app/stream） |
| `_listener` | `weak_ptr<MediaSourceEvent>` | 事件监听器（通常是推流 Session 或 Muxer） |
| `_create_stamp` | `time_t` | 流创建时间（Unix 时间戳） |
| `_ticker` | `Ticker` | 流上线计时器 |
| `_speed` | `BytesSpeed[TrackMax]` | 各轨道的数据速率统计 |
| `_owned` | `atomic_flag` | 流所有权标志（防止重复注册） |
| `_statistic` | `ObjectStatistic<MediaSource>` | 对象数量统计（调试用） |

---

## 4. 核心函数详解

### 4.1 `regist()` — 流注册

```cpp
void MediaSource::regist()
```

**功能：** 将当前流注册到全局流注册表（`static map`），并广播 `kBroadcastMediaChanged` 事件。

**关键逻辑：**
1. 以 `schema + vhost + app + stream` 为 key 插入全局 map
2. 触发 `emitEvent(true)` 广播注册事件
3. 若已有同名流，旧流会被替换（支持断连续推）

**调用时机：** 在 `RtspMediaSourceImp`、`RtmpMediaSourceImp` 等子类构造完成后调用。

---

### 4.2 `unregist()` — 流注销

```cpp
bool MediaSource::unregist()
```

**功能：** 从全局注册表移除当前流，广播注销事件。

**调用时机：** 析构函数中自动调用。

---

### 4.3 `find()` — 同步查找流

```cpp
static Ptr find(const string &schema, const string &vhost, const string &app, const string &id, bool from_mp4 = false);
```

**功能：** 在全局注册表中同步查找指定流。

**参数：**
- `schema`：协议类型（rtsp/rtmp 等），传空则忽略协议类型
- `vhost`：虚拟主机
- `app`：应用名
- `id`：流 ID
- `from_mp4`：若未找到，是否尝试从 MP4 文件创建点播流

**返回值：** 找到则返回 `shared_ptr<MediaSource>`，否则返回 `nullptr`。

---

### 4.4 `findAsync()` — 异步查找流

```cpp
static void findAsync(const MediaInfo &info, const shared_ptr<Session> &session, const function<void(const Ptr &src)> &cb);
```

**功能：** 异步查找流，若流不存在则等待最多 `kMaxStreamWaitTimeMS` 毫秒。

**关键逻辑：**
1. 先同步查找，找到直接回调
2. 未找到则注册一个临时监听器，等待 `kBroadcastMediaChanged` 事件
3. 超时后触发 `kBroadcastNotFoundStream` 事件（可触发按需拉流）
4. 最终回调 `cb(nullptr)` 或 `cb(src)`

**调用场景：** 播放器请求播放时，流可能还未推上来，此机制实现"先播后推"。

---

### 4.5 `setupRecord()` — 录制控制

```cpp
bool setupRecord(Recorder::type type, bool start, const string &custom_path, size_t max_second);
```

**功能：** 开启或关闭 HLS/MP4 录制。

**参数：**
- `type`：`Recorder::type_hls` 或 `Recorder::type_mp4`
- `start`：true 开启，false 关闭
- `custom_path`：自定义录制路径（空则使用默认路径）
- `max_second`：MP4 最大切片时长（秒）

**实现：** 委托给 `_listener`（即 `MultiMediaSourceMuxer`）处理。

---

### 4.6 `startSendRtp()` — 开始 RTP 发送

```cpp
void startSendRtp(const MediaSourceEvent::SendRtpArgs &args, const function<void(uint16_t, const SockException &)> cb);
```

**功能：** 将当前流以 RTP 方式发送给指定目标（GB28181 回传）。

**`SendRtpArgs` 关键字段：**
- `data_type`：ES/PS/TS 流类型
- `con_type`：TCP主动/UDP主动/TCP被动/UDP被动
- `dst_url`/`dst_port`：目标地址
- `ssrc`：RTP SSRC
- `pt`：RTP Payload Type

---

### 4.7 `for_each_media()` — 遍历所有流

```cpp
static void for_each_media(const function<void(const Ptr &src)> &cb, const string &schema = "", ...);
```

**功能：** 遍历全局注册表中的所有流，支持按 schema/vhost/app/stream 过滤。

**调用场景：** WebAPI 的 `getMediaList` 接口。

---

## 5. MediaSourceEvent 接口

`MediaSourceEvent` 是 `MediaSource` 的事件监听器接口，通常由推流 Session 或 `MultiMediaSourceMuxer` 实现。

| 方法 | 说明 |
|------|------|
| `getOriginType()` | 返回流来源类型（rtmp_push/rtsp_push/pull 等） |
| `getOriginUrl()` | 返回推流 URL 或文件路径 |
| `getOriginSock()` | 返回推流客户端的 Socket 信息 |
| `seekTo(stamp)` | 拖动进度条（点播用） |
| `pause(pause)` | 暂停/恢复（点播用） |
| `close(sender)` | 通知推流端关闭流 |
| `totalReaderCount(sender)` | 返回总观看人数 |
| `onReaderChanged(sender, size)` | 观看人数变化通知 |
| `onRegist(sender, regist)` | 流注册/注销通知 |
| `getLossRate(sender, type)` | 获取丢包率 |
| `getOwnerPoller(sender)` | 获取所属事件线程 |

---

## 6. ProtocolOption 配置类

`ProtocolOption` 控制 `MultiMediaSourceMuxer` 的转协议行为，可通过 `on_publish` WebHook 回复动态设置。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `modify_stamp` | int | 2 | 时间戳修复模式（0=原始/1=系统时间/2=相对时间） |
| `enable_audio` | bool | true | 是否转发音频 |
| `add_mute_audio` | bool | true | 无音频时是否添加静音 |
| `auto_close` | bool | false | 无人观看时是否自动关闭 |
| `continue_push_ms` | uint32_t | 15000 | 断连续推等待时间（ms） |
| `enable_hls` | bool | true | 是否转 HLS |
| `enable_mp4` | bool | false | 是否录制 MP4 |
| `enable_rtsp` | bool | true | 是否转 RTSP |
| `enable_rtmp` | bool | true | 是否转 RTMP/FLV |
| `enable_ts` | bool | true | 是否转 HTTP-TS |
| `enable_fmp4` | bool | true | 是否转 HTTP-FMP4 |
| `hls_demand` | bool | false | HLS 是否按需生成 |
| `rtsp_demand` | bool | false | RTSP 是否按需生成 |
| `rtmp_demand` | bool | false | RTMP 是否按需生成 |

---

## 7. 调用链示意

```
RTMP推流 → RtmpSession::onCmd_publish()
    → NoticeCenter::kBroadcastMediaPublish
    → WebHook::on_publish (鉴权)
    → RtmpSession 创建 RtmpMediaSourceImp
        → RtmpMediaSourceImp 创建 MultiMediaSourceMuxer
            → MultiMediaSourceMuxer 创建各协议 MediaSource
                → 各 MediaSource::regist()
                    → NoticeCenter::kBroadcastMediaChanged
                    → WebHook::on_stream_changed
```
