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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.pilinara.AppContainer
import com.pilinara.api.BiliApi
import com.pilinara.api.BiliVideo
import com.pilinara.api.ViewData
import com.pilinara.player.PlayerActivity
import com.pilinara.player.PlayRequest
import com.pilinara.player.buildBiliPlayRequest
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.toWan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** B 站视频详情：封面/简介/分 P 列表，点击任一 P 即取 playurl 进入播放器。 */
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

    LaunchedEffect(video.bvid) {
        runCatching { withContext(Dispatchers.IO) { container.api.view(video.bvid) } }
            .onSuccess { detail = it }
            .onFailure { error = it.message ?: "加载失败" }
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
                Text(
                    text = "加载失败：$error",
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(24.dp),
                )
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
        }
    }
}

private fun pickTitle(d: ViewData, page: Int, part: String?): String =
    if (d.pages.size > 1) "${d.title} - ${part ?: "P$page"}" else d.title

private suspend fun play(
    container: AppContainer,
    bvid: String,
    cid: Long,
    title: String,
    loadingCid: (Long?) -> Unit,
) {
    loadingCid(cid)
    runCatching {
        val qn = container.settings.preferQn.first()
        val cdn = container.settings.cdnNode.first()
        withContext(Dispatchers.IO) {
            buildBiliPlayRequest(container.api, bvid, cid, title, qn, cdn)
        }
    }.onSuccess { req: PlayRequest ->
        PlayerActivity.start(container.appContext, req)
    }.onFailure {
        // 错误在详情页之外以 Toast 呈现，避免静默失败。
        android.widget.Toast.makeText(container.appContext, "播放失败：${it.message}", android.widget.Toast.LENGTH_LONG).show()
    }
    loadingCid(null)
}
