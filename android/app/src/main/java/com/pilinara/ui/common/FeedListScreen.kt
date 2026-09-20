package com.pilinara.ui.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.api.BiliVideo
import com.pilinara.api.FavFolder
import com.pilinara.ui.bili.VideoDetailScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 需要登录的通用视频流页（动态 / 历史）。
 *
 * 未登录（接口返回 -101）时给登录引导，而不是把「账号未登录」当成加载失败——
 * 这类页面对游客本来就没内容。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PagedVideoListScreen(
    container: AppContainer,
    title: String,
    loginHint: String,
    onImmersive: (Boolean) -> Unit,
    /** 分页加载：page 从 1 起；[paged] 为 false 时只加载一次。 */
    pageLoader: suspend (Int) -> List<BiliVideo>,
    paged: Boolean = true,
) {
    val scope = rememberCoroutineScope()
    val videos = remember { mutableStateListOf<BiliVideo>() }
    var page by remember { mutableIntStateOf(1) }
    var loading by remember { mutableStateOf(true) }
    var unauthenticated by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var selected by remember { mutableStateOf<BiliVideo?>(null) }

    fun loadMore() {
        if (loading || !hasMore) return
        loading = true
        scope.launch {
            runSuspendCatching { withContext(Dispatchers.IO) { pageLoader(page) } }
                .onSuccess { list ->
                    val known = videos.map { it.bvid.ifEmpty { "aid_${it.aid}" } }.toHashSet()
                    videos.addAll(list.filter { v -> known.add(v.bvid.ifEmpty { "aid_${v.aid}" }) })
                    page++
                    if (!paged || list.isEmpty()) hasMore = false
                    error = null
                }
                .onFailure { e ->
                    // B 站对游客返回 -101（账号未登录）；这是预期状态而非故障。
                    if (isNotLoggedIn(e)) unauthenticated = true
                    else if (videos.isEmpty()) error = e.message
                }
            loading = false
        }
    }

    LaunchedEffect(Unit) { if (videos.isEmpty() && !unauthenticated) loadMore() }

    val current = selected
    if (current != null) {
        VideoDetailScreen(
            container = container,
            video = current,
            onBack = { selected = null },
            onOpenVideo = { selected = it },
            onImmersive = onImmersive,
        )
        return
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text(title) }) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when {
                unauthenticated -> LoginPrompt(loginHint)
                loading && videos.isEmpty() -> LoadingBox()
                error != null && videos.isEmpty() -> ErrorBox("加载失败：$error")
                videos.isEmpty() -> ErrorBox("暂无内容")
                else -> VideoGrid(
                    videos = videos,
                    onItemClick = { selected = it },
                    onLoadMore = if (paged && hasMore) ::loadMore else null,
                )
            }
        }
    }
}

/** 收藏页：先拉收藏夹列表，再按选中的夹拉内容（均需登录）。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(
    container: AppContainer,
    onImmersive: (Boolean) -> Unit,
) {
    var folders by remember { mutableStateOf<List<FavFolder>?>(null) }
    var unauthenticated by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedTab by remember { mutableIntStateOf(0) }
    var opened by remember { mutableStateOf<BiliVideo?>(null) }

    LaunchedEffect(Unit) {
        runSuspendCatching { withContext(Dispatchers.IO) { container.api.favoriteFolders() } }
            .onSuccess { folders = it }
            .onFailure { e ->
                if (isNotLoggedIn(e)) unauthenticated = true else error = e.message
            }
    }

    opened?.let { v ->
        VideoDetailScreen(
            container = container,
            video = v,
            onBack = { opened = null },
            onOpenVideo = { opened = it },
            onImmersive = onImmersive,
        )
        return
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("收藏") }) },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            val list = folders
            when {
                unauthenticated -> LoginPrompt("登录后查看我的收藏夹")
                error != null -> ErrorBox("加载失败：$error")
                list == null -> LoadingBox()
                list.isEmpty() -> ErrorBox("还没有收藏夹")
                else -> {
                    val idx = selectedTab.coerceIn(0, list.lastIndex)
                    PrimaryScrollableTabRow(selectedTabIndex = idx, edgePadding = 8.dp) {
                        list.forEachIndexed { i, f ->
                            Tab(
                                selected = i == idx,
                                onClick = { selectedTab = i },
                                text = { Text("${f.title}（${f.mediaCount}）") },
                            )
                        }
                    }
                    FolderVideos(
                        container = container,
                        key = list[idx].mediaId,
                        loader = { container.api.favoriteMedias(list[idx].mediaId) },
                        onOpen = { opened = it },
                    )
                }
            }
        }
    }
}

@Composable
private fun FolderVideos(
    container: AppContainer,
    key: Long,
    loader: suspend () -> List<BiliVideo>,
    onOpen: (BiliVideo) -> Unit,
) {
    var videos by remember(key) { mutableStateOf<List<BiliVideo>?>(null) }
    var error by remember(key) { mutableStateOf<String?>(null) }
    LaunchedEffect(key) {
        runSuspendCatching { withContext(Dispatchers.IO) { loader() } }
            .onSuccess { videos = it }
            .onFailure { error = it.message }
    }
    when {
        videos == null && error == null -> LoadingBox()
        error != null && videos == null -> ErrorBox("加载失败：$error")
        else -> VideoGrid(videos = videos.orEmpty(), onItemClick = onOpen)
    }
}

@Composable
private fun LoginPrompt(hint: String) {
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(hint, style = MaterialTheme.typography.bodyMedium)
        Text(
            "请到「我的」页扫码登录",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** B 站游客响应码 -101（账号未登录）。 */
private fun isNotLoggedIn(e: Throwable): Boolean {
    val msg = e.message.orEmpty()
    return msg.contains("-101") || msg.contains("未登录")
}
