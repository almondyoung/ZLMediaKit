# ZLMediaKit 文档总览

本文档基于 ZLMediaKit 源码分析生成，覆盖架构设计、核心类说明、算法原理、协议分析、WebHook 事件及各角色使用指南。

## 目录结构

```
docs/
├── README.md                    # 本文件，文档总览
├── 01-overview.md               # 整体模块说明
├── 02-architecture.md           # 架构图与设计图（Mermaid）
├── 03-classes/
│   ├── 01-MediaSource.md        # MediaSource 类详解
│   ├── 02-Track-Frame.md        # Track / Frame 类详解
│   ├── 03-MultiMediaSourceMuxer.md  # MultiMediaSourceMuxer 类详解
│   ├── 04-RtspSession.md        # RtspSession 类详解
│   ├── 05-RtmpSession.md        # RtmpSession 类详解
│   ├── 06-HttpSession.md        # HttpSession 类详解
│   └── 07-other-classes.md      # 其他核心类（Stamp、PacketCache 等）
├── 04-algorithms.md             # 算法说明
├── 05-roles/
│   ├── 01-architect.md          # 架构师指南
│   ├── 02-developer.md          # 开发人员指南
│   └── 03-user.md               # 用户手册
├── 06-protocols.md              # 协议与格式专项分析
└── 07-webhook.md                # WebHook 回调事件
```

## 快速导航

| 文档 | 适合人群 | 内容摘要 |
|------|----------|----------|
| [整体模块说明](01-overview.md) | 所有人 | 模块划分、职责、依赖关系 |
| [架构图](02-architecture.md) | 架构师/开发者 | 分层架构、组件图、类图、序列图 |
| [类详解](03-classes/) | 开发者 | 每个核心类的函数、成员变量、调用链 |
| [算法说明](04-algorithms.md) | 开发者 | GOP 缓存、时间戳修复、拥塞控制等 |
| [架构师指南](05-roles/01-architect.md) | 架构师 | 设计思想、扩展性、性能考虑 |
| [开发人员指南](05-roles/02-developer.md) | 开发者 | 插件开发、测试用例、部署说明 |
| [用户手册](05-roles/03-user.md) | 用户/运维 | 搭建服务器、推拉流 URL、配置说明 |
| [协议分析](06-protocols.md) | 开发者/用户 | RTSP/RTMP/HLS/WebRTC/SRT 等 |
| [WebHook 事件](07-webhook.md) | 开发者/用户 | 所有事件列表、请求格式、示例 |
