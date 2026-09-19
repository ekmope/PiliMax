package com.pilinara.ui.bili

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.MonetizationOn
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pilinara.AppContainer
import com.pilinara.api.BiliApi
import com.pilinara.api.BiliVideo
import com.pilinara.api.ReplyItem
import com.pilinara.api.ViewData
import com.pilinara.player.InlinePlayer
import com.pilinara.player.PlayRequest
import com.pilinara.player.launchFullscreen
import com.pilinara.ui.common.CommentsPage
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.loadReplies
import com.pilinara.ui.common.runSuspendCatching
import com.pilinara.ui.common.toWan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val DETAIL_TABS = listOf("简介", "评论", "相关")

/**
 * B 站视频详情（bilipai / 官方 App 式）：
 * 顶部内联播放器（进入即播，下滑看内容，右滑切评论/相关），
 * 下方标题 + 操作栏（点赞/投币/收藏/分享）+ 三页滑动内容。
 * 全屏按钮转横屏 PlayerActivity。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoDetailScreen(
    container: AppContainer,
    video: BiliVideo,
    onBack: () -> Unit,
    onOpenVideo: (BiliVideo) -> Unit = {},
) {
    var detail by remember { mutableStateOf<ViewData?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var retryKey by remember { mutableStateOf(0) }

    // 评论分页状态。
    var replies by remember { mutableStateOf<List<ReplyItem>>(emptyList()) }
    var replyNext by remember { mutableStateOf(0L) }
    var replyEnd by remember { mutableStateOf(false) }
    var replyLoading by remember { mutableStateOf(false) }

    // 相关推荐。
    var related by remember { mutableStateOf<List<BiliVideo>?>(null) }

    val pagerState = rememberPagerState(pageCount = { DETAIL_TABS.size })
    val scope = rememberCoroutineScope()

    LaunchedEffect(video.bvid, retryKey) {
        error = null
        runSuspendCatching { withContext(Dispatchers.IO) { container.api.view(video.bvid) } }
            .onSuccess { detail = it }
            .onFailure { error = it.message ?: "加载失败" }
    }

    // 详情成功后拉第一页评论 + 相关推荐。
    LaunchedEffect(detail?.aid) {
        val aid = detail?.aid ?: return@LaunchedEffect
        replies = emptyList()
        replyNext = 0
        replyEnd = false
        related = null
        loadReplies(container, aid, 0L, { replyLoading = it }, { replyEnd = it }) { list, next ->
            replies = (replies + list).distinctBy { r -> r.rpid }
            replyNext = next
        }
        related = withContext(Dispatchers.IO) {
            runCatching { container.api.related(aid) }.getOrDefault(emptyList())
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("视频详情", maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            // 顶部内联播放器：进入即播；失败时显示封面 + 错误。
            Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
                if (video.cid > 0 && video.bvid.isNotEmpty()) {
                    InlinePlayer(
                        container = container,
                        request = PlayRequest(
                            title = video.title.ifEmpty { "未知标题" },
                            videoUrl = "",
                            cid = video.cid,
                            bvid = video.bvid,
                        ),
                        onFullscreen = { req -> launchFullscreen(container.appContext, req) },
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Box(
                        Modifier.fillMaxSize()
                            .background(MaterialTheme.colorScheme.surfaceVariant),
                        contentAlignment = Alignment.Center,
                    ) { Text("无法播放：缺少 cid") }
                }
            }

            // 标题 + 操作栏。
            val d = detail
            Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text(
                    d?.title ?: video.title,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = buildString {
                        append(d?.owner?.name ?: video.owner.name)
                        append(" · ")
                        append((d?.stat?.view ?: video.stat.view).toWan())
                        append("播放 · ")
                        append((d?.stat?.danmaku ?: video.stat.danmaku).toWan())
                        append("弹幕")
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
                if (error != null) {
                    Text(
                        "详情加载失败：$error",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                    Button(onClick = { retryKey++ }, modifier = Modifier.padding(top = 4.dp)) {
                        Text("重试")
                    }
                }
            }
            ActionRow(stat = d?.stat ?: video.stat, bvid = video.bvid)
            HorizontalDivider()

            // 三页滑动：简介 / 评论 / 相关（右滑切换）。
            PrimaryTabRow(selectedTabIndex = pagerState.currentPage) {
                DETAIL_TABS.forEachIndexed { i, label ->
                    Tab(
                        selected = pagerState.currentPage == i,
                        onClick = { scope.launch { pagerState.animateScrollToPage(i) } },
                        text = { Text(label) },
                    )
                }
            }
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
            ) { page ->
                when (page) {
                    0 -> IntroPage(d)
                    1 -> CommentsPage(
                        container = container,
                        replies = replies,
                        loading = replyLoading,
                        ended = replyEnd,
                        oid = d?.aid ?: video.aid,
                        nextCursor = replyNext,
                        onAppend = { list, next, end ->
                            replies = (replies + list).distinctBy { it.rpid }
                            replyNext = next
                            replyEnd = end
                        },
                        onLoading = { replyLoading = it },
                    )
                    2 -> RelatedPage(
                        related = related,
                        onOpen = onOpenVideo,
                    )
                }
            }
        }
    }
}

/** 操作栏：点赞/投币/收藏计数展示 + 分享（系统分享面板，真实可用）。 */
@Composable
private fun ActionRow(stat: com.pilinara.api.BiliStat, bvid: String) {
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActionChip(icon = { Icon(Icons.Filled.ThumbUp, null, Modifier.size(18.dp)) }, text = stat.like.toWan())
        ActionChip(icon = { Icon(Icons.Outlined.MonetizationOn, null, Modifier.size(18.dp)) }, text = stat.coin.toWan())
        ActionChip(icon = { Icon(Icons.Filled.Star, null, Modifier.size(18.dp)) }, text = stat.favorite.toWan())
        IconButton(onClick = {
            val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(android.content.Intent.EXTRA_TEXT, "https://www.bilibili.com/video/$bvid")
            }
            context.startActivity(android.content.Intent.createChooser(intent, "分享"))
        }) {
            Icon(Icons.Filled.Share, contentDescription = "分享")
        }
    }
}

@Composable
private fun ActionChip(icon: @Composable () -> Unit, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        icon()
        Text(text, style = MaterialTheme.typography.labelSmall)
    }
}

/** 简介页：描述 + 分 P 列表。 */
@Composable
private fun IntroPage(d: ViewData?) {
    if (d == null) {
        LoadingBox()
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (d.desc.isNotEmpty()) {
            item { Text(d.desc, style = MaterialTheme.typography.bodyMedium) }
        }
        if (d.pages.size > 1) {
            item {
                Text("分 P（${d.pages.size}）", style = MaterialTheme.typography.titleSmall)
            }
            items(d.pages) { p ->
                Text(
                    "P${p.page}  ${p.part.ifEmpty { "第 ${p.page} 集" }}",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 2.dp),
                )
            }
        }
    }
}

/** 相关页：推荐视频列表，点击切换详情。 */
@Composable
private fun RelatedPage(
    related: List<BiliVideo>?,
    onOpen: (BiliVideo) -> Unit,
) {
    if (related == null) {
        LoadingBox()
        return
    }
    if (related.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("暂无相关推荐", style = MaterialTheme.typography.labelSmall)
        }
        return
    }
    LazyColumn(contentPadding = PaddingValues(12.dp)) {
        items(related, key = { it.bvid }) { v ->
            Row(
                Modifier.fillMaxWidth()
                    .padding(vertical = 6.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { onOpen(v) }
                    .padding(6.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                AsyncImage(
                    model = BiliApi.image(v.pic),
                    contentDescription = null,
                    modifier = Modifier
                        .size(width = 120.dp, height = 68.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                )
                Column(Modifier.weight(1f)) {
                    Text(
                        v.title,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        "${v.owner.name} · ${v.stat.view.toWan()}播放",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
    }
}


