package com.pilinara.player

import com.pilinara.api.BiliApi
import com.pilinara.api.PlayUrlData
import com.pilinara.api.Track
import com.pilinara.data.SettingsStore

/** B 站清晰度档位（设置页与 playurl 共用）。 */
data class Quality(val qn: Int, val label: String) {
    companion object {
        val PRESETS = listOf(
            Quality(127, "8K 超高清"),
            Quality(125, "HDR 真彩"),
            Quality(120, "4K 超清"),
            Quality(112, "1080P60 高帧率"),
            Quality(80, "1080P 高清"),
            Quality(64, "720P"),
            Quality(32, "480P"),
            Quality(16, "360P"),
        )
    }
}

/**
 * CDN 节点偏好。B 站 playurl 返回一个 baseUrl + 若干 backupUrl，分别指向
 * 阿里/华为/腾讯等镜像域名；这里按域名关键字挑选，「自动」使用服务端下发的 baseUrl。
 */
enum class CdnNode(val id: String, val label: String, private val hostKeyword: String?) {
    AUTO("auto", "自动（服务端分配）", null),
    ALI("ali", "阿里云", "mirrorali"),
    HUAWEI("hw", "华为云", "mirrorhw"),
    TENCENT("cos", "腾讯云 COS", "mirrorcos"),
    AKAMAI("akamai", "Akamai", "mirroraka"),
    ;

    fun pick(baseUrl: String, backups: List<String>): String {
        if (hostKeyword == null) return baseUrl
        return backups.firstOrNull { it.contains(hostKeyword, ignoreCase = true) }
            ?: (backups + baseUrl).firstOrNull { it.contains(hostKeyword, ignoreCase = true) }
            ?: baseUrl
    }

    companion object {
        fun of(id: String?): CdnNode = entries.firstOrNull { it.id == id } ?: AUTO
    }
}

/**
 * 拉取播放地址并映射成播放器请求：
 * - DASH：选最高可用视频轨与最高音质音轨（双轨合流由 PiliMediaSourceFactory 完成）；
 * - durl：旧版分段流直接播；
 * - CDN 偏好 / 默认清晰度均来自 [SettingsStore]。
 */
suspend fun buildBiliPlayRequest(
    api: BiliApi,
    bvid: String,
    cid: Long,
    title: String,
    qn: Int,
    cdnNodeId: String,
): PlayRequest {
    val data = api.playurl(bvid, cid, qn = qn)
    val node = CdnNode.of(cdnNodeId)
    val headers = mapOf(
        "Referer" to "https://www.bilibili.com/video/$bvid",
        "User-Agent" to com.pilinara.net.Http.UA_WEB,
    )
    return mapPlayData(data, title, cid, headers, node)
}

fun mapPlayData(
    data: PlayUrlData,
    title: String,
    cid: Long,
    headers: Map<String, String>,
    node: CdnNode,
): PlayRequest {
    data.dash?.let { dash ->
        val video = dash.video
            .sortedWith(compareByDescending<Track> { it.height }.thenByDescending { it.bandwidth })
            .firstOrNull()
            ?: error("播放地址中没有视频轨")
        val audio = dash.audio.maxByOrNull { it.bandwidth }
        return PlayRequest(
            title = title,
            videoUrl = node.pick(video.baseUrl, video.backupUrl),
            audioUrl = audio?.let { node.pick(it.baseUrl, it.backupUrl) },
            streamType = "progressive",
            cid = cid,
            headers = headers,
        )
    }
    val first = data.durl.firstOrNull() ?: error("播放地址为空")
    val url = node.pick(first.url, first.backupUrl)
    val type = when {
        url.contains(".m3u8", ignoreCase = true) -> "hls"
        url.contains(".mpd", ignoreCase = true) -> "dash"
        else -> "progressive"
    }
    return PlayRequest(
        title = title,
        videoUrl = url,
        streamType = type,
        cid = cid,
        headers = headers,
    )
}
