package com.pilinara.ui.bili

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pilinara.AppContainer
import com.pilinara.api.BiliApi
import com.pilinara.api.BiliVideo
import com.pilinara.api.ReplyItem
import com.pilinara.api.ViewData
import com.pilinara.player.PlayerActivity
import com.pilinara.player.PlayRequest
import com.pilinara.player.buildBiliPlayRequest
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.runSuspendCatching
import com.pilinara.ui.common.toWan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** B 站视频详情：封面/简介/分 P 列表/评论区，点击任一 P 即取 playurl 进入播放器。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VideoDetailScreen(
    container: AppContainer,
    video: BiliVideo,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var detail by remember { mutableStateOf<ViewData?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loadingCid by remember { mutableStateOf<Long?>(null) }

    // 详情加载重试通过递增 retryKey 触发。
    var retryKey by remember { mutableStateOf(0) }
    // 详情失败且自动播放也失败时，回落到可重试的错误页（而非永远转圈）。
    var autoPlayFailed by remember { mutableStateOf(false) }

    // 评论分页状态。
    var replies by remember { mutableStateOf<List<ReplyItem>>(emptyList()) }
    var replyNext by remember { mutableStateOf(0L) }
    var replyEnd by remember { mutableStateOf(false) }
    var replyLoading by remember { mutableStateOf(false) }

    LaunchedEffect(video.bvid, retryKey) {
        error = null
        com.pilinara.ui.common.runSuspendCatching { withContext(Dispatchers.IO) { container.api.view(video.bvid) } }
            .onSuccess { detail = it }
            .onFailure { error = it.message ?: "加载失败" }
    }

    // 详情成功后拉第一页评论。
    LaunchedEffect(detail?.aid) {
        val aid = detail?.aid ?: return@LaunchedEffect
        replies = emptyList()
        replyNext = 0
        replyEnd = false
        loadReplies(container, aid, 0L, { replyLoading = it }, { replyNext = it }, { replyEnd = it }) {
            replies = (replies + it).distinctBy { r -> r.rpid }
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
        val d = detail
        if (d == null) {
            if (error != null) {
                // 热门/推荐卡片自带 cid：详情接口故障时不再挡播放，直接进播放器。
                if (video.cid > 0 && !autoPlayFailed) {
                    LaunchedEffect(Unit) {
                        play(
                            container, video.bvid, video.cid,
                            video.title.ifEmpty { "未知标题" },
                        ) { loadingCid = it }.onFailure { autoPlayFailed = true }
                    }
                    LoadingBox(Modifier.padding(padding))
                } else {
                    Column(
                        Modifier.fillMaxSize().padding(padding).padding(24.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "详情加载失败：$error",
                            color = MaterialTheme.colorScheme.error,
                        )
                        Button(onClick = { autoPlayFailed = false; retryKey++ }) { Text("重试") }
                    }
                }
            } else {
                LoadingBox(Modifier.padding(padding))
            }
            return@Scaffold
        }
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
        ) {
            item {
                Box(
                    Modifier.fillMaxWidth().aspectRatio(16f / 9f)
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                ) {
                    AsyncImage(
                        model = BiliApi.image(d.pic),
                        contentDescription = d.title,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                    Button(
                        onClick = {
                            scope.launch { play(container, d.bvid, d.cid, pickTitle(d, 1, null), loadingCid = { loadingCid = it }) }
                        },
                        modifier = Modifier.padding(12.dp).align(androidx.compose.ui.Alignment.BottomEnd),
                    ) {
                        Icon(Icons.Filled.PlayArrow, contentDescription = null)
                        Text("立即播放")
                    }
                }
            }
            item {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
                    Text(d.title, style = MaterialTheme.typography.titleLarge)
                    Text(
                        text = "${d.owner.name} · ${d.stat.view.toWan()}播放 · ${d.stat.danmaku.toWan()}弹幕",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                    if (d.desc.isNotEmpty()) {
                        Text(
                            d.desc,
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 4,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
            }
            if (d.pages.size > 1) {
                items(d.pages) { page ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 3.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .clickable(enabled = loadingCid == null) {
                                scope.launch {
                                    play(container, d.bvid, page.cid, pickTitle(d, page.page, page.part)) {
                                        loadingCid = it
                                    }
                                }
                            }
                            .padding(horizontal = 14.dp, vertical = 14.dp),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            "P${page.page}",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            page.part.ifEmpty { "第 ${page.page} 集" },
                            style = MaterialTheme.typography.titleMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
            item {
                Text(
                    "评论",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                )
            }
            if (replies.isEmpty() && replyLoading) {
                item {
                    Box(
                        Modifier.fillMaxWidth().padding(16.dp),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator() }
                }
            }
            items(replies, key = { it.rpid }) { r ->
                CommentItem(r)
            }
            item {
                // 触底加载更多；到底则显示「没有更多评论」。
                when {
                    replyEnd -> Text(
                        "没有更多评论了",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                    )
                    replies.isNotEmpty() -> {
                        Box(
                            Modifier.fillMaxWidth().padding(16.dp),
                            contentAlignment = Alignment.Center,
                        ) { CircularProgressIndicator() }
                        // 该 item 滚入可视区才组合，等价触底加载；组合期间不随状态重启。
                        LaunchedEffect(Unit) {
                            loadReplies(
                                container, d.aid, replyNext,
                                { replyLoading = it }, { replyNext = it }, { replyEnd = it },
                            ) { replies = (replies + it).distinctBy { r -> r.rpid } }
                        }
                    }
                }
            }
        }
    }
}

/** 单条主评论：头像 + 昵称 + 时间 + 点赞，子评论折叠为灰底块（最多 3 条）。 */
@Composable
private fun CommentItem(r: ReplyItem) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = BiliApi.image(r.member?.avatar.orEmpty()),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(36.dp).clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
            )
            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                Text(
                    r.member?.uname.orEmpty().ifEmpty { "匿名" },
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 1,
                )
                Text(
                    fmtCommentTime(r.ctime),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Filled.ThumbUp,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    r.like.toWan(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        }
        Text(
            r.content?.message.orEmpty(),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 6.dp, start = 46.dp),
        )
        val subs = r.replies.orEmpty()
        if (subs.isNotEmpty()) {
            Column(
                Modifier.padding(top = 6.dp, start = 46.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                    .padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                subs.take(3).forEach { sub ->
                    Text(
                        buildString {
                            append(sub.member?.uname.orEmpty().ifEmpty { "匿名" })
                            append("：")
                            append(sub.content?.message.orEmpty())
                        },
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (r.rcount > subs.size) {
                    Text(
                        "共 ${r.rcount} 条回复",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
    }
}

private fun fmtCommentTime(unixSec: Long): String {
    if (unixSec <= 0) return ""
    val diff = System.currentTimeMillis() / 1000 - unixSec
    return when {
        diff < 60 -> "刚刚"
        diff < 3600 -> "${diff / 60}分钟前"
        diff < 86400 -> "${diff / 3600}小时前"
        diff < 86400L * 30 -> "${diff / 86400}天前"
        else -> {
            val cal = java.util.Calendar.getInstance().apply { timeInMillis = unixSec * 1000 }
            "%d-%02d-%02d".format(
                cal.get(java.util.Calendar.YEAR),
                cal.get(java.util.Calendar.MONTH) + 1,
                cal.get(java.util.Calendar.DAY_OF_MONTH),
            )
        }
    }
}

/** 拉一页评论；失败静默（评论区故障不应影响主内容），失败时视为到底避免无限重试。 */
private suspend fun loadReplies(
    container: AppContainer,
    aid: Long,
    next: Long,
    setLoading: (Boolean) -> Unit,
    setNext: (Long) -> Unit,
    setEnd: (Boolean) -> Unit,
    append: (List<ReplyItem>) -> Unit,
) {
    setLoading(true)
    runSuspendCatching {
        withContext(Dispatchers.IO) { container.api.replies(aid, mode = 3, next = next) }
    }.onSuccess { page ->
        val list = page.replies.orEmpty()
        if (list.isEmpty() || page.cursor?.isEnd == true) {
            setEnd(true)
        } else {
            setNext(page.cursor?.next ?: next + 1)
            append(list)
        }
    }.onFailure { setEnd(true) }
    setLoading(false)
}

private fun pickTitle(d: ViewData, page: Int, part: String?): String =
    if (d.pages.size > 1) "${d.title} - ${part ?: "P$page"}" else d.title

private suspend fun play(
    container: AppContainer,
    bvid: String,
    cid: Long,
    title: String,
    loadingCid: (Long?) -> Unit,
): Result<PlayRequest> {
    loadingCid(cid)
    val result = com.pilinara.ui.common.runSuspendCatching {
        val qn = container.settings.preferQn.first()
        val cdn = container.settings.cdnNode.first()
        val roaming = container.settings.roamingServer.first()
        val hiRes = container.settings.hiResAudio.first()
        withContext(Dispatchers.IO) {
            buildBiliPlayRequest(container.api, bvid, cid, title, qn, cdn, roaming, hiRes)
        }
    }
    result.onSuccess { req: PlayRequest ->
        PlayerActivity.start(container.appContext, req)
    }.onFailure {
        // 错误在详情页之外以 Toast 呈现，避免静默失败。
        android.widget.Toast.makeText(container.appContext, "播放失败：${it.message}", android.widget.Toast.LENGTH_LONG).show()
    }
    loadingCid(null)
    return result
}
