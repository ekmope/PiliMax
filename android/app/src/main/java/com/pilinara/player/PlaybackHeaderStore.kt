package com.pilinara.player

import java.net.URI

/**
 * Media3 1.11 的 MediaItem 不再支持逐条请求头；改为「URL → 请求头」表，
 * 由 PlaybackService 中的 ResolvingDataSource 在打开连接时按 URI 注入
 * （B 站防盗链 Referer、第三方源自定义头都走这里）。
 *
 * 匹配顺序：URL 精确匹配 → 注册域名（最后两段，如 bilivideo.com）兜底。
 * 兜底是必要的：playurl 下发的 baseUrl 常 302 跳到另一个 CDN 节点域名
 * （cn-sh-cc → upos-sz-mirrorcos），防盗链头必须在跳转后的请求上仍然带着。
 */
object PlaybackHeaderStore {

    @Volatile
    private var headersByUrl: Map<String, Map<String, String>> = emptyMap()

    fun set(urls: Collection<String>, headers: Map<String, String>) {
        headersByUrl = urls.filter { it.isNotEmpty() }.associateWith { headers }
    }

    fun forUri(uri: String): Map<String, String>? {
        headersByUrl[uri]?.let { return it }
        val targetDomain = registrableDomain(uri) ?: return null
        return headersByUrl.entries.firstOrNull { (key, _) ->
            registrableDomain(key) == targetDomain
        }?.value
    }

    /** 取 host 最后两段作为「注册域名」近似：cn-sh-cc-01-03.bilivideo.com → bilivideo.com。 */
    private fun registrableDomain(url: String): String? =
        runCatching {
            val parts = URI(url).host?.split('.') ?: return@runCatching null
            if (parts.size < 2) null else parts.takeLast(2).joinToString(".")
        }.getOrNull()

    fun clear() {
        headersByUrl = emptyMap()
    }
}
