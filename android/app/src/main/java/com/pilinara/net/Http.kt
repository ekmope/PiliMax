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
        // 浏览器伪装头必须最先生效，后续 VIP 改写拦截器只动响应体。
        .addBrowserFingerprintHeaders()
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
        origin: String? = null,
    ): Request.Builder = Request.Builder().url(url).apply {
        header("User-Agent", UA_WEB)
        if (referer != null) header("Referer", referer)
        if (origin != null) header("Origin", origin)
        headers.forEach { (k, v) -> header(k, v) }
    }

    /** 协程化 GET，返回字符串 body（按响应声明的 UTF-8 解码，适合 JSON / B 站接口）。 */
    suspend fun getString(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
        origin: String? = null,
    ): String = execute(request(url, headers, referer, origin).get().build()) {
        it.body?.string().orEmpty()
    }

    /**
     * 抓取第三方站点 HTML：很多老旧番剧站不返回 Content-Type charset（或声明 GB2312/GBK），
     * 默认按 UTF-8 解码会乱码导致选择器全部失效。这里依次用 ① 响应头 charset
     * ② 页面前 4KB 的 `<meta charset>` / http-equiv 声明 ③ UTF-8 兜底。
     */
    suspend fun getHtml(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
        origin: String? = null,
    ): String = execute(request(url, headers, referer, origin).get().build()) { resp ->
        val bytes = resp.body?.bytes() ?: ByteArray(0)
        HtmlCharset.decode(bytes, resp.header("Content-Type"))
    }

    /** 协程化 GET（二进制，如 seg.so 弹幕）。 */
    suspend fun getBytes(
        url: String,
        headers: Map<String, String> = emptyMap(),
        referer: String? = null,
        origin: String? = null,
    ): ByteArray = execute(request(url, headers, referer, origin).get().build()) {
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
        /**
         * 统一伪装为 Windows 桌面 Chrome：逆向实测 B 站 web/player 接口对移动端 UA 有更严格的
         * 风控降级（playurl 412 / 仅给低清晰度），桌面 Chrome 标识在搜索、playurl、seg.so
         * 弹幕、CDN 视频流上均稳定放行。播放流只校验 Referer，不挑 UA。
         */
        const val UA_WEB =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/148.0.0.0 Safari/537.36"

        @Suppress("unused")
        fun isHttpUrl(url: String): Boolean = runCatching { url.toHttpUrl() }.isSuccess
    }
}

/**
 * 给 B 站域名请求补齐桌面 Chrome 的 Client Hints / 语言 / XHR 风格头，
 * 降低 412 指纹风控命中率。只作用于 bilibili.com 系域名，不影响第三方源抓取。
 */
private fun OkHttpClient.Builder.addBrowserFingerprintHeaders(): OkHttpClient.Builder =
    addInterceptor { chain ->
        val req = chain.request()
        val host = req.url.host
        if (!host.endsWith("bilibili.com")) return@addInterceptor chain.proceed(req)
        val b = req.newBuilder()
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("sec-ch-ua", "\"Chromium\";v=\"148\", \"Not?A_Brand\";v=\"24\", \"Google Chrome\";v=\"148\"")
            .header("sec-ch-ua-mobile", "?0")
            .header("sec-ch-ua-platform", "\"Windows\"")
        if (req.header("Accept") == null) {
            b.header("Accept", "application/json, text/plain, */*")
        }
        chain.proceed(b.build())
    }

/**
 * 第三方页面编码识别（对应 animeko/kazumi 里 Jsoup 的 charset 探测）。
 * 老旧中文番剧站大量使用 GB2312/GBK，OkHttp 缺省会按 UTF-8 解成乱码。
 */
object HtmlCharset {
    private val HEADER_CHARSET = Regex("(?i)charset=\\s*\"?'?\\s*([a-z0-9_\\-]+)")
    private val META_CHARSET =
        Regex("(?is)<meta[^>]+?charset\\s*=\\s*[\"']?\\s*([a-zA-Z0-9_\\-]+)")

    fun decode(bytes: ByteArray, contentType: String?): String {
        if (bytes.isEmpty()) return ""
        // BOM
        if (bytes.size >= 3 && bytes[0] == 0xEF.toByte() && bytes[1] == 0xBB.toByte() &&
            bytes[2] == 0xBF.toByte()
        ) {
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        val declared = contentType?.let { nameFrom(it) }
            ?: bytes.copyOf(minOf(bytes.size, 4096))
                .toString(Charsets.ISO_8859_1)
                .let { head -> META_CHARSET.find(head)?.groupValues?.get(1)?.lowercase() }
        val charset = declared?.let(::resolve) ?: Charsets.UTF_8
        return String(bytes, charset)
    }

    private fun nameFrom(header: String): String? =
        HEADER_CHARSET.find(header)?.groupValues?.get(1)?.lowercase()

    private fun resolve(name: String): java.nio.charset.Charset? {
        val canonical = when (name) {
            "gb2312", "gbk", "gb18030", "x-gbk" -> "GB18030" // GB18030 是 GBK/GB2312 的超集
            "utf8", "utf-8" -> "UTF-8"
            "big5" -> "Big5"
            "windows-1252", "iso-8859-1", "latin1" -> "ISO-8859-1"
            else -> name
        }
        return runCatching {
            val cs = java.nio.charset.Charset.forName(canonical)
            if (java.nio.charset.Charset.isSupported(cs.name())) cs else null
        }.getOrNull()
    }
}
