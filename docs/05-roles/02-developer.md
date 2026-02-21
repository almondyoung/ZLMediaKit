# 开发人员指南

## 1. 编译与构建

### 1.1 依赖安装

**Ubuntu/Debian：**
```bash
# 基础依赖
sudo apt-get install -y cmake git build-essential

# SSL 支持
sudo apt-get install -y libssl-dev

# MP4 录制支持（可选）
sudo apt-get install -y libavcodec-dev libavformat-dev libavutil-dev

# SRT 支持（可选）
sudo apt-get install -y libsrt-dev

# WebRTC 支持（可选）
sudo apt-get install -y libsrtp2-dev
```

**macOS：**
```bash
brew install cmake openssl
```

### 1.2 编译

```bash
git clone --depth 1 https://github.com/ZLMediaKit/ZLMediaKit
cd ZLMediaKit
git submodule update --init

mkdir build && cd build

# 基础编译
cmake .. -DCMAKE_BUILD_TYPE=Release

# 启用所有功能
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_WEBRTC=ON \
  -DENABLE_SRT=ON \
  -DENABLE_MP4=ON \
  -DENABLE_RTPPROXY=ON

make -j$(nproc)
```

### 1.3 编译选项

| 选项 | 默认 | 说明 |
|------|------|------|
| `ENABLE_WEBRTC` | OFF | 启用 WebRTC 支持 |
| `ENABLE_SRT` | OFF | 启用 SRT 支持 |
| `ENABLE_MP4` | OFF | 启用 MP4 录制（需要 FFmpeg） |
| `ENABLE_RTPPROXY` | ON | 启用 GB28181 RTP 代理 |
| `ENABLE_PYTHON` | OFF | 启用 Python 插件 |
| `ENABLE_FFMPEG` | OFF | 启用 FFmpeg 拉流 |
| `USE_SOLUTION_FOLDERS` | OFF | 生成 IDE 项目文件 |

---

## 2. 教学用例：开发新协议插件

以添加一个简单的自定义 TCP 协议为例，该协议接收原始 H264 裸流。

### 2.1 创建 Session 类

```cpp
// src/MyProtocol/MySession.h
#include "Network/Session.h"
#include "Common/MultiMediaSourceMuxer.h"
#include "ext-codec/H264.h"

class MySession : public toolkit::Session {
public:
    MySession(const toolkit::Socket::Ptr &sock) : Session(sock) {}

    void onRecv(const toolkit::Buffer::Ptr &buf) override {
        // 解析自定义协议，提取 H264 NALU
        parseData(buf->data(), buf->size());
    }

    void onError(const toolkit::SockException &err) override {
        // 连接断开，清理资源
        _muxer = nullptr;
    }

    void onManager() override {
        // 定时检查超时
    }

private:
    void parseData(const char *data, size_t len) {
        // 假设数据格式：4字节长度 + NALU 数据
        // 实际实现需要处理粘包/拆包
        
        if (!_muxer) {
            // 创建媒体源
            mediakit::MediaTuple tuple;
            tuple.vhost = "__defaultVhost__";
            tuple.app = "live";
            tuple.stream = getIdentifier();
            
            _muxer = std::make_shared<mediakit::MultiMediaSourceMuxer>(tuple);
            
            // 创建 H264 Track
            _track = std::make_shared<mediakit::H264Track>();
            _muxer->addTrack(_track);
        }
        
        // 构造 Frame
        auto frame = mediakit::FrameImp::create();
        frame->_codec_id = mediakit::CodecH264;
        frame->_dts = getCurrentMs();
        frame->_buffer.assign(data, len);
        frame->_prefix_size = 4; // 0x00000001 前缀
        
        // 输入帧数据
        _track->inputFrame(frame);
    }

private:
    mediakit::MultiMediaSourceMuxer::Ptr _muxer;
    std::shared_ptr<mediakit::H264Track> _track;
};
```

### 2.2 在 main.cpp 中启动服务器

```cpp
// 在 main.cpp 中添加
#include "MyProtocol/MySession.h"

// 启动自定义协议服务器（端口 9999）
auto my_server = std::make_shared<toolkit::TcpServer>();
my_server->start<MySession>(9999);
```

### 2.3 测试

```bash
# 使用 FFmpeg 推流
ffmpeg -re -i test.mp4 -c:v copy -f rawvideo tcp://localhost:9999

# 使用 VLC 播放（RTSP 协议）
vlc rtsp://localhost/live/<session_id>
```

---

## 3. 教学用例：添加自定义 WebHook 事件

### 3.1 在 config.h 中定义新事件

```cpp
// src/Common/config.h
namespace Broadcast {
    // 自定义事件：流质量报告
    extern const std::string kBroadcastStreamQuality;
    #define BroadcastStreamQualityArgs const std::string &stream_id, float fps, float bitrate
}
```

### 3.2 在 config.cpp 中实现

```cpp
// src/Common/config.cpp
namespace Broadcast {
    const std::string kBroadcastStreamQuality = "kBroadcastStreamQuality";
}
```

### 3.3 在适当位置触发事件

```cpp
// 在 MultiMediaSourceMuxer 中定期触发
void MultiMediaSourceMuxer::reportQuality() {
    float fps = _ring->getVideoFps();
    float bitrate = _ring->getBitRate();
    
    NOTICE_EMIT(BroadcastStreamQualityArgs, 
                Broadcast::kBroadcastStreamQuality,
                _tuple.stream, fps, bitrate);
}
```

### 3.4 在 WebHook.cpp 中监听并发送 HTTP 回调

```cpp
// server/WebHook.cpp
namespace Hook {
    const string kOnStreamQuality = HOOK_FIELD "on_stream_quality";
}

// 在 installWebHook() 中添加
NoticeCenter::Instance().addListener(&web_hook_tag, 
    Broadcast::kBroadcastStreamQuality, 
    [](BroadcastStreamQualityArgs) {
        GET_CONFIG(string, hook_url, Hook::kOnStreamQuality);
        if (!hook_enable || hook_url.empty()) return;
        
        ArgsType body;
        body["stream_id"] = stream_id;
        body["fps"] = fps;
        body["bitrate"] = bitrate;
        
        do_http_hook(hook_url, body, nullptr);
    });
```

---

## 4. 测试用例

### 4.1 推流测试

```bash
# RTMP 推流
ffmpeg -re -i test.mp4 -c copy -f flv rtmp://localhost/live/test

# RTSP 推流
ffmpeg -re -i test.mp4 -c copy -f rtsp rtsp://localhost/live/test

# SRT 推流（需编译 SRT 支持）
ffmpeg -re -i test.mp4 -c copy -f mpegts srt://localhost:9000?streamid=live/test
```

### 4.2 播放测试

```bash
# RTSP 播放
ffplay rtsp://localhost/live/test

# RTMP 播放
ffplay rtmp://localhost/live/test

# HTTP-FLV 播放
ffplay http://localhost/live/test.flv

# HLS 播放
ffplay http://localhost/live/test/hls.m3u8

# HTTP-FMP4 播放
ffplay http://localhost/live/test.mp4

# HTTP-TS 播放
ffplay http://localhost/live/test.ts
```

### 4.3 API 测试

```bash
# 获取流列表
curl "http://localhost/index/api/getMediaList?secret=035c73f7-bb6b-4889-a715-d9eb2d1925cc"

# 开始录制 MP4
curl "http://localhost/index/api/startRecord?secret=xxx&type=1&vhost=__defaultVhost__&app=live&stream=test"

# 停止录制
curl "http://localhost/index/api/stopRecord?secret=xxx&type=1&vhost=__defaultVhost__&app=live&stream=test"

# 添加拉流代理
curl -X POST "http://localhost/index/api/addStreamProxy" \
  -H "Content-Type: application/json" \
  -d '{"secret":"xxx","vhost":"__defaultVhost__","app":"live","stream":"proxy","url":"rtsp://camera/stream"}'

# 截图
curl "http://localhost/index/api/getSnap?secret=xxx&url=rtsp://localhost/live/test&timeout_sec=10&expire_sec=3"
```

### 4.4 WebHook 测试

使用 Python 搭建简单的 WebHook 服务器：

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/on_publish', methods=['POST'])
def on_publish():
    data = request.json
    print(f"推流: {data['app']}/{data['stream']} from {data['ip']}")
    # 允许所有推流
    return jsonify({"code": 0, "msg": "success"})

@app.route('/on_play', methods=['POST'])
def on_play():
    data = request.json
    print(f"播放: {data['app']}/{data['stream']} from {data['ip']}")
    # 允许所有播放
    return jsonify({"code": 0, "msg": "success"})

@app.route('/on_stream_changed', methods=['POST'])
def on_stream_changed():
    data = request.json
    action = "注册" if data['regist'] else "注销"
    print(f"流{action}: {data['schema']}://{data['app']}/{data['stream']}")
    return jsonify({"code": 0})

if __name__ == '__main__':
    app.run(port=8080)
```

配置 `config.ini`：
```ini
[hook]
enable=1
on_publish=http://localhost:8080/on_publish
on_play=http://localhost:8080/on_play
on_stream_changed=http://localhost:8080/on_stream_changed
```

---

## 5. 部署说明

### 5.1 目录结构

```
release/linux/Release/
├── MediaServer          # 可执行文件
├── config.ini           # 配置文件
├── default.pem          # SSL 证书（自签名）
└── www/                 # HTTP 根目录
    ├── index.html
    └── snap/            # 截图保存目录
```

### 5.2 启动与停止

```bash
# 前台启动
./MediaServer

# 指定配置文件
./MediaServer -c /path/to/config.ini

# 后台启动
./MediaServer -d &

# 停止
kill -SIGTERM $(cat MediaServer.pid)
# 或
./MediaServer -s stop
```

### 5.3 systemd 服务

```ini
# /etc/systemd/system/zlmediakit.service
[Unit]
Description=ZLMediaKit Media Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/zlmediakit
ExecStart=/opt/zlmediakit/MediaServer -c /opt/zlmediakit/config.ini
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable zlmediakit
systemctl start zlmediakit
systemctl status zlmediakit
```

### 5.4 Docker 部署

```bash
# 使用官方 Docker 镜像
docker pull zlmediakit/zlmediakit:master

docker run -d \
  --name zlmediakit \
  -p 1935:1935 \   # RTMP
  -p 554:554 \     # RTSP
  -p 80:80 \       # HTTP
  -p 443:443 \     # HTTPS
  -p 10000:10000/udp \  # RTP/GB28181
  -v /path/to/config.ini:/opt/media/conf/config.ini \
  -v /path/to/www:/opt/media/www \
  zlmediakit/zlmediakit:master
```

### 5.5 Nginx 反向代理

```nginx
# HTTP-FLV / HLS / API
server {
    listen 80;
    server_name media.example.com;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_buffering off;  # 直播流必须关闭缓冲
    }
}

# RTMP（需要 nginx-rtmp-module，通常直接暴露 1935 端口）
```

### 5.6 防火墙配置

```bash
# 开放必要端口
ufw allow 1935/tcp   # RTMP
ufw allow 554/tcp    # RTSP
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
ufw allow 10000/udp  # RTP/GB28181
ufw allow 8554/udp   # WebRTC（DTLS/SRTP）
```

---

## 6. 日志说明

ZLMediaKit 使用 ZLToolKit 的日志系统，日志级别：

| 级别 | 说明 |
|------|------|
| `TraceL` | 最详细的调试信息 |
| `DebugL` | 调试信息 |
| `InfoL` | 一般信息 |
| `WarnL` | 警告 |
| `ErrorL` | 错误 |

**日志配置：**
```cpp
// 设置日志级别
Logger::Instance().setLevel(LTrace);

// 添加控制台输出
Logger::Instance().add(std::make_shared<ConsoleChannel>());

// 添加文件输出
Logger::Instance().add(std::make_shared<FileChannel>("MediaServer.log", LDebug));
```

**常见日志含义：**
```
[I] 推流成功: rtmp://localhost/live/test
[W] 无人观看: rtmp://localhost/live/test
[E] 推流鉴权失败: unauthorized
```
