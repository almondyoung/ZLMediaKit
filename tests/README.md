此目录下的所有.cpp文件将被编译成可执行程序(不包含此目录下的子目录).
子目录DeviceHK为海康IPC的适配程序,需要先下载海康的SDK才能编译,
由于操作麻烦,所以仅把源码放在这里仅供参考.

- http_publish_smoke.sh

  http-flv/http-ts/http-ps 推流端到端smoke测试脚本, 覆盖POST/PUT、.live.*和短后缀、on_publish stream_replace并发占用; 需要先构建MediaServer, 并安装ffmpeg/curl/python3.
  GitHub Actions入口为.github/workflows/http_publish_smoke.yml, 覆盖默认构建、关闭HLS、关闭RTPProxy三类矩阵.

- test_benchmark.cpp

    rtsp/rtmp性能测试客户端

- test_httpApi.cpp

  http api 测试服务器

- test_httpClient.cpp

   http 测试客户端

- test_player.cpp

   rtsp/rtmp带视频渲染的客户端

- test_pusher.cpp

   先拉流再推流的测试客户端

- test_pusherMp4.cpp

   解复用mp4文件再推流的测试客户端

- test_server.cpp

   rtsp/rtmp/http等服务器

- test_wsClient.cpp

  websocket测试客户端

- test_wsServer.cpp

   websocket回显测试服务器
