/*
 * Copyright (c) 2016-present The ZLMediaKit project authors. All Rights Reserved.
 *
 * This file is part of ZLMediaKit(https://github.com/ZLMediaKit/ZLMediaKit).
 *
 * Use of this source code is governed by MIT-like license that can be found in the
 * LICENSE file in the root of the source tree. All contributing project authors
 * may be found in the AUTHORS file in the root of the source tree.
 */

#ifndef ZLMEDIAKIT_WEBHOOK_H
#define ZLMEDIAKIT_WEBHOOK_H

#include <string>
#include <functional>
#include "json/json.h"
#include "Common/MediaSource.h"

// 支持json或urlencoded方式传输参数  [AUTO-TRANSLATED:0e14d484]
// // Support json or urlencoded way to transmit parameters
#define JSON_ARGS

#ifdef JSON_ARGS
typedef Json::Value ArgsType;
#else
typedef mediakit::HttpArgs ArgsType;
#endif

namespace Hook {
// web hook回复最大超时时间  [AUTO-TRANSLATED:9a059363]
// Maximum timeout for web hook reply
extern const std::string kTimeoutSec;
}//namespace Hook

void installWebHook();
void unInstallWebHook();
void onProcessExited();
/**
 * 触发http hook请求
 * @param url 请求地址
 * @param body 请求body
 * @param func 回调
 * Trigger http hook request
 * @param url Request address
 * @param body Request body
 * @param func Callback
 
 
 * [AUTO-TRANSLATED:8ffdd09b]
 */
void do_http_hook(const std::string &url, const ArgsType &body, const std::function<void(const Json::Value &, const std::string &)> &func = nullptr);

/**
 * 触发拉流代理状态 hook
 * @param is_start true=拉流成功, false=拉流结束
 * @param key      proxy key (shortUrl)
 * @param tuple    媒体元组
 * @param url      源流地址
 * @param err_msg  结束原因（is_start=true 时为空）
 */
void do_stream_proxy_hook(bool is_start, const std::string &key,
                          const mediakit::MediaTuple &tuple,
                          const std::string &url,
                          const std::string &err_msg);
#endif //ZLMEDIAKIT_WEBHOOK_H
