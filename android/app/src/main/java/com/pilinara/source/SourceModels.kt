package com.pilinara.source

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/** 源订阅（一个 URL = 一份 animeko 兼容清单）。 */
@Serializable
data class SourceSubscription(
    val id: String,
    val name: String,
    val url: String,
    val addedAt: Long,
    val enabled: Boolean = true,
    val sourceCount: Int = 0,
    val lastUpdatedAt: Long = 0,
    val lastError: String? = null,
)

/** 内置订阅预设（assets/sources/presets.json）。 */
@Serializable
data class SourcePreset(
    val name: String,
    val description: String = "",
    val url: String,
)

@Serializable
data class SourcePresets(val presets: List<SourcePreset> = emptyList())

/** 源实例的 UI 视图（从 Rust 侧 JSON 中读必要字段）。 */
data class SourceInstanceView(
    val instanceId: String,
    val factoryId: String,
    val name: String,
    val description: String,
    val iconUrl: String?,
    val subscriptionId: String?,
    val enabled: Boolean,
    val sortOrder: Int,
    val raw: JsonObject,
)

/** 聚合搜索结果条目。 */
@Serializable
data class SourceSubject(
    val name: String,
    val url: String,
)

/** 聚合搜索结果（带来源名）。 */
data class SourceSearchResult(
    val sourceName: String,
    val subject: SourceSubject,
)

@Serializable
data class SourceEpisode(
    val name: String = "",
    val sort: String = "",
    val pageUrl: String = "",
)

@Serializable
data class SourceChannel(
    val name: String = "",
    val tier: Long = 0,
    val episodes: List<SourceEpisode> = emptyList(),
)

/** 嗅探/选择器解析出的可播放结果。 */
data class ResolvedVideo(
    val url: String,
    val headers: Map<String, String>,
)

/** 本地追番：订阅源里的番剧追番记录；biliSeasonId>0 表示已同步到 B 站追番。 */
@Serializable
data class FollowedSubject(
    val name: String,
    val subjectUrl: String,
    val sourceName: String,
    val followedAt: Long,
    val biliSeasonId: Long = 0,
)
