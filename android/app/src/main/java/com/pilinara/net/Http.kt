package com.pilinara.net

import com.pilinara.vip.VipTrialInterceptor
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * 全局唯一的 OkHttp 客户端：B 站 API、第三方源抓取、Media3 视频流、Coil 图片共用连接池，
 * 统一携带 Cookie / UA，减少骁龙核心唤醒与 TLS 握手开销（低功耗）。
 */
class Http(cacheDir: File, cookieFile: File) {

    val cookieJar: PersistentCookieJar = PersistentCookieJar(cookieFile)

    val client: OkHttpClient = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .addInterceptor(VipTrialInterceptor())
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .cache(
            okhttp3.Cache(
                directory = File(cacheDir, "http_cache"),
                maxSize = 256L * 1024 * 1024,
            ),
        )
        .build()

    /** 抓第三方源页面时常用的浏览器风格请求构造。 */
    fun request(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
    ): Request.Builder = Request.Builder().url(url).apply {
        header("User-Agent", UA_WEB)
        if (referer != null) header("Referer", referer)
        headers.forEach { (k, v) -> header(k, v) }
    }

    /** 协程化 GET，返回字符串 body。 */
    suspend fun getString(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
    ): String = execute(request(url, headers, referer).get().build()) {
        it.body?.string().orEmpty()
    }

    /** 协程化 GET（二进制，如 seg.so 弹幕）。 */
    suspend fun getBytes(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
    ): ByteArray = execute(request(url, headers, referer).get().build()) {
        it.body?.bytes() ?: ByteArray(0)
    }

    /** 协程化表单 POST。 */
    suspend fun postForm(
        url: String,
        form: Map<String, String>,
        headers: Map<String, String> = emptyMap(),
    ): String {
        val body = okhttp3.FormBody.Builder().apply {
            form.forEach { (k, v) -> add(k, v) }
        }.build()
        return execute(request(url, headers).post(body).build()) {
            it.body?.string().orEmpty()
        }
    }

    private suspend fun <T> execute(request: Request, read: (Response) -> T): T =
        suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    cont.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        runCatching { read(it) }
                            .onSuccess { v -> cont.resume(v) }
                            .onFailure { e ->
                                cont.resumeWithException(
                                    if (e is IOException) e else IOException(e),
                                )
                            }
                    }
                }
            })
            cont.invokeOnCancellation { runCatching { call.cancel() } }
        }

    companion object {
        const val UA_WEB =
            "Mozilla/5.0 (Linux; Android 17; SM8750) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/148.0.0.0 Mobile Safari/537.36"

        @Suppress("unused")
        fun isHttpUrl(url: String): Boolean = runCatching { url.toHttpUrl() }.isSuccess
    }
}
