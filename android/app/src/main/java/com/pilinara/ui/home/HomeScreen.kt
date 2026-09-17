package com.pilinara.ui.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.PrimaryScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.api.BiliOwner
import com.pilinara.api.BiliVideo
import com.pilinara.core.NativeCore
import com.pilinara.data.JsonFileStore
import com.pilinara.ui.bili.VideoDetailScreen
import com.pilinara.ui.common.ErrorBox
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.VideoGrid
import com.pilinara.ui.common.runSuspendCatching
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

private enum class HomeTab(val label: String) {
    POPULAR("热门"),
    RECOMMEND("推荐"),
    TODAY("今日"),
    HISTORY("历史"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(container: AppContainer) {
    var tab by remember { mutableStateOf(HomeTab.POPULAR) }
    var selected by remember { mutableStateOf<BiliVideo?>(null) }

    val current = selected
    if (current != null) {
        VideoDetailScreen(container = container, video = current, onBack = { selected = null })
        return
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(title = { Text("PiliNara") })
                PrimaryScrollableTabRow(selectedTabIndex = tab.ordinal, edgePadding = 8.dp) {
                    HomeTab.entries.forEach { t ->
                        Tab(selected = tab == t, onClick = { tab = t }, text = { Text(t.label) })
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                HomeTab.POPULAR -> PagedFeed(container, onOpen = { selected = it }) { page ->
                    applyFeedFilter(container, container.api.popular(page))
                }

                HomeTab.RECOMMEND -> PagedFeed(container, onOpen = { selected = it }) { page ->
                    applyFeedFilter(container, container.api.recommend(page))
                }

                HomeTab.TODAY -> TodayFeed(container, onOpen = { selected = it })
                HomeTab.HISTORY -> HistoryFeed(container, onOpen = { selected = it })
            }
        }
    }
}

/** 热门/推荐共用的分页网格。[fetchPage] 在 IO 上执行，返回第 page 页（1 起）。 */
@Composable
private fun PagedFeed(
    container: AppContainer,
    onOpen: (BiliVideo) -> Unit,
    fetchPage: suspend (Int) -> List<BiliVideo>,
) {
    val scope = rememberCoroutineScope()
    val videos = remember { mutableStateListOf<BiliVideo>() }
    var page by remember { mutableIntStateOf(1) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun loadMore() {
        if (loading) return
        loading = true
        scope.launch {
            runSuspendCatching { withContext(Dispatchers.IO) { fetchPage(page) } }
                .onSuccess {
                    // 跨页重复的卡片不再重复加入。
                    val known = videos.map { it.bvid.ifEmpty { "aid_${it.aid}" } }.toHashSet()
                    videos.addAll(it.filter { v ->
                        known.add(v.bvid.ifEmpty { "aid_${v.aid}" })
                    })
                    page++
                    error = null
                }
                .onFailure { if (videos.isEmpty()) error = it.message }
            loading = false
        }
    }

    LaunchedEffect(Unit) { if (videos.isEmpty()) loadMore() }

    when {
        loading && videos.isEmpty() -> LoadingBox()
        error != null && videos.isEmpty() -> ErrorBox("加载失败：$error")
        else -> VideoGrid(
            videos = videos,
            onItemClick = onOpen,
            onLoadMore = if (loading) null else ::loadMore,
        )
    }
}

/** 「今日推荐」：Rust 核心根据观看历史给候选流打分排序。 */
@Composable
private fun TodayFeed(container: AppContainer, onOpen: (BiliVideo) -> Unit) {
    val videos = remember { mutableStateListOf<BiliVideo>() }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runSuspendCatching {
            withContext(Dispatchers.IO) {
                val history = container.api.history(50)
                val candidates = container.api.popular(1, 50) + container.api.recommend(1)
                // Rust 侧定义的是扁平字段结构，这里按其 schema 组装而非直接传 B 站原始模型。
                val historyJson = buildJsonArray {
                    history.forEach { h ->
                        addJsonObject {
                            put("bvid", h.bvid)
                            put("title", h.title)
                            put("author_mid", h.owner?.mid ?: 0L)
                            put("author_name", h.owner?.name.orEmpty())
                            put("view_at", h.history?.viewAt ?: 0L)
                            put("progress", h.history?.progress ?: 0L)
                            put("duration", h.duration)
                            put("tag_name", h.tname.orEmpty())
                        }
                    }
                }.toString()
                val candidateJson = buildJsonArray {
                    candidates.forEach { v ->
                        addJsonObject {
                            put("bvid", v.bvid)
                            put("cid", v.cid)
                            put("aid", v.aid)
                            put("cover", v.pic)
                            put("title", v.title)
                            put("duration", v.duration)
                            put("pubdate", v.pubdate)
                            put("goto", v.goto)
                            put("owner_mid", v.owner.mid)
                            put("owner_name", v.owner.name)
                            put("owner_face", v.owner.face)
                            put("stat_view", v.stat.view)
                            put("stat_like", v.stat.like)
                            put("stat_danmu", v.stat.danmaku)
                            put("tname", v.tname)
                        }
                    }
                }.toString()
                val plan = NativeCore
                    .buildTodayWatchPlan(historyJson, candidateJson, "relax", "balanced")
                    .let { Json.parseToJsonElement(it).jsonObject }
                plan["video_queue"]!!.jsonArray.mapNotNull { el ->
                    runCatching {
                        val o = el.jsonObject
                        BiliVideo(
                            aid = o["aid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                            bvid = o["bvid"]?.jsonPrimitive?.content.orEmpty(),
                            cid = o["cid"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                            title = o["title"]?.jsonPrimitive?.content.orEmpty(),
                            pic = o["cover"]?.jsonPrimitive?.content.orEmpty(),
                            duration = o["duration"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                            owner = BiliOwner(
                                name = o["owner_name"]?.jsonPrimitive?.content.orEmpty(),
                            ),
                        )
                    }.getOrNull()
                }
            }
        }.onSuccess { videos.addAll(it) }
            .onFailure { error = it.message }
        loading = false
    }

    when {
        loading -> LoadingBox()
        videos.isEmpty() -> ErrorBox("${error ?: "暂无推荐"}（登录并产生观看历史后更准）")
        else -> VideoGrid(videos = videos, onItemClick = onOpen)
    }
}

@Composable
private fun HistoryFeed(container: AppContainer, onOpen: (BiliVideo) -> Unit) {
    val videos = remember { mutableStateListOf<BiliVideo>() }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        runSuspendCatching { withContext(Dispatchers.IO) { container.api.history(100) } }
            .onSuccess { list ->
                videos.addAll(
                    list.map { h ->
                        BiliVideo(
                            aid = h.aid,
                            bvid = h.bvid,
                            cid = h.history?.cid ?: 0L,
                            title = h.title,
                            pic = h.pic,
                            duration = h.duration,
                            tname = h.tname.orEmpty(),
                            owner = BiliOwner(name = h.owner?.name.orEmpty()),
                        )
                    },
                )
            }
            .onFailure { error = it.message }
        loading = false
    }

    when {
        loading -> LoadingBox()
        videos.isEmpty() -> ErrorBox("${error ?: "暂无历史"}（需要登录）")
        else -> VideoGrid(videos = videos, onItemClick = onOpen)
    }
}

/** 信息流规则过滤：存在本地规则文件时交 Rust 核心处理，否则原样返回。 */
private suspend fun applyFeedFilter(container: AppContainer, raw: List<BiliVideo>): List<BiliVideo> {
    val rules = container.files.read(JsonFileStore.FEED_RULES) ?: return raw
    return runCatching {
        val out = NativeCore.applyFeedFilter(
            Json.encodeToString(ListSerializer(BiliVideo.serializer()), raw),
            rules,
        )
        Json.decodeFromString(ListSerializer(BiliVideo.serializer()), out)
    }.getOrDefault(raw)
}
