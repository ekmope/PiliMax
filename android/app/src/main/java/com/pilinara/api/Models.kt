package com.pilinara.api

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.longOrNull

/**
 * 宽松的 Long 解析：B 站不同接口/灰度下同一字段可能是数字、数字字符串、空串甚至布尔，
 * 统一吞掉异常形态，避免单个脏字段导致整页解析失败。
 */
object FlexLong : KSerializer<Long> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.pilinara.FlexLong", PrimitiveKind.LONG)

    override fun deserialize(decoder: Decoder): Long {
        val jd = decoder as? JsonDecoder ?: return decoder.decodeLong()
        return when (val el = jd.decodeJsonElement()) {
            is JsonNull -> 0L
            is JsonPrimitive -> when {
                el.isString -> el.content.trim().toLongOrNull() ?: 0L
                else -> el.longOrNull ?: el.booleanOrNull?.let { if (it) 1L else 0L } ?: 0L
            }
            else -> 0L
        }
    }

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: Long) =
        encoder.encodeLong(value)
}

/** 宽松 Int，语义同 [FlexLong]。 */
object FlexInt : KSerializer<Int> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.pilinara.FlexInt", PrimitiveKind.INT)

    override fun deserialize(decoder: Decoder): Int {
        val jd = decoder as? JsonDecoder ?: return decoder.decodeInt()
        return when (val el = jd.decodeJsonElement()) {
            is JsonNull -> 0
            is JsonPrimitive -> when {
                el.isString -> el.content.trim().toIntOrNull() ?: 0
                else -> el.longOrNull?.toInt() ?: el.booleanOrNull?.let { if (it) 1 else 0 } ?: 0
            }
            else -> 0
        }
    }

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: Int) =
        encoder.encodeInt(value)
}

@Serializable
data class ApiResp<T>(
    val code: Int = -1,
    val message: String? = null,
    @Suppress("PropertyName")
    val msg: String? = null,
    val data: T? = null,
) {
    val errMsg: String get() = message ?: msg ?: "未知错误 ($code)"
}

// ---------- 登录 ----------

@Serializable
data class QrGenerate(
    val url: String = "",
    @SerialName("qrcode_key") val qrcodeKey: String = "",
)

@Serializable
data class QrPoll(
    val url: String? = null,
    val refresh_token: String? = null,
    val timestamp: Long = 0,
)

@Serializable
data class NavInfo(
    val isLogin: Boolean = false,
    val mid: Long = 0,
    val uname: String = "",
    val face: String = "",
    val vipStatus: Int = 0,
    val vipType: Int = 0,
)

@Serializable
data class NavWbi(
    val wbi_img: WbiImg = WbiImg(),
)

@Serializable
data class WbiImg(
    @SerialName("img_url") val imgUrl: String = "",
    @SerialName("sub_url") val subUrl: String = "",
)

// ---------- 视频卡片 ----------

@Serializable
data class BiliOwner(
    val mid: Long = 0,
    val name: String = "",
    val face: String = "",
)

@Serializable
data class BiliStat(
    val view: Long = 0,
    val danmaku: Long = 0,
    val reply: Long = 0,
    val favorite: Long = 0,
    val coin: Long = 0,
    val share: Long = 0,
    val like: Long = 0,
)

/** 统一的视频卡片（热门/推荐/搜索/详情都映射到它）。 */
@Serializable
data class BiliVideo(
    val aid: Long = 0,
    val bvid: String = "",
    val cid: Long = 0,
    val title: String = "",
    val pic: String = "",
    val desc: String = "",
    val duration: Long = 0,
    val pubdate: Long = 0,
    val tname: String = "",
    val goto: String = "",
    val owner: BiliOwner = BiliOwner(),
    val stat: BiliStat = BiliStat(),
)

@Serializable
data class PopularData(val list: List<BiliVideo> = emptyList(), val noMore: Boolean = false)

@Serializable
data class RcmdData(val item: List<RcmdItem> = emptyList())

/** 推荐流字段与热门流略有差异（cover / param），单独接收后再归一化。 */
@Serializable
data class RcmdItem(
    val id: Long = 0,
    val bvid: String = "",
    val title: String = "",
    val pic: String = "",
    val cover: String = "",
    val duration: Long = 0,
    val pubdate: Long = 0,
    val tname: String? = null,
    val desc: String? = null,
    val goto: String? = null,
    val owner: BiliOwner? = null,
    val stat: BiliStat? = null,
) {
    fun toBiliVideo(): BiliVideo = BiliVideo(
        aid = id,
        bvid = bvid,
        title = title,
        pic = pic.ifEmpty { cover },
        desc = desc.orEmpty(),
        duration = duration,
        pubdate = pubdate,
        tname = tname.orEmpty(),
        goto = goto.orEmpty(),
        owner = owner ?: BiliOwner(),
        stat = stat ?: BiliStat(),
    )
}

@Serializable
data class SearchData(
    val numResults: Int = 0,
    val result: List<SearchVideo> = emptyList(),
)

@Serializable
data class SearchVideo(
    val bvid: String = "",
    @Serializable(with = FlexLong::class) val aid: Long = 0,
    @Serializable(with = FlexLong::class) val typeid: Long = 0,
    val title: String = "",
    val pic: String = "",
    val author: String = "",
    @Serializable(with = FlexLong::class) val mid: Long = 0,
    // 注意：web 搜索接口 play/review 等均为 JSON 数字（如 "play":851779），旧接口可能给字符串。
    @Serializable(with = FlexLong::class) val play: Long = 0,
    @Serializable(with = FlexLong::class) val review: Long = 0,
    @Serializable(with = FlexLong::class) val video_review: Long = 0,
    val tag: String = "",
    val duration: String = "",
) {
    fun toBiliVideo(): BiliVideo = BiliVideo(
        aid = aid,
        bvid = bvid,
        title = EM_TAG.replace(title, ""),
        pic = BiliApi.image(pic),
        duration = parseDuration(duration),
        tname = tag,
        owner = BiliOwner(mid = mid, name = author),
        stat = BiliStat(
            view = play,
            danmaku = if (review > 0) review else video_review,
        ),
    )

    companion object {
        private val EM_TAG = Regex("</?em[^>]*>")

        fun parseDuration(s: String): Long {
            if (s.isEmpty()) return 0
            var secs = 0L
            for (p in s.split(':')) {
                val n = p.toLongOrNull() ?: return 0
                secs = secs * 60 + n
            }
            return secs
        }
    }
}

// ---------- 视频详情 ----------

@Serializable
data class ViewData(
    val aid: Long = 0,
    val bvid: String = "",
    val cid: Long = 0,
    val title: String = "",
    val desc: String = "",
    val pic: String = "",
    val duration: Long = 0,
    val pubdate: Long = 0,
    val tname: String = "",
    val owner: BiliOwner = BiliOwner(),
    val stat: BiliStat = BiliStat(),
    val pages: List<VideoPage> = emptyList(),
)

@Serializable
data class VideoPage(
    val cid: Long = 0,
    val page: Int = 0,
    val part: String = "",
)

// ---------- 历史 ----------

@Serializable
data class HistoryInner(
    val oid: Long = 0,
    val cid: Long = 0,
    val viewAt: Long = 0,
    val progress: Long = 0,
)

@Serializable
data class HistoryItem(
    val aid: Long = 0,
    val bvid: String = "",
    val title: String = "",
    val pic: String = "",
    val duration: Long = 0,
    val tname: String? = null,
    val owner: BiliOwner? = null,
    val history: HistoryInner? = null,
)

// ---------- playurl ----------

@Serializable
data class PlayUrlData(
    @Serializable(with = FlexInt::class) val quality: Int = 0,
    // playurl 的 format 是字符串（如 "flv_p64"、"hdmp4"、DASH 下为 ""），不是数字。
    val format: String = "",
    @Serializable(with = FlexLong::class) val timelength: Long = 0,
    val trial: Boolean = false,
    val dash: Dash? = null,
    val durl: List<Durl> = emptyList(),
)

@Serializable
data class Dash(
    @Serializable(with = FlexLong::class) val duration: Long = 0,
    val video: List<Track> = emptyList(),
    val audio: List<Track> = emptyList(),
    // 杜比全景声轨：{"audio": Track 或 null}，结构一致，单独接收。
    val dolby: Dolby? = null,
)

@Serializable
data class Dolby(val audio: List<Track> = emptyList())

@Serializable
data class Track(
    @Serializable(with = FlexInt::class) val id: Int = 0,
    @SerialName("baseUrl") val baseUrl: String = "",
    @SerialName("backupUrl") val backupUrl: List<String> = emptyList(),
    @Serializable(with = FlexInt::class) val bandwidth: Int = 0,
    @SerialName("mimeType") val mimeType: String = "",
    val codecs: String = "",
    @Serializable(with = FlexInt::class) val width: Int = 0,
    @Serializable(with = FlexInt::class) val height: Int = 0,
    @SerialName("frameRate") val frameRate: String = "",
)

@Serializable
data class Durl(
    @Serializable(with = FlexInt::class) val order: Int = 0,
    @Serializable(with = FlexLong::class) val length: Long = 0,
    @Serializable(with = FlexLong::class) val size: Long = 0,
    val url: String = "",
    // durl 用蛇形命名（dash track 才是驼峰）。
    @SerialName("backup_url") val backupUrl: List<String> = emptyList(),
)
