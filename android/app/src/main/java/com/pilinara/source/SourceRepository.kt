package com.pilinara.source

import com.pilinara.core.NativeCore
import com.pilinara.net.Http
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI

/**
 * 第三方源的搜索 / 详情 / 播放解析。
 *
 * 搜索：所有启用源并发查询（animeko 式多源聚合）；
 * 播放：选择器 matchVideo → kazumi 子集嗅探 → 嵌套页二级嗅探。
 */
class SourceRepository(
    private val http: Http,
    private val manager: SourceManager,
) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    /** 单个源的最长等待：死链/反爬源不应让整页聚合一直转圈。 */
    private val perSourceTimeoutMs = 12_000L

    /**
     * 并发聚合搜索，结果**流式**回调：
     * - [onPartial]：每有一个源出结果就回传一次（UI 增量渲染，最快 1~2 秒出首批）；
     * - 返回值：全部完成后各源结果合计。
     * 单个源失败/超时不影响其他源，解决「几个慢站卡住整页」的体验问题。
     */
    suspend fun aggregateSearchStreaming(
        keyword: String,
        onPartial: suspend (List<SourceSearchResult>) -> Unit,
    ): List<SourceSearchResult> = coroutineScope {
        val instances = manager.enabledInstanceJsonList()
        val deferred = instances.map { instanceJson ->
            async {
                runCatching {
                    withTimeout(perSourceTimeoutMs) { searchOne(instanceJson, keyword) }
                }.getOrDefault(emptyList())
            }
        }
        // 各源独立完成即推送，UI 增量刷新。
        deferred.forEach { d ->
            val part = d.await()
            if (part.isNotEmpty()) onPartial(part)
        }
        deferred.awaitAll().flatten()
    }

    /** 兼容旧调用：一次性等待全部源完成后返回。 */
    suspend fun aggregateSearch(keyword: String): List<SourceSearchResult> {
        var all: List<SourceSearchResult> = emptyList()
        aggregateSearchStreaming(keyword) { partial -> all = all + partial }
        return all
    }

    /** 单源搜索：构造 URL → 抓取（自动识别 GBK/UTF-8）→ Rust 核心解析。 */
    private suspend fun searchOne(instanceJson: String, keyword: String): List<SourceSearchResult> {
        val searchUrl = NativeCore.buildSearchUrl(instanceJson, keyword)
        // 第三方页面编码混杂（GBK/GB2312/UTF-8），统一走 HTML 编码探测。
        val html = http.getHtml(searchUrl, referer = baseOf(searchUrl))
        val out = NativeCore.parseSubjectList(instanceJson, html, searchUrl)
        val subjects = json.decodeFromString(
            ListSerializer(SourceSubject.serializer()),
            out,
        )
        val sourceName = sourceNameOf(instanceJson)
        return subjects.map { SourceSearchResult(sourceName, it) }
    }

    /** 拉取条目详情页的全部线路。 */
    suspend fun channels(instanceJson: String, subjectUrl: String): List<SourceChannel> {
        val html = http.getHtml(subjectUrl, referer = baseOf(subjectUrl))
        val out = NativeCore.parseChannels(instanceJson, html, subjectUrl)
        return json.decodeFromString(ListSerializer(SourceChannel.serializer()), out)
    }

    /**
     * 解析某一集的可播放地址：
     * 1) 选择器 matchVideo；
     * 2) 内置/自定义正则嗅探；
     * 3) iframe/跳转等嵌套页再抓一次后嗅探。
     */
    suspend fun resolve(instanceJson: String, pageUrl: String): ResolvedVideo {
        val headers = videoHeaders(instanceJson)
        val html = http.getHtml(pageUrl, headers = headers, referer = baseOf(pageUrl))

        val direct = NativeCore.matchVideo(instanceJson, html)
        val sniffConfig = sniffConfigOf(instanceJson)
        var found: String? = parseNullable(direct) ?: parseNullable(
            NativeCore.sniffVideo(html, sniffConfig),
        )

        if (found == null) {
            val nested = parseNullable(NativeCore.sniffNested(html, sniffConfig))
            if (nested != null) {
                val nestedUrl = resolveUrl(pageUrl, nested)
                val nestedHtml = http.getHtml(
                    nestedUrl,
                    headers = headers,
                    referer = baseOf(nestedUrl),
                )
                found = parseNullable(NativeCore.sniffVideo(nestedHtml, sniffConfig))
                    ?.let { resolveUrl(nestedUrl, it) }
            }
        }

        val url = found?.let { resolveUrl(pageUrl, it) }
            ?: error("未能解析出视频地址（源未返回可识别的直链）")

        return ResolvedVideo(
            url = url,
            headers = headers + mapOf(
                "Referer" to baseOf(pageUrl),
                "Origin" to originOf(pageUrl),
            ),
        )
    }

    private fun videoHeaders(instanceJson: String): Map<String, String> =
        runCatching {
            json.decodeFromString(
                kotlinx.serialization.builtins.MapSerializer(
                    kotlinx.serialization.serializer<String>(),
                    kotlinx.serialization.serializer<String>(),
                ),
                NativeCore.videoHeaders(instanceJson),
            )
        }.getOrDefault(emptyMap())

    /**
     * 取实例 arguments 中的嗅探配置（animeko web-selector 允许内嵌 `searchConfig`/
     * 自定义 sniffer 字段）；没有就传 null 走核心内置规则。
     */
    private fun sniffConfigOf(instanceJson: String): String {
        return runCatching {
            val args: JsonObject? = json.parseToJsonElement(instanceJson)
                .jsonObject["arguments"]?.jsonObject
            val sniffer = args?.get("sniffer") ?: args?.get("snifferConfig")
            sniffer?.toString() ?: "null"
        }.getOrDefault("null")
    }

    private fun sourceNameOf(instanceJson: String): String = runCatching {
        json.parseToJsonElement(instanceJson).jsonObject["arguments"]
            ?.jsonObject?.get("name")?.jsonPrimitive?.content
    }.getOrNull().orEmpty().ifEmpty { "未知源" }

    private fun parseNullable(s: String): String? =
        s.takeIf { it.isNotBlank() && it != "null" }

    private fun resolveUrl(base: String, link: String): String =
        runCatching { URI(base).resolve(link).toString() }.getOrDefault(link)

    private fun baseOf(url: String): String = runCatching {
        val u = URI(url)
        "${u.scheme}://${u.host}${if (u.port > 0) ":${u.port}" else ""}/"
    }.getOrDefault("https://www.bilibili.com/")

    private fun originOf(url: String): String = runCatching {
        val u = URI(url)
        "${u.scheme}://${u.host}${if (u.port > 0) ":${u.port}" else ""}"
    }.getOrDefault("https://www.bilibili.com")
}
