package com.pilinara.ui.source

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.pilinara.AppContainer
import com.pilinara.api.ReplyItem
import com.pilinara.player.PlayRequest
import com.pilinara.player.PlayerActivity
import com.pilinara.source.SourceChannel
import com.pilinara.ui.common.CommentsPage
import com.pilinara.ui.common.ErrorBox
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.loadReplies
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val SOURCE_DETAIL_TABS = listOf("选集", "评论")

/**
 * 第三方源详情：多线路 chips + 选集网格 + 评论页签。
 * 播放时经选择器/嗅探拿到直链，按扩展名判定 HLS/DASH/普通流。
 *
 * 顶栏「登录」：WebView 打开源站，用户登录后 Cookie 实时灌入全局 jar，
 * 该源后续请求自动携带登录态（会员集数等）。
 * 评论页签：按番名匹配 B 站番剧，复用 B 站评论区（游客可看）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourceDetailScreen(
    container: AppContainer,
    sourceName: String,
    subjectUrl: String,
    subjectName: String,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var channels by remember { mutableStateOf<List<SourceChannel>>(emptyList()) }
    var channelIndex by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var resolving by remember { mutableStateOf<String?>(null) }

    // 源账号登录态（该源站域名下有无 Cookie）。
    val host = remember(subjectUrl) { SourceLoginActivity.hostOf(subjectUrl) }
    var loggedIn by remember { mutableStateOf(false) }
    var showLogout by remember { mutableStateOf(false) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        // 从登录 WebView 返回（ON_RESUME）时刷新登录态显示。
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                loggedIn = host.isNotEmpty() && container.http.cookieJar.hasAny(host)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // 追番（本地 + 可选同步 B 站）。
    val followed by container.sources.followed.collectAsState()
    val isFollowed = followed.any { it.subjectUrl == subjectUrl }
    var followBusy by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }

    // 评论分页状态（B 站番剧评论区，oid = media_id）。
    val pagerState = rememberPagerState(pageCount = { SOURCE_DETAIL_TABS.size })
    var commentResolved by remember { mutableStateOf(false) }
    var commentOid by remember { mutableStateOf(0L) }
    var replies by remember { mutableStateOf<List<ReplyItem>>(emptyList()) }
    var replyNext by remember { mutableStateOf(0L) }
    var replyEnd by remember { mutableStateOf(false) }
    var replyLoading by remember { mutableStateOf(false) }

    fun toggleFollow() {
        if (followBusy) return
        scope.launch {
            if (isFollowed) {
                withContext(Dispatchers.IO) { container.sources.removeFollow(subjectUrl) }
                toast = "已取消追番"
                return@launch
            }
            followBusy = true
            // 追番同步到 B 站：开关开启时先按番名搜索 B 站，存在则加入 B 站追番；
            // 不存在（或搜索/加入失败）则仅本地追番，不阻断。
            var biliSeasonId = 0L
            val sync = container.settings.bangumiSync.first()
            if (sync) {
                withContext(Dispatchers.IO) {
                    val hit = runCatching { container.api.searchBangumi(subjectName) }
                        .getOrDefault(emptyList())
                        .firstOrNull { it.title.isNotEmpty() }
                    if (hit != null && runCatching { container.api.addBangumiFollow(hit.seasonId) }
                            .getOrDefault(false)
                    ) {
                        biliSeasonId = hit.seasonId
                    }
                }
            }
            withContext(Dispatchers.IO) {
                container.sources.addFollow(subjectName, subjectUrl, sourceName, biliSeasonId)
            }
            toast = if (biliSeasonId > 0) "已追番，并同步到 B 站追番" else "已追番"
            followBusy = false
        }
    }

    LaunchedEffect(subjectUrl) {
        com.pilinara.ui.common.runSuspendCatching {
            withContext(Dispatchers.IO) {
                val instance = container.sources.instances()
                    .firstOrNull { it.name == sourceName && it.enabled }
                    ?: error("源「$sourceName」未启用或不存在")
                container.sourceRepository.channels(instance.raw.toString(), subjectUrl)
            }
        }.onSuccess { channels = it }
            .onFailure { error = it.message }
        loading = false
    }

    // 首次切到评论页签才解析 B 站评论区：番名 → season_id → media_id（评论 oid）。
    LaunchedEffect(pagerState.currentPage) {
        if (pagerState.currentPage != 1 || commentResolved) return@LaunchedEffect
        commentResolved = true
        withContext(Dispatchers.IO) {
            val hit = runCatching { container.api.searchBangumi(subjectName) }
                .getOrDefault(emptyList())
                .firstOrNull { it.title.isNotEmpty() }
            commentOid = if (hit != null) {
                runCatching { container.api.bangumiMediaId(hit.seasonId) }.getOrDefault(0L)
            } else {
                0L
            }
        }
        if (commentOid > 0) {
            loadReplies(
                container, commentOid, 0L,
                { replyLoading = it },
                { replyEnd = it },
            ) { list, next ->
                replies = (replies + list).distinctBy { it.rpid }
                replyNext = next
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(subjectName, maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    if (host.isNotEmpty()) {
                        TextButton(onClick = {
                            if (loggedIn) showLogout = true
                            else context.startActivity(
                                SourceLoginActivity.intent(context, host, sourceName),
                            )
                        }) {
                            Text(if (loggedIn) "已登录" else "登录")
                        }
                    }
                    TextButton(enabled = !followBusy, onClick = ::toggleFollow) {
                        Text(if (isFollowed) "已追番" else "追番")
                    }
                },
            )
        },
    ) { padding ->
        when {
            loading -> LoadingBox(Modifier.padding(padding))
            error != null || channels.isEmpty() ->
                ErrorBox("解析失败：${error ?: "该源没有返回可播放线路"}", Modifier.padding(padding))

            else -> {
                val channel = channels.getOrElse(channelIndex) { channels.first() }
                Column(Modifier.fillMaxSize().padding(padding)) {
                    PrimaryTabRow(selectedTabIndex = pagerState.currentPage) {
                        SOURCE_DETAIL_TABS.forEachIndexed { i, label ->
                            Tab(
                                selected = pagerState.currentPage == i,
                                onClick = { scope.launch { pagerState.animateScrollToPage(i) } },
                                text = { Text(label) },
                            )
                        }
                    }
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                        when (page) {
                            0 -> LazyColumn(Modifier.fillMaxSize()) {
                                item { ChannelChips(channels, channelIndex) { channelIndex = it } }
                                items(channel.episodes.chunked(3)) { rowItems ->
                                    Row(
                                        Modifier.fillMaxWidth()
                                            .padding(horizontal = 12.dp, vertical = 4.dp),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        rowItems.forEach { ep ->
                                            EpisodeButton(
                                                text = ep.name.ifEmpty { ep.sort },
                                                busy = resolving == ep.pageUrl,
                                                modifier = Modifier.weight(1f),
                                            ) {
                                                scope.launch {
                                                    resolving = ep.pageUrl
                                                    com.pilinara.ui.common.runSuspendCatching {
                                                        withContext(Dispatchers.IO) {
                                                            val instance = container.sources.instances()
                                                                .first { it.name == sourceName && it.enabled }
                                                            container.sourceRepository.resolve(
                                                                instance.raw.toString(),
                                                                ep.pageUrl,
                                                            )
                                                        }
                                                    }.onSuccess { resolved ->
                                                        val type = when {
                                                            resolved.url.contains(".m3u8", ignoreCase = true) -> "hls"
                                                            resolved.url.contains(".mpd", ignoreCase = true) -> "dash"
                                                            else -> "progressive"
                                                        }
                                                        PlayerActivity.start(
                                                            container.appContext,
                                                            PlayRequest(
                                                                title = "$subjectName - ${ep.name.ifEmpty { ep.sort }}",
                                                                videoUrl = resolved.url,
                                                                streamType = type,
                                                                headers = resolved.headers,
                                                            ),
                                                        )
                                                    }.onFailure {
                                                        android.widget.Toast.makeText(
                                                            container.appContext,
                                                            "嗅探失败：${it.message}",
                                                            android.widget.Toast.LENGTH_LONG,
                                                        ).show()
                                                    }
                                                    resolving = null
                                                }
                                            }
                                        }
                                        repeat(3 - rowItems.size) { Box(Modifier.weight(1f)) }
                                    }
                                }
                            }

                            1 -> when {
                                !commentResolved -> LoadingBox()
                                commentOid <= 0 -> Box(
                                    Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        "未在 B 站匹配到「$subjectName」，暂无评论",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }

                                else -> CommentsPage(
                                    container = container,
                                    replies = replies,
                                    loading = replyLoading,
                                    ended = replyEnd,
                                    oid = commentOid,
                                    nextCursor = replyNext,
                                    onAppend = { list, next, end ->
                                        replies = (replies + list).distinctBy { it.rpid }
                                        replyNext = next
                                        replyEnd = end
                                    },
                                    onLoading = { replyLoading = it },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showLogout) {
        AlertDialog(
            onDismissRequest = { showLogout = false },
            title = { Text("退出源账号登录") },
            text = { Text("将清除「$sourceName」保存在本机的登录 Cookie，之后该源的会员内容可能无法解析。") },
            confirmButton = {
                TextButton(onClick = {
                    showLogout = false
                    container.http.cookieJar.clearDomain(host)
                    loggedIn = false
                    toast = "已退出登录"
                }) { Text("退出登录") }
            },
            dismissButton = { TextButton(onClick = { showLogout = false }) { Text("取消") } },
        )
    }

    toast?.let { msg ->
        android.widget.Toast.makeText(container.appContext, msg, android.widget.Toast.LENGTH_SHORT).show()
        toast = null
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChannelChips(channels: List<SourceChannel>, selected: Int, onSelect: (Int) -> Unit) {
    FlowRow(
        Modifier.fillMaxWidth().padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        channels.forEachIndexed { i, ch ->
            FilterChip(
                selected = i == selected,
                onClick = { onSelect(i) },
                label = { Text(ch.name.ifEmpty { "线路 ${i + 1}" }) },
            )
        }
    }
}

@Composable
private fun EpisodeButton(
    text: String,
    busy: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Box(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(enabled = !busy, onClick = onClick)
            .padding(vertical = 14.dp),
        contentAlignment = androidx.compose.ui.Alignment.Center,
    ) {
        Text(
            text = if (busy) "解析中…" else text,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
        )
    }
}
