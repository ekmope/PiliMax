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
    roamingServer: String = "",
    hiResAudio: Boolean = false,
): PlayRequest {
    val data = api.playurl(
        bvid = bvid,
        cid = cid,
        qn = qn,
        roamingServer = roamingServer.ifBlank { null },
    )
    val node = CdnNode.of(cdnNodeId)
    val headers = mapOf(
        "Referer" to "https://www.bilibili.com/video/$bvid",
        "User-Agent" to com.pilinara.net.Http.UA_WEB,
    )
    return mapPlayData(data, title, cid, headers, node, qn, hiResAudio)
}

fun mapPlayData(
    data: PlayUrlData,
    title: String,
    cid: Long,
    headers: Map<String, String>,
    node: CdnNode,
    preferQn: Int,
    hiResAudio: Boolean = false,
): PlayRequest {
    data.dash?.let { dash ->
        val video = pickVideoTrack(dash.video, preferQn) ?: error("播放地址中没有视频轨")
        // 默认普通 AAC；开启高解析度后依次尝试 Hi-Res FLAC、杜比全景声。
        val audio = if (hiResAudio) {
            dash.flac?.flac ?: dash.dolby?.audio ?: pickAudioTrack(dash)
        } else {
            pickAudioTrack(dash)
        }
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

/**
 * 选择视频轨：
 * 1. 不超过用户设置的清晰度上限 [preferQn]；
 * 2. 同清晰度下优先 AV1 → HEVC → AVC（骁龙 8 至尊版均有硬解，AV1/HEVC 压缩率高更省电省流）；
 * 3. 编码相同时取高码率。
 */
private fun pickVideoTrack(tracks: List<Track>, preferQn: Int): Track? {
    if (tracks.isEmpty()) return null
    val available = tracks.filter { it.id <= preferQn }.ifEmpty { tracks }
    val targetQn = available.maxOf { it.id }
    return available.filter { it.id == targetQn }
        .sortedWith(
            compareByDescending<Track> { codecRank(it.codecs) }
                .thenByDescending { it.bandwidth },
        )
        .first()
}

private fun codecRank(codecs: String): Int = when {
    codecs.startsWith("av01", ignoreCase = true) -> 3
    codecs.startsWith("hvc1", ignoreCase = true) ||
        codecs.startsWith("hev1", ignoreCase = true) -> 2
    else -> 1
}

private val AAC_AUDIO_IDS = setOf(30250, 30280, 30232, 30216)

/**
 * 选择音轨：
 * 1. 普通 AAC 音轨里取最高码率（兼容性最好，Media3 原生解码、低功耗）；
 * 2. 没有可识别 AAC 时退回最高码率轨；
 * 3. Hi-Res FLAC / 杜比全景声需要用户显式开启（见设置页），默认不选——杜比在无对应
 *    解码器的设备上会无声。
 */
fun pickAudioTrack(dash: com.pilinara.api.Dash): Track? =
    dash.audio.filter { it.id in AAC_AUDIO_IDS }.maxByOrNull { it.bandwidth }
        ?: dash.audio.maxByOrNull { it.bandwidth }
