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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.player.PlayRequest
import com.pilinara.player.PlayerActivity
import com.pilinara.source.SourceChannel
import com.pilinara.ui.common.ErrorBox
import com.pilinara.ui.common.LoadingBox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 第三方源详情：多线路 chips + 选集网格。
 * 播放时经选择器/嗅探拿到直链，按扩展名判定 HLS/DASH/普通流。
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
    var channels by remember { mutableStateOf<List<SourceChannel>>(emptyList()) }
    var channelIndex by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var resolving by remember { mutableStateOf<String?>(null) }

    // 追番（本地 + 可选同步 B 站）。
    val followed by container.sources.followed.collectAsState()
    val isFollowed = followed.any { it.subjectUrl == subjectUrl }
    var followBusy by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }

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
                LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                    item { ChannelChips(channels, channelIndex) { channelIndex = it } }
                    items(channel.episodes.chunked(3)) { rowItems ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
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
            }
        }
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
