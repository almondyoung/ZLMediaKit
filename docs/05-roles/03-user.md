# 用户手册

## 1. 快速开始

### 1.1 下载与启动

```bash
# 方式一：使用 Docker（推荐）
docker run -d \
  --name zlmediakit \
  -p 1935:1935 -p 554:554 -p 80:80 \
  zlmediakit/zlmediakit:master

# 方式二：编译安装
git clone --depth 1 https://github.com/ZLMediaKit/ZLMediaKit
cd ZLMediaKit && git submodule update --init
mkdir build && cd build && cmake .. && make -j4
cd ../release/linux/Release && ./MediaServer
```

### 1.2 验证服务

```bash
# 检查服务状态
curl http://localhost/index/api/version

# 推一路测试流
ffmpeg -re -i /path/to/test.mp4 -c copy -f flv rtmp://localhost/live/test

# 播放测试
ffplay rtsp://localhost/live/test
# 或浏览器打开 http://localhost/live/test.flv
```

---

## 2. 推流 URL 格式

### 2.1 RTMP 推流

```
rtmp://host[:1935]/app/stream[?参数]
```

**示例：**
```bash
# 基础推流
ffmpeg -re -i input.mp4 -c copy -f flv rtmp://localhost/live/mystream

# 带虚拟主机
ffmpeg -re -i input.mp4 -c copy -f flv "rtmp://localhost/live/mystream?vhost=example.com"

# 带鉴权参数（由业务服务器验证）
ffmpeg -re -i input.mp4 -c copy -f flv "rtmp://localhost/live/mystream?token=abc123"
```

### 2.2 RTSP 推流

```
rtsp://host[:554]/app/stream[?参数]
```

```bash
ffmpeg -re -i input.mp4 -c copy -f rtsp rtsp://localhost/live/mystream
```

### 2.3 SRT 推流

```
srt://host[:9000]?streamid=app/stream
```

```bash
ffmpeg -re -i input.mp4 -c copy -f mpegts "srt://localhost:9000?streamid=live/mystream"
```

### 2.4 GB28181 RTP 推流

通过 API 开启 RTP 接收端口，然后让摄像头推流：

```bash
# 开启 RTP 接收端口
curl "http://localhost/index/api/openRtpServer?secret=xxx&port=10001&tcp_mode=0&stream_id=camera01"

# 摄像头配置：
# 服务器地址: localhost
# 服务器端口: 10001
# 传输协议: UDP
```

---

## 3. 播放 URL 格式

### 3.1 RTSP 播放

```
rtsp://host[:554]/app/stream
rtsps://host[:332]/app/stream  (SSL加密)
```

```bash
# VLC 播放
vlc rtsp://localhost/live/mystream

# FFplay 播放
ffplay rtsp://localhost/live/mystream

# 强制 TCP 传输
ffplay -rtsp_transport tcp rtsp://localhost/live/mystream
```

### 3.2 RTMP 播放

```
rtmp://host[:1935]/app/stream
rtmps://host[:19350]/app/stream  (SSL加密)
```

```bash
ffplay rtmp://localhost/live/mystream
```

### 3.3 HTTP-FLV 播放

```
http://host[:80]/app/stream.flv
https://host[:443]/app/stream.flv
```

适合浏览器通过 flv.js 播放：
```html
<script src="flv.min.js"></script>
<video id="videoElement"></video>
<script>
  var flvPlayer = flvjs.createPlayer({
    type: 'flv',
    url: 'http://localhost/live/mystream.flv'
  });
  flvPlayer.attachMediaElement(document.getElementById('videoElement'));
  flvPlayer.load();
  flvPlayer.play();
</script>
```

### 3.4 HLS 播放

```
http://host[:80]/app/stream/hls.m3u8
http://host[:80]/app/stream/hls.fmp4.m3u8  (FMP4格式)
```

适合 iOS/Safari 原生播放，或通过 hls.js 在浏览器播放：
```html
<script src="hls.min.js"></script>
<video id="video"></video>
<script>
  var hls = new Hls();
  hls.loadSource('http://localhost/live/mystream/hls.m3u8');
  hls.attachMedia(document.getElementById('video'));
</script>
```

### 3.5 HTTP-FMP4 播放

```
http://host[:80]/app/stream.mp4
ws://host[:80]/app/stream.mp4  (WebSocket)
```

适合通过 MSE 在浏览器播放。

### 3.6 HTTP-TS 播放

```
http://host[:80]/app/stream.ts
ws://host[:80]/app/stream.ts  (WebSocket)
```

### 3.7 WebRTC 播放

```
webrtc://host/app/stream
```

通过 ZLMediaKit 提供的 WebRTC 信令接口播放，适合超低延迟场景（< 200ms）。

---

## 4. 虚拟主机

ZLMediaKit 支持虚拟主机，同一服务器可以托管多个域名的流：

```bash
# 推流时指定虚拟主机
ffmpeg -re -i input.mp4 -c copy -f flv "rtmp://localhost/live/test?vhost=example.com"

# 播放时指定虚拟主机
ffplay "rtsp://localhost/live/test?vhost=example.com"
```

**配置：**
```ini
[general]
enableVhost=1  # 启用虚拟主机
```

---

## 5. 配置文件说明

配置文件位于 `config.ini`，主要配置项：

### 5.1 服务器端口

```ini
[rtsp]
port=554          # RTSP 端口
sslport=332       # RTSPS 端口

[rtmp]
port=1935         # RTMP 端口
sslport=19350     # RTMPS 端口

[http]
port=80           # HTTP 端口
sslport=443       # HTTPS 端口

[shell]
port=9000         # Shell 管理端口

[rtp_proxy]
port=10000        # GB28181 RTP 默认端口
```

### 5.2 转协议配置

```ini
[protocol]
# 时间戳修复模式（推荐保持默认值 2）
modify_stamp=2

# 是否转换为各种协议（1=开启，0=关闭）
enable_hls=1
enable_mp4=0      # 默认不录制 MP4
enable_rtsp=1
enable_rtmp=1
enable_ts=1
enable_fmp4=1

# 按需转协议（1=有播放器才转，0=推流即转）
hls_demand=0
rtsp_demand=0
rtmp_demand=0
```

### 5.3 HLS 配置

```ini
[hls]
segDur=2          # 切片时长（秒）
segNum=3          # m3u8 中保留的切片数（0=不删除，用于录制）
segKeep=0         # 是否保留切片文件
fileBufSize=65536 # 文件写缓冲大小
```

### 5.4 录制配置

```ini
[protocol]
enable_mp4=1              # 开启 MP4 录制
mp4_save_path=./www       # MP4 保存路径
mp4_max_second=3600       # 每个 MP4 文件最大时长（秒）
mp4_as_player=0           # MP4 录制是否算作观看者

hls_save_path=./www       # HLS 保存路径
```

### 5.5 WebHook 配置

```ini
[hook]
enable=1                                    # 启用 WebHook
timeoutSec=10                               # WebHook 超时时间（秒）
on_publish=http://your-server/on_publish    # 推流鉴权
on_play=http://your-server/on_play          # 播放鉴权
on_stream_changed=http://your-server/on_stream_changed  # 流变化通知
on_stream_not_found=http://your-server/on_stream_not_found  # 流未找到
on_stream_none_reader=http://your-server/on_stream_none_reader  # 无人观看
on_record_mp4=http://your-server/on_record_mp4  # MP4 录制完成
on_flow_report=http://your-server/on_flow_report  # 流量统计
alive_interval=30                           # 保活心跳间隔（秒）
```

---

## 6. REST API 常用接口

所有 API 需要携带 `secret` 参数（或通过 127.0.0.1 访问可免 secret）。

### 6.1 流管理

```bash
# 获取所有流列表
GET /index/api/getMediaList?secret=xxx

# 获取指定流信息
GET /index/api/getMediaList?secret=xxx&schema=rtmp&vhost=__defaultVhost__&app=live&stream=test

# 关闭流
GET /index/api/close_stream?secret=xxx&schema=rtmp&vhost=__defaultVhost__&app=live&stream=test&force=1

# 添加拉流代理
POST /index/api/addStreamProxy
{
  "secret": "xxx",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "proxy",
  "url": "rtsp://camera/stream",
  "retry_count": -1
}

# 删除拉流代理
GET /index/api/delStreamProxy?secret=xxx&key=<proxy_key>
```

### 6.2 录制管理

```bash
# 开始录制 MP4（type=1）或 HLS（type=0）
GET /index/api/startRecord?secret=xxx&type=1&vhost=__defaultVhost__&app=live&stream=test

# 停止录制
GET /index/api/stopRecord?secret=xxx&type=1&vhost=__defaultVhost__&app=live&stream=test

# 查询录制状态
GET /index/api/isRecording?secret=xxx&type=1&vhost=__defaultVhost__&app=live&stream=test

# 获取 MP4 录制文件列表
GET /index/api/getMp4RecordFile?secret=xxx&vhost=__defaultVhost__&app=live&stream=test&period=2024-01
```

### 6.3 截图

```bash
# 获取流截图（实时截图）
GET /index/api/getSnap?secret=xxx&url=rtsp://localhost/live/test&timeout_sec=10&expire_sec=3
```

### 6.4 GB28181 RTP

```bash
# 开启 RTP 接收端口
GET /index/api/openRtpServer?secret=xxx&port=10001&tcp_mode=0&stream_id=camera01

# 关闭 RTP 接收端口
GET /index/api/closeRtpServer?secret=xxx&stream_id=camera01

# 开始 RTP 发送（将流推送给 GB28181 平台）
POST /index/api/startSendRtp
{
  "secret": "xxx",
  "vhost": "__defaultVhost__",
  "app": "live",
  "stream": "test",
  "ssrc": "1",
  "dst_url": "192.168.1.100",
  "dst_port": 10000,
  "is_udp": 1,
  "pt": 96,
  "data_type": 1
}
```

### 6.5 系统信息

```bash
# 获取服务器版本
GET /index/api/version

# 获取服务器统计信息
GET /index/api/getStatistic?secret=xxx

# 获取线程负载
GET /index/api/getThreadsLoad?secret=xxx

# 获取网络统计
GET /index/api/getWorkThreadsLoad?secret=xxx
```

---

## 7. 常见问题

### 7.1 推流后无法播放

**检查步骤：**
1. 确认推流成功（查看日志或调用 `getMediaList` API）
2. 确认播放 URL 正确（schema/app/stream 与推流一致）
3. 检查防火墙是否开放对应端口
4. 检查 WebHook 鉴权是否返回正确格式

### 7.2 HLS 延迟高

HLS 延迟 = 切片时长 × 切片数量，默认约 6 秒。

**降低延迟：**
```ini
[hls]
segDur=1    # 切片时长改为 1 秒
segNum=2    # 保留 2 个切片
```

注意：切片时长过短会增加服务器负载和客户端请求频率。

### 7.3 RTSP 播放花屏

**原因：** 播放器未从关键帧开始解码。

**解决：**
- 确认 GOP 缓存已开启（默认开启）
- 若使用直接代理模式（`rtsp.directProxy=1`），关闭它
- 检查推流端是否正常发送 SPS/PPS

### 7.4 WebRTC 无法连接

**检查：**
1. 确认 UDP 端口（8554）已开放
2. 检查 STUN/TURN 服务器配置
3. 确认 DTLS 证书配置正确（`default.pem`）

### 7.5 MP4 录制文件损坏

**原因：** 服务器异常退出导致 MP4 文件未正确关闭。

**解决：**
```ini
[record]
fastStart=1  # 开启快速索引，录制完成后写入索引到文件头
```

或使用 FFmpeg 修复：
```bash
ffmpeg -i damaged.mp4 -c copy fixed.mp4
```
