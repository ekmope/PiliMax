package com.pilinara.player

/**
 * Media3 1.11 的 MediaItem 不再支持逐条请求头；改为「URL → 请求头」表，
 * 由 PlaybackService 中的 ResolvingDataSource 在打开连接时按 URI 注入
 * （B 站防盗链 Referer、第三方源自定义头都走这里）。
 */
object PlaybackHeaderStore {

    @Volatile
    private var headersByUrl: Map<String, Map<String, String>> = emptyMap()

    fun set(urls: Collection<String>, headers: Map<String, String>) {
        headersByUrl = urls.filter { it.isNotEmpty() }.associateWith { headers }
    }

    fun forUri(uri: String): Map<String, String>? = headersByUrl[uri]

    fun clear() {
        headersByUrl = emptyMap()
    }
}
