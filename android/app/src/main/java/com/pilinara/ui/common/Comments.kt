package com.pilinara.ui.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pilinara.AppContainer
import com.pilinara.api.BiliApi
import com.pilinara.api.ReplyItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 评论页：主楼列表 + 触底翻页。视频详情 / 番剧（源匹配 B 站）共用。
 * @param oid 评论区 oid：视频是 aid，番剧是 media_id（接口 type 均为 1）。
 */
@Composable
fun CommentsPage(
    container: AppContainer,
    replies: List<ReplyItem>,
    loading: Boolean,
    ended: Boolean,
    oid: Long,
    nextCursor: Long,
    onAppend: (List<ReplyItem>, Long, Boolean) -> Unit,
    onLoading: (Boolean) -> Unit,
) {
    LazyColumn {
        if (replies.isEmpty() && loading) {
            item {
                Box(
                    Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) { CircularProgressIndicator() }
            }
        }
        items(replies, key = { it.rpid }) { r -> CommentItem(r) }
        item {
            when {
                ended -> Text(
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
                    // 该 item 滚入可视区才组合，等价触底加载；游标变化续页。
                    LaunchedEffect(nextCursor) {
                        loadReplies(
                            container, oid, nextCursor,
                            onLoading,
                            { end -> if (end) onAppend(emptyList(), nextCursor, true) },
                        ) { list, next -> onAppend(list, next, false) }
                    }
                }
            }
        }
    }
}

/** 单条主评论：头像 + 昵称 + 时间 + 点赞，子评论折叠为灰底块（最多 3 条）。 */
@Composable
fun CommentItem(r: ReplyItem) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = BiliApi.image(r.member?.avatar.orEmpty()),
                contentDescription = null,
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

fun fmtCommentTime(unixSec: Long): String {
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
suspend fun loadReplies(
    container: AppContainer,
    oid: Long,
    next: Long,
    setLoading: (Boolean) -> Unit,
    setEnd: (Boolean) -> Unit,
    append: (List<ReplyItem>, Long) -> Unit,
) {
    setLoading(true)
    runSuspendCatching {
        withContext(Dispatchers.IO) { container.api.replies(oid, mode = 3, next = next) }
    }.onSuccess { page ->
        val list = page.replies.orEmpty()
        if (list.isEmpty() || page.cursor?.isEnd == true) {
            setEnd(true)
        } else {
            append(list, page.cursor?.next ?: next + 1)
        }
    }.onFailure { setEnd(true) }
    setLoading(false)
}
