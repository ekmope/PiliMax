package com.pilinara.api

import com.pilinara.net.Http
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * B 站 web 接口封装。所有响应均为 JSON；大会员字段改写在 OkHttp 拦截器层透明完成。
 */
class BiliApi(private val http: Http) {

    val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        coerceInputValues = true
    }

    private var mixinKey: String? = null

    private inline fun <reified T> decode(s: String): ApiResp<T> =
        json.decodeFromString<ApiResp<T>>(s)

    private suspend fun signedGet(
        base: String,
        params: Map<String, String>,
        referer: String? = null,
    ): String {
        val key = ensureWbiKey()
        val query = if (key != null) Wbi.sign(params, key) else encode(params)
        return http.getString("$base?$query", referer = referer)
    }

    private fun encode(params: Map<String, String>): String =
        params.entries.joinToString("&") { (k, v) ->
            "${java.net.URLEncoder.encode(k, "UTF-8")}=${java.net.URLEncoder.encode(v, "UTF-8")}"
        }

    // ---------- WBI 密钥（匿名 nav 也会返回） ----------

    private suspend fun ensureWbiKey(): String? {
        mixinKey?.let { return it }
        runCatching {
            val body = http.getString("https://api.bilibili.com/x/web-interface/nav")
            val root = json.parseToJsonElement(body).jsonObject["data"]?.jsonObject
            val wbi = root?.get("wbi_img")?.jsonObject
            val img = wbi?.get("img_url")?.jsonPrimitive?.content?.substringAfterLast('/')
                ?.substringBefore('.').orEmpty()
            val sub = wbi?.get("sub_url")?.jsonPrimitive?.content?.substringAfterLast('/')
                ?.substringBefore('.').orEmpty()
            if (img.isNotEmpty() && sub.isNotEmpty()) {
                mixinKey = Wbi.mixinKey(img, sub)
            }
        }
        return mixinKey
    }

    /** 用一次 nav 调用同时拿到登录态与 WBI 密钥。 */
    suspend fun nav(): NavInfo {
        val body = http.getString("https://api.bilibili.com/x/web-interface/nav")
        val root = json.parseToJsonElement(body).jsonObject
        root["data"]?.jsonObject?.let { data ->
            val wbi = data["wbi_img"]?.jsonObject
            val img = wbi?.get("img_url")?.jsonPrimitive?.content?.substringAfterLast('/')
                ?.substringBefore('.').orEmpty()
            val sub = wbi?.get("sub_url")?.jsonPrimitive?.content?.substringAfterLast('/')
                ?.substringBefore('.').orEmpty()
            if (img.isNotEmpty() && sub.isNotEmpty()) {
                mixinKey = Wbi.mixinKey(img, sub)
            }
        }
        return decode<NavInfo>(body).data ?: NavInfo()
    }

    // ---------- 扫码登录 ----------

    suspend fun qrGenerate(): QrGenerate {
        val body = http.getString(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/generate",
        )
        return decode<QrGenerate>(body).data ?: error("二维码生成失败")
    }

    /**
     * 轮询扫码结果。
     * @return [QrPoll]；code=0 成功（Cookie 已由 CookieJar 落地），86101 未扫码，
     *         86090 已扫码待确认，86038 二维码过期。
     */
    suspend fun qrPoll(qrcodeKey: String): Pair<Int, QrPoll?> {
        val body = http.getString(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=$qrcodeKey",
        )
        val resp = decode<QrPoll>(body)
        return resp.code to resp.data
    }

    /** seg.so 弹幕需要 buvid3 Cookie，匿名状态先访问指纹接口领取。 */
    suspend fun ensureBuvid() {
        runCatching {
            http.getString("https://api.bilibili.com/x/frontend/finger/spi")
        }
    }

    // ---------- 首页 ----------

    suspend fun popular(pn: Int = 1, ps: Int = 30): List<BiliVideo> {
        val body = http.getString(
            "https://api.bilibili.com/x/web-interface/popular?pn=$pn&ps=$ps",
        )
        return decode<PopularData>(body).data?.list.orEmpty()
    }

    suspend fun recommend(freshIdx: Int = 1): List<BiliVideo> {
        val body = signedGet(
            "https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd",
            mapOf(
                "ps" to "30",
                "fresh_idx" to freshIdx.toString(),
                "fresh_idx_1h" to freshIdx.toString(),
                "feed_version" to "V2",
            ),
        )
        return decode<RcmdData>(body).data?.item.orEmpty()
            .filter { it.goto == "av" || it.bvid.isNotEmpty() }
            .map(RcmdItem::toBiliVideo)
    }

    // ---------- 搜索 ----------

    suspend fun searchVideo(keyword: String, page: Int = 1): List<BiliVideo> {
        val body = signedGet(
            "https://api.bilibili.com/x/web-interface/wbi/search/type",
            mapOf(
                "search_type" to "video",
                "keyword" to keyword,
                "page" to page.toString(),
                "order" to "totalrank",
            ),
            referer = "https://search.bilibili.com",
        )
        return decode<SearchData>(body).data?.result.orEmpty()
            .map(SearchVideo::toBiliVideo)
    }

    // ---------- 详情 / 播放 ----------

    suspend fun view(bvid: String): ViewData {
        val body = http.getString(
            "https://api.bilibili.com/x/web-interface/view?bvid=$bvid",
        )
        val resp = decode<ViewData>(body)
        return resp.data ?: error(resp.errMsg)
    }

    suspend fun history(max: Int = 100): List<HistoryItem> {
        val body = http.getString(
            "https://api.bilibili.com/x/v2/history?max=$max",
            referer = "https://www.bilibili.com",
        )
        return json.decodeFromString<ApiResp<List<HistoryItem>>>(body).data.orEmpty()
    }

    /**
     * 获取播放地址（DASH）。
     * 普通请求遇到「仅大会员」错误码时自动带 try_look=1 重试（试看流由本地 VIP 改写转正）。
     */
    suspend fun playurl(
        bvid: String,
        cid: Long,
        qn: Int = 127,
        forceTryLook: Boolean = false,
    ): PlayUrlData {
        val params = linkedMapOf(
            "bvid" to bvid,
            "cid" to cid.toString(),
            "qn" to qn.toString(),
            "fnval" to "4048",
            "fnver" to "0",
            "fourk" to "1",
            "otype" to "json",
        )
        if (forceTryLook) params["try_look"] = "1"
        val body = signedGet(
            "https://api.bilibili.com/x/player/wbi/playurl",
            params,
            referer = "https://www.bilibili.com/video/$bvid",
        )
        val resp = decode<PlayUrlData>(body)
        val data = resp.data
        if (!forceTryLook && data?.dash == null && resp.code in NEEDS_VIP_CODES) {
            return playurl(bvid, cid, qn, forceTryLook = true)
        }
        return data ?: error(resp.errMsg)
    }

    /** seg.so protobuf 弹幕单段（返回原始二进制）。 */
    suspend fun danmakuSegment(cid: Long, segmentIndex: Int): ByteArray {
        return http.getBytes(
            "https://api.bilibili.com/x/v2/dm/web/seg.so?type=1&oid=$cid&segment_index=$segmentIndex",
            referer = "https://www.bilibili.com",
        )
    }

    /** 旧版 XML 弹幕（后备）。 */
    suspend fun danmakuXml(cid: Long): String =
        http.getString("https://comment.bilibili.com/$cid.xml")

    companion object {
        // -10403: 大会员专享；100: 需要登录/无权限；-10404: 地区限制等。
        private val NEEDS_VIP_CODES = setOf(-10403, 100, -10404)

        /** 协议相对图片地址补全。 */
        fun image(url: String): String =
            if (url.startsWith("//")) "https:$url" else url
    }
}
