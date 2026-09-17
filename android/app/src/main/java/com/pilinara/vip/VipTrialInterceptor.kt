package com.pilinara.vip

import com.pilinara.core.NativeCore
import okhttp3.Interceptor
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

/**
 * 对 B 站 JSON 响应做大会员字段本地改写（nav / playurl 等）。
 *
 * 纯字段重写由 Rust 核心完成，这里只决定「哪些响应需要改写」：
 * - 开关关闭时直接透传；
 * - 仅处理 bilibili.com 域名下的 JSON 响应，避免误伤第三方源。
 */
class VipTrialInterceptor : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val response = chain.proceed(chain.request())
        if (!VipTrialGate.enabled) return response

        val host = chain.request().url.host
        val path = chain.request().url.encodedPath
        // 哔哩漫游式解析服务器不在 bilibili.com 域名下，但它返回的 playurl 同样需要
        // 清除 trial 标记 / 改写会员字段。
        val isBili = host.endsWith("bilibili.com")
        val isPlayurlProxy = path.contains("playurl")
        if (!isBili && !isPlayurlProxy) return response

        val body = response.body ?: return response
        val contentType = body.contentType()
        if (contentType?.subtype?.contains("json", ignoreCase = true) != true) return response

        val raw = body.string()
        val rewritten = NativeCore.applyVipTrial(
            raw,
            VipTrialGate.configJson(),
            System.currentTimeMillis(),
        )
        return response.newBuilder()
            .body(rewritten.toResponseBody(contentType))
            .build()
    }
}
