package com.pilinara.api

import com.pilinara.net.Http
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl

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

    /** 非 {code,data} 包装的裸响应（如 SponsorBlock）。 */
    private inline fun <reified T> decodeRaw(s: String): T =
        json.decodeFromString<T>(s)

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
            var b3 = ""
            var b4 = ""
            runCatching {
                val body = http.getString("https://api.bilibili.com/x/frontend/finger/spi")
                val data = json.parseToJsonElement(body).jsonObject["data"]?.jsonObject
                    ?: return@runCatching
                b3 = data["b_3"]?.jsonPrimitive?.content.orEmpty()
                b4 = data["b_4"]?.jsonPrimitive?.content.orEmpty()
            }
            // spi 失败时本地生成一个合法格式的 buvid3（BV 方案：UUID + 随机数字 + infoc），
            // 保证任何网络状况下请求都带指纹，降低 412 概率。
            if (b3.isEmpty()) {
                b3 = "${java.util.UUID.randomUUID()}${(10000..99999).random()}infoc"
            }
            val now = System.currentTimeMillis()
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
        // 说明：buvid3/buvid4 等 Cookie 是规避 412 的核心。部分项目（bilipai）还会额外调
        // ExClimbWuzhi 做「激活上报」，但其请求体字段是加密指纹、无法可靠复现，编造字段
        // 反而可能被标记为可疑设备，故此处不做该上报，仅保证 Cookie 形态完整。
        // 整个指纹准备对调用方「永不抛异常」：宁可无指纹降级，也不能阻断播放/搜索。
    }

    private fun randomHex(len: Int): String {
        val alphabet = "0123456789abcdef"
        val sb = StringBuilder(len)
        repeat(len) { sb.append(alphabet.random()) }
        return sb.toString()
    }

    // ---------- 首页 ----------

    suspend fun popular(pn: Int = 1, ps: Int = 30): List<BiliVideo> {
        ensureBuvid()
        val body = http.getString(
            "https://api.bilibili.com/x/web-interface/popular?pn=$pn&ps=$ps",
        )
        // 热门流偶尔混入专栏/广告卡（没有 bvid），点了只会 -404，直接过滤。
        return decode<PopularData>(body).data?.list.orEmpty()
            .filter { it.bvid.isNotEmpty() }
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
        // 详情页是用户最常触发的第一个请求：预热未完成时若不带 buvid 指纹，
        // 会直接 412（表现为「详情加载失败：风控」）。ensureBuvid 幂等且永不抛异常。
        ensureBuvid()
        val body = http.getString(
            "https://api.bilibili.com/x/web-interface/view?bvid=$bvid",
            referer = "https://www.bilibili.com",
        )
        val resp = decode<ViewData>(body)
        return resp.data ?: error(resp.errMsg)
    }

    /**
     * 评论主楼列表（官方公开接口，游客可用；bilipai 同端点）。
     * @param mode 3 按时间倒序 / 2 按热度。
     * @param next 翻页游标，首次传 0。
     */
    suspend fun replies(aid: Long, mode: Int = 3, next: Long = 0): ReplyMainData {
        ensureBuvid()
        val body = signedGet(
            "https://api.bilibili.com/x/v2/reply/wbi/main",
            mapOf(
                "oid" to aid.toString(),
                "type" to "1",
                "mode" to mode.toString(),
                "next" to next.toString(),
                "ps" to "20",
            ),
            referer = "https://www.bilibili.com",
        )
        return decode<ReplyMainData>(body).data ?: ReplyMainData()
    }

    /** 相关推荐（view/detail/related，游客可用；失败返回空列表不阻断详情）。 */
    suspend fun related(aid: Long): List<BiliVideo> = try {
        val body = signedGet(
            "https://api.bilibili.com/x/web-interface/view/detail/related",
            mapOf("aid" to aid.toString()),
            referer = "https://www.bilibili.com",
        )
        decode<List<BiliVideo>>(body).data.orEmpty()
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * 空降片段（BilibiliSponsorBlock 公开社区 API，bilipai 同源）。
     * 用于跳过片头广告/恰饭等社区标注片段；404/失败返回空列表。
     *
     * @param categories 启用的分类（sponsor/paid_promotion/intro/outro/…），
     *   空集合时回退默认（sponsor + poi_highlight）。
     */
    suspend fun sponsorSegments(
        bvid: String,
        cid: Long,
        categories: Collection<String> = emptyList(),
    ): List<SponsorSegment> = try {
        val cats = categories.ifEmpty { listOf("sponsor", "poi_highlight") }
        val body = http.getString(
            "https://bsbsb.top/api/skipSegments?videoID=$bvid&cid=$cid" +
                cats.joinToString("") { "&category=$it" },
        )
        decodeRaw<List<SponsorSegment>>(body)
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * B 站追番列表（登录态；游客返回空）。用于「订阅源追番同步到 B 站」的匹配。
     */
    suspend fun myBangumiFollow(page: Int = 1): List<BangumiFollowItem> = try {
        val body = signedGet(
            "https://api.bilibili.com/x/space/bangumi/follow/list",
            mapOf("vmid" to myMid().toString(), "pn" to page.toString(), "ps" to "30"),
            referer = "https://space.bilibili.com",
        )
        json.decodeFromString<ApiResp<BangumiFollowData>>(body).data?.list.orEmpty()
    } catch (_: Exception) {
        emptyList()
    }

    /**
     * 加入 B 站追番（需登录）。season_id 来自搜索/详情页；失败不抛异常。
     */
    suspend fun addBangumiFollow(seasonId: Long): Boolean = try {
        val csrf = http.cookieJar.value("bilibili.com", "bili_jct").orEmpty()
        if (csrf.isEmpty()) return false
        val body = http.postForm(
            "https://api.bilibili.com/pgc/web/follow/add",
            mapOf("season_id" to seasonId.toString(), "csrf" to csrf),
            headers = mapOf("Referer" to "https://www.bilibili.com"),
        )
        runCatching {
            json.parseToJsonElement(body).jsonObject["code"]?.jsonPrimitive?.content?.toIntOrNull()
        }.getOrNull() == 0
    } catch (_: Exception) {
        false
    }

    /**
     * 番剧 season_id → media_id（番剧评论区的 oid）。
     * 评论接口 type=1 时 oid 用 media_id；查不到返回 0。
     */
    suspend fun bangumiMediaId(seasonId: Long): Long = try {
        val body = http.getString(
            "https://api.bilibili.com/pgc/view/web/season?season_id=$seasonId",
            referer = "https://www.bilibili.com",
        )
        json.parseToJsonElement(body).jsonObject["result"]?.jsonObject
            ?.get("media_id")?.jsonPrimitive?.longOrNull ?: 0L
    } catch (_: Exception) {
        0L
    }

    /**
     * 按关键词搜索番剧（用于把订阅源里的番名匹配到 B 站 season_id）。
     */
    suspend fun searchBangumi(keyword: String): List<BangumiSearchItem> = try {
        val body = signedGet(
            "https://api.bilibili.com/x/web-interface/wbi/search/type",
            mapOf("search_type" to "media_bangumi", "keyword" to keyword, "page" to "1"),
            referer = "https://search.bilibili.com",
        )
        decode<BangumiSearchData>(body).data?.result.orEmpty()
    } catch (_: Exception) {
        emptyList()
    }

    /** 当前登录用户 mid（游客为 0）。 */
    suspend fun myMid(): Long = try {
        nav().mid ?: 0L
    } catch (_: Exception) {
        0L
    }

    suspend fun history(max: Int = 100): List<HistoryItem> {
        val body = http.getString(
            "https://api.bilibili.com/x/v2/history?max=$max",
            referer = "https://www.bilibili.com",
        )
        return json.decodeFromString<ApiResp<List<HistoryItem>>>(body).data.orEmpty()
    }

    /**
     * 获取播放地址（多端 + 多策略，2026-09 逆向实测）：
     *
     * 1. 桌面 Chrome 伪装的旧版 [/x/player/playurl]：匿名稳定 200，DASH 实际给到 480P；
     * 2. 安卓 appkey 签名（无 access_key 即匿名）：同样稳定，作为 DASH 第二来源；
     * 3. [platform=html5]：合流 MP4，匿名可拿完整 720P 单文件；
     * 4. ①~③均报权限错误时，wbi 端点 + try_look=1 拿试看流（试看标记由 VIP 拦截器本地清除）；
     * 5. 用户配置了哔哩漫游式解析服务器时，播放接口的主机名替换为该服务器，并手动带上
     *    B 站 Cookie（OkHttp 的 CookieJar 不会跨域发送），由代理解锁大会员清晰度。
     *
     * 最终从多个成功响应里挑选「实际下发的最高视频轨 / 最高 durl 画质」，避免被 accept_quality
     * 的广告位数值骗到（接口声称支持 1080P，匿名实际只下发 480P 轨）。
     */
    suspend fun playurl(
        bvid: String,
        cid: Long,
        qn: Int = 127,
        forceTryLook: Boolean = false,
        roamingServer: String? = null,
    ): PlayUrlData {
        ensureBuvid()
        val referer = "https://www.bilibili.com/video/$bvid"
        val baseParams = linkedMapOf(
            "bvid" to bvid,
            "cid" to cid.toString(),
            "qn" to qn.toString(),
            "fnval" to "4048",
            "fnver" to "0",
            "fourk" to "1",
            "otype" to "json",
        )
        val candidates = ArrayList<PlayUrlData>()
        var lastErr = "播放地址获取失败"
        var vipDenied = false

        fun roamingOf(original: String): String =
            if (!roamingServer.isNullOrBlank()) applyRoaming(original, roamingServer) else original

        // 大会员专享：优先走试看解锁链（wbi → 安卓老 build），本地拦截器清试看标记。
        if (forceTryLook) {
            fetchVipTrialCandidate(baseParams, referer, ::roamingOf)
                ?.let { return it }
            error("该视频需要大会员")
        }

        // ① web 旧版端点 DASH
        runCatching {
            fetchPlayurl(
                url = roamingOf("https://api.bilibili.com/x/player/playurl"),
                params = baseParams,
                referer = referer,
            )
        }.onSuccess { d ->
            if (d.code == 0 && d.data != null) candidates += d.data else {
                if (d.code in NEEDS_VIP_CODES) vipDenied = true
                lastErr = d.errMsg
            }
        }.onFailure {
            lastErr = when (it) {
                is com.pilinara.net.BiliRiskControlException -> it.message ?: it.toString()
                else -> it.message ?: lastErr
            }
        }

        // ② 安卓 appkey 签名 DASH（匿名），与 web 端互补风控
        runCatching {
            val signed = appSign(
                baseParams + mapOf("mobi_app" to "android", "platform" to "android"),
                ANDROID_APPKEY, ANDROID_APPSEC,
            )
            val body = http.getString(
                roamingOf("https://api.bilibili.com/x/player/playurl") + "?" + encode(signed),
                headers = mapOf("User-Agent" to UA_ANDROID),
                referer = referer,
            )
            decode<PlayUrlData>(body)
        }.onSuccess { r ->
            if (r.code == 0 && r.data != null) candidates += r.data
            else if (r.code in NEEDS_VIP_CODES) vipDenied = true
        }

        // ③ 权限错误：依次尝试 wbi try_look 与安卓老 build try_look（社区经典解锁手法）
        if (vipDenied) {
            val unlocked = fetchVipTrialCandidate(baseParams, referer, ::roamingOf)
            if (unlocked != null) return unlocked
            error("该视频需要大会员：$lastErr")
        }

        // ④ 匿名 html5 合流 720P（作为候选参与画质 PK；登录用户的 DASH 通常更高，不会被选中）
        val loggedIn = http.cookieJar.has(BILI_DOMAIN, "SESSDATA")
        if (!loggedIn) {
            runCatching {
                val body = http.getString(
                    roamingOf("https://api.bilibili.com/x/player/playurl") + "?" +
                        encode(baseParams + mapOf("platform" to "html5", "high_quality" to "1")),
                    referer = referer,
                )
                decode<PlayUrlData>(body)
            }.onSuccess { r -> if (r.code == 0 && r.data != null) candidates += r.data }
        }

        // ⑤ 未登录：wbi/playurl + try_look=1。try_look 是 B 站官方参数——未登录也可下发
        //    720P/1080P 清晰度（参考 bilipai/bv 的未登录高画质策略）。作为候选参与画质 PK，
        //    让匿名用户不必登录就能拿到更清晰的流。
        if (!loggedIn) {
            runCatching {
                fetchPlayurl(
                    url = roamingOf("https://api.bilibili.com/x/player/wbi/playurl"),
                    params = baseParams + ("try_look" to "1"),
                    signed = true,
                    referer = referer,
                )
            }.onSuccess { r -> if (r.code == 0 && r.data != null) candidates += r.data }
        }

        if (candidates.isEmpty()) {
            error(
                when {
                    lastErr.contains("Unexpected JSON") || lastErr.contains("风控") ->
                        "网络请求被 B 站风控拦截。请先登录账号，或在网络环境变化后重试。"
                    else -> lastErr
                },
            )
        }
        return candidates.maxByOrNull(::scorePlayData) ?: error(lastErr)
    }

    /**
     * 大会员内容试看解锁候选链：
     * 1) wbi/playurl + try_look（web 试看，字段被拦截器改写）；
     * 2) 安卓 v2/playurl + 老 build(6260000) appkey 签名 + try_look
     *    （社区逆向验证的经典完整流手法，部分番剧可直接拿到非截断 DASH）。
     * 返回首个 code==0 的 data；均失败返回 null。
     */
    private suspend fun fetchVipTrialCandidate(
        baseParams: Map<String, String>,
        referer: String,
        roamingOf: (String) -> String,
    ): PlayUrlData? {
        runCatching {
            fetchPlayurl(
                url = roamingOf("https://api.bilibili.com/x/player/wbi/playurl"),
                params = baseParams + ("try_look" to "1"),
                signed = true,
                referer = referer,
            )
        }.getOrNull()?.let { if (it.code == 0 && it.data != null) return it.data }

        runCatching {
            val p = baseParams + mapOf(
                "platform" to "android",
                "mobi_app" to "android",
                "build" to "6260000",
                "try_look" to "1",
            )
            val signed = appSign(p, ANDROID_APPKEY, ANDROID_APPSEC)
            val url = roamingOf("https://api.bilibili.com/x/v2/playurl") + "?" + encode(signed)
            val body = http.getString(
                url,
                headers = mapOf("User-Agent" to UA_ANDROID),
                referer = referer,
            )
            decode<PlayUrlData>(body)
        }.getOrNull()?.let { if (it.code == 0 && it.data != null) return it.data }

        return null
    }

    /** 拉一次 playurl 并解码。[signed] 为 true 时走 WBI 签名。 */
    private suspend fun fetchPlayurl(
        url: String,
        params: Map<String, String>,
        referer: String,
        signed: Boolean = false,
    ): ApiResp<PlayUrlData> {
        val query = if (signed) {
            val key = ensureWbiKey()
            if (key != null) Wbi.sign(params, key) else encode(params)
        } else {
            encode(params)
        }
        val body = http.getString(
            "$url?$query",
            referer = referer,
            origin = "https://www.bilibili.com",
            headers = if (url.contains("api.bilibili.com")) emptyMap() else roamingCookieHeaders(url),
        )
        return decode(body)
    }

    /** 安卓端 appkey 签名：参数排序拼接 + MD5(appsec)。 */
    private fun appSign(
        params: Map<String, String>,
        appkey: String,
        appsec: String,
    ): Map<String, String> {
        val p = LinkedHashMap(params)
        p["appkey"] = appkey
        p["ts"] = (System.currentTimeMillis() / 1000).toString()
        // 部分接口要求；带上无害。
        p.putIfAbsent("build", "8010000")
        val raw = p.toSortedMap().entries.joinToString("&") { "${it.key}=${it.value}" }
        val md5 = java.security.MessageDigest.getInstance("MD5")
            .digest((raw + appsec).toByteArray())
            .joinToString("") { "%02x".format(it) }
        p["sign"] = md5
        return p
    }

    /** 主机名替换（哔哩漫游风格）。 */
    private fun applyRoaming(original: String, server: String): String {
        val base = server.trim().trimEnd('/')
        val host = original.substringAfter("://").substringBefore('/')
        return original.replaceFirst(host, base.substringAfter("://"))
    }

    /** 给第三方解析服务器的请求手动附加 bilibili.com 的 Cookie（SESSDATA 等）。 */
    private fun roamingCookieHeaders(requestUrl: String): Map<String, String> {
        val cookies = http.cookieJar.loadForRequest(
            "https://api.bilibili.com/".toHttpUrl(),
        )
        if (cookies.isEmpty()) return emptyMap()
        return mapOf("Cookie" to cookies.joinToString("; ") { "${it.name}=${it.value}" })
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

        // 安卓官方客户端匿名 appkey（社区逆向公开常量；无 access_key 时只能取免费内容）。
        private const val ANDROID_APPKEY = "1d8b6e7d45233436"
        private const val ANDROID_APPSEC = "560c52ccd288fed045859ed18bffd973"
        private const val UA_ANDROID =
            "Mozilla/5.0 BiliDroid/8.10.0 (bbcallen@gmail.com) os/android model/PiliNara"

        // -10403: 大会员专享；100: 需要登录/无权限；-10404: 地区限制等。
        private val NEEDS_VIP_CODES = setOf(-10403, 100, -10404)

        /**
         * 候选播放地址打分：以**实际下发**的最高视频轨/分段画质为准（×10），
         * 同画质下 DASH（可分离音轨）+1，分高者胜。
         */
        private fun scorePlayData(d: PlayUrlData): Int {
            val vQn = d.dash?.video?.maxOfOrNull { it.id } ?: 0
            if (vQn > 0) return vQn * 10 + 1
            if (d.durl.isNotEmpty()) return d.quality * 10
            return 0
        }

        /** 协议相对图片地址补全。 */
        fun image(url: String): String =
            if (url.startsWith("//")) "https:$url" else url
    }
}
