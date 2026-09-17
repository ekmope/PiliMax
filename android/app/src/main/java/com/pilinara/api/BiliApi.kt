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
        origin: String? = null,
    ): String {
        val key = ensureWbiKey()
        val query = if (key != null) Wbi.sign(params, key) else encode(params)
        return http.getString("$base?$query", referer = referer, origin = origin)
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

    /**
     * 准备 B 站网页风控所需的设备指纹 Cookie。
     *
     * 逆向实测：finger/spi 把 buvid3/buvid4 放在 **JSON body** 里（不是 Set-Cookie），
     * 真实浏览器由 JS 取出发芽（buvid3 是「激活报告」后的形态，但直接用 spi 的 b_3 即可通过
     * playurl / seg.so 风控）；缺失这些 Cookie 时 wbi/playurl 直接 412。
     * 同时补齐浏览器里常驻的 _uuid / b_nut / b_lsid / buvid_fp，使 Cookie 形态更像真实 Chrome。
     * 幂等：已有有效 buvid3 时直接返回。
     */
    suspend fun ensureBuvid() {
        val jar = http.cookieJar
        if (jar.has(BILI_DOMAIN, "buvid3")) return
        runCatching {
            val body = http.getString("https://api.bilibili.com/x/frontend/finger/spi")
            val data = json.parseToJsonElement(body).jsonObject["data"]?.jsonObject ?: return@runCatching
            val b3 = data["b_3"]?.jsonPrimitive?.content.orEmpty()
            val b4 = data["b_4"]?.jsonPrimitive?.content.orEmpty()
            val now = System.currentTimeMillis()
            if (b3.isNotEmpty()) {
                jar.put(BILI_DOMAIN, "buvid3", b3, ONE_YEAR_SECS)
                jar.put(BILI_DOMAIN, "buvid4", b4.ifEmpty { b3 }, ONE_YEAR_SECS)
                jar.put(BILI_DOMAIN, "buvid_fp", java.util.UUID.randomUUID()
                    .toString().replace("-", "").take(32), ONE_YEAR_SECS)
                jar.put(BILI_DOMAIN, "_uuid", "${java.util.UUID.randomUUID()}infoc", ONE_YEAR_SECS)
                jar.put(BILI_DOMAIN, "b_nut", (now / 1000).toString(), ONE_YEAR_SECS)
                jar.put(
                    BILI_DOMAIN,
                    "b_lsid",
                    "${randomHex(8).uppercase()}_${java.lang.Long.toHexString(now / 1000).uppercase()}",
                    ONE_YEAR_SECS,
                )
            }
        }
    }

    private fun randomHex(len: Int): String {
        val alphabet = "0123456789abcdef"
        val sb = StringBuilder(len)
        repeat(len) { sb.append(alphabet.random()) }
        return sb.toString()
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
        ensureBuvid()
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
            // 视频搜索结果里会混入直播/用户/广告卡片，它们没有 bvid，直接剔除。
            .filter { it.bvid.isNotEmpty() && it.aid > 0 }
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
     * 获取播放地址。
     *
     * 逆向结论（2026-09 实测，Windows Chrome 伪装 + buvid 指纹）：
     * 1. 旧版 [/x/player/playurl] 比 wbi 端点风控宽松：不签名也稳定 200，携带 buvid3 时
     *    返回完整 DASH（音视频分离），是首选；
     * 2. wbi 端点缺指纹 Cookie 时直接 HTTP 412，仅留给「大会员专享」的 try_look 试看场景；
     * 3. 匿名 web DASH 上限 480P；而 platform=html5 给的是合流 MP4、匿名可取 720P，
     *    未登录时作为后备（登录后 DASH 清晰度更高，不走该后备）。
     *
     * 大会员错误码自动带 try_look=1 走 wbi 重试（试看标记由本地 VIP 拦截器清除）。
     */
    suspend fun playurl(
        bvid: String,
        cid: Long,
        qn: Int = 127,
        forceTryLook: Boolean = false,
    ): PlayUrlData {
        ensureBuvid()
        val referer = "https://www.bilibili.com/video/$bvid"
        val params = linkedMapOf(
            "bvid" to bvid,
            "cid" to cid.toString(),
            "qn" to qn.toString(),
            "fnval" to "4048",
            "fnver" to "0",
            "fourk" to "1",
            "otype" to "json",
        )

        // ① 大会员专享：wbi + try_look（试看流由 VipTrialInterceptor 本地转正）。
        if (forceTryLook) {
            params["try_look"] = "1"
            val body = signedGet(
                "https://api.bilibili.com/x/player/wbi/playurl",
                params,
                referer = referer,
                origin = "https://www.bilibili.com",
            )
            val resp = decode<PlayUrlData>(body)
            return resp.data ?: error(resp.errMsg)
        }

        // ② 首选：旧版端点 DASH（带桌面浏览器 Referer/Origin + 指纹 Cookie）。
        var body = http.getString(
            "https://api.bilibili.com/x/player/playurl?${encode(params)}",
            referer = referer,
            origin = "https://www.bilibili.com",
        )
        var resp = decode<PlayUrlData>(body)
        var data = resp.data

        // ③ 权限错误：转 wbi try_look。
        if (data?.dash == null && resp.code in NEEDS_VIP_CODES) {
            return playurl(bvid, cid, qn, forceTryLook = true)
        }
        if (data == null) error(resp.errMsg)

        // ④ 匿名且 DASH 最高只有 480P 时，尝试 html5 合流 720P MP4（登录用户清晰度更高，跳过）。
        val loggedIn = http.cookieJar.has(BILI_DOMAIN, "SESSDATA")
        val dashMaxQn = data.dash?.video?.maxOfOrNull { it.id } ?: 0
        if (!loggedIn && data.durl.isEmpty() && dashMaxQn in 1..<64) {
            val html5 = params + mapOf("platform" to "html5", "high_quality" to "1")
            runCatching {
                val hb = http.getString(
                    "https://api.bilibili.com/x/player/playurl?${encode(html5)}",
                    referer = referer,
                    origin = "https://www.bilibili.com",
                )
                val hd = decode<PlayUrlData>(hb).data
                if (hd != null && hd.durl.isNotEmpty() && hd.quality >= 64 && hd.quality > dashMaxQn) {
                    return hd
                }
            }
        }
        return data
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
        private const val BILI_DOMAIN = ".bilibili.com"
        private const val ONE_YEAR_SECS = 365L * 24 * 3600

        // -10403: 大会员专享；100: 需要登录/无权限；-10404: 地区限制等。
        private val NEEDS_VIP_CODES = setOf(-10403, 100, -10404)

        /** 协议相对图片地址补全。 */
        fun image(url: String): String =
            if (url.startsWith("//")) "https:$url" else url
    }
}
