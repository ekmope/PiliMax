package com.pilinara.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * 持久化 CookieJar：按域名内存缓存 + JSON 落盘。
 *
 * B 站登录态（SESSDATA / bili_jct / buvid3 等）需要跨进程重启保留，且 Media3/Coil
 * 共用同一 OkHttp 客户端以携带登录 Cookie 与防盗链 Referer。
 */
class PersistentCookieJar(private val file: File) : CookieJar {

    @Serializable
    private data class CookieData(
        val name: String,
        val value: String,
        val domain: String,
        val path: String,
        val expiresAt: Long,
        val secure: Boolean,
        val hostOnly: Boolean,
    )

    // host -> (name -> Cookie)
    private val store = ConcurrentHashMap<String, MutableMap<String, Cookie>>()
    private val json = Json { ignoreUnknownKeys = true }

    init {
        load()
    }

    @Synchronized
    private fun load() {
        if (!file.exists()) return
        runCatching {
            val list = json.decodeFromString<List<CookieData>>(file.readText())
            val now = System.currentTimeMillis()
            for (c in list) {
                if (c.expiresAt <= now) continue
                val cookie = Cookie.Builder()
                    .name(c.name)
                    .value(c.value)
                    .path(c.path)
                    .expiresAt(c.expiresAt)
                    .apply {
                        if (c.hostOnly) hostOnlyDomain(c.domain) else domain(c.domain)
                        if (c.secure) secure()
                    }
                    .build()
                store.computeIfAbsent(c.domain) { ConcurrentHashMap() }[c.name] = cookie
            }
        }
    }

    @Synchronized
    private fun persist() {
        val now = System.currentTimeMillis()
        val all = store.values.flatMap { it.values }
            .filter { it.expiresAt >= now }
            .map {
                CookieData(
                    name = it.name,
                    value = it.value,
                    domain = it.domain,
                    path = it.path,
                    expiresAt = it.expiresAt,
                    secure = it.secure,
                    hostOnly = it.hostOnly,
                )
            }
        runCatching { file.writeText(json.encodeToString(all)) }
    }

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        for (cookie in cookies) {
            store.computeIfAbsent(cookie.domain) { ConcurrentHashMap() }[cookie.name] = cookie
        }
        persist()
    }

    /**
     * 手动种植 Cookie（B 站 finger/spi 把 buvid3/buvid4 放在 JSON body 而非 Set-Cookie，
     * 需要客户端像网页 JS 一样自行写入）。
     *
     * @param domain 形如 ".bilibili.com" 或 "bilibili.com"
     */
    fun put(
        domain: String,
        name: String,
        value: String,
        maxAgeSeconds: Long,
        secure: Boolean = false,
    ) {
        // OkHttp 的 Cookie.Builder.domain() 不接受带前导点的域（会抛
        // IllegalArgumentException: unexpected domain），而 B 站约定俗成用
        // ".bilibili.com" 表示全子域。这里统一剥点归一化；loadForRequest 的
        // domainMatch 对「带点/不带点」两种键都能正确匹配。
        val base = domain.removePrefix(".")
        val cookie = Cookie.Builder()
            .name(name)
            .value(value)
            .domain(base)
            .path("/")
            .expiresAt(System.currentTimeMillis() + maxAgeSeconds * 1000L)
            .apply { if (secure) secure() }
            .build()
        store.computeIfAbsent(base) { ConcurrentHashMap() }[name] = cookie
        persist()
    }

    /** 清除某域全部 Cookie（源账号退出登录）。 */
    @Synchronized
    fun clearDomain(domain: String) {
        store.remove(domain.removePrefix("."))
        persist()
    }

    /** 某域下是否存在任意未过期 Cookie（判断源账号是否已登录）。 */
    fun hasAny(domain: String): Boolean {
        val now = System.currentTimeMillis()
        return store[domain.removePrefix(".")]?.values?.any { it.expiresAt >= now } == true
    }

    /** 查询某域下是否存在未过期 Cookie（用于判断登录态/指纹是否已就绪）。 */
    fun has(domain: String, name: String): Boolean {
        val c = store[domain.removePrefix(".")]?.get(name) ?: return false
        return c.expiresAt >= System.currentTimeMillis()
    }

    /** 读取某域下未过期 Cookie 的值（如 bili_jct/csrf）；不存在返回 null。 */
    fun value(domain: String, name: String): String? {
        val c = store[domain.removePrefix(".")]?.get(name) ?: return null
        return if (c.expiresAt >= System.currentTimeMillis()) c.value else null
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val now = System.currentTimeMillis()
        val out = ArrayList<Cookie>()
        for ((domain, cookies) in store) {
            if (!domainMatch(url.host, domain)) continue
            for (cookie in cookies.values) {
                if (cookie.expiresAt < now) continue
                if (cookie.secure && url.scheme != "https") continue
                if (url.encodedPath.startsWith(cookie.path)) out.add(cookie)
            }
        }
        return out
    }

    /** OkHttp 的 domain 匹配语义：hostOnly 全等，否则以 `.domain` 为后缀。 */
    private fun domainMatch(host: String, domain: String): Boolean {
        val base = domain.removePrefix(".")
        return host == base || host.endsWith(".$base")
    }
}
