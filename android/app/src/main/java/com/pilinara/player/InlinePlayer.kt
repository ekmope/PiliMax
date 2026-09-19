package com.pilinara.player

import android.content.Context
import android.os.Bundle
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.pilinara.AppContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext

/**
 * 内联播放器：嵌入详情页顶部（bilipai / B 站官方 App 式布局）。
 *
 * 与全屏 PlayerActivity 的区别：无独立控制层/手势层，只保留
 * 播放/暂停 + 全屏按钮；弹幕层照常叠加。生命周期随组合：
 * 离开详情页即释放，避免后台偷跑解码耗电。
 */
@UnstableApi
@Composable
fun InlinePlayer(
    container: AppContainer,
    request: PlayRequest,
    onFullscreen: (PlayRequest) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var player by remember { mutableStateOf<ExoPlayer?>(null) }
    var playing by remember { mutableStateOf(false) }
    var buffering by remember { mutableStateOf(true) }
    var danmakuList by remember { mutableStateOf<List<Danmaku>>(emptyList()) }
    var actualRequest by remember { mutableStateOf(request) }
    val danmakuEnabled by container.settings.danmakuEnabled.collectAsState(true)
    val danmakuOpacity by container.settings.danmakuOpacity.collectAsState(0.82f)
    val danmakuScale by container.settings.danmakuScale.collectAsState(1.0f)

    DisposableEffect(Unit) {
        onDispose {
            player?.release()
            player = null
        }
    }

    // 拉取播放地址（按用户偏好清晰度/CDN），失败时回落到调用方给的地址。
    LaunchedEffect(request.bvid, request.cid) {
        val req = withContext(Dispatchers.IO) {
            runCatching {
                val weakNet = container.settings.weakNet.first()
                val qn = PlayerSettings.effectiveQn(container.settings.preferQn.first(), weakNet)
                val cdn = container.settings.cdnNode.first()
                val roaming = container.settings.roamingServer.first()
                val hiRes = container.settings.hiResAudio.first() && !weakNet
                buildBiliPlayRequest(
                    container.api, request.bvid, request.cid, request.title,
                    qn, cdn, roaming, hiRes,
                )
            }.getOrDefault(request)
        }
        // 设置快照在协程里读（DataStore 磁盘 IO 绝不阻塞主线程）。
        val snapshot = PlayerSettings.load(container.settings)
        val exo = runCatching {
            PlayerEngine.create(context.applicationContext, container, snapshot)
        }.getOrNull() ?: return@LaunchedEffect
        exo.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) { playing = isPlaying }
            override fun onPlaybackStateChanged(state: Int) {
                buffering = state == Player.STATE_BUFFERING
            }
        })
        player = exo
        actualRequest = req
        prepareAndPlayInline(exo, req)
        if (req.cid > 0 && danmakuEnabled) {
            danmakuList = runCatching {
                withContext(Dispatchers.IO) { loadDanmakuList(container, req.cid) }
            }.getOrDefault(emptyList())
        }
    }

    Box(modifier = modifier.background(Color.Black)) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    resizeMode = androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
            },
            update = { view -> view.player = player },
            modifier = Modifier.fillMaxSize(),
        )
        DanmakuLayer(
            danmaku = danmakuList,
            enabled = danmakuEnabled,
            opacity = danmakuOpacity,
            scale = danmakuScale,
            positionProvider = { player?.currentPosition ?: 0L },
            isPlayingProvider = { player?.isPlaying ?: false },
        )
        if (buffering) {
            CircularProgressIndicator(
                Modifier.align(Alignment.Center).size(40.dp),
                color = Color.White,
            )
        }
        Box(
            Modifier.align(Alignment.BottomEnd)
                .background(Color.Black.copy(alpha = 0.35f)),
        ) {
            Row {
                IconButton(onClick = {
                    val p = player ?: return@IconButton
                    if (p.isPlaying) p.pause() else p.play()
                }) {
                    Icon(
                        if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                        contentDescription = "播放/暂停",
                        tint = Color.White,
                    )
                }
                IconButton(onClick = { onFullscreen(actualRequest) }) {
                    Icon(
                        Icons.Filled.Fullscreen,
                        contentDescription = "全屏",
                        tint = Color.White,
                    )
                }
            }
        }
    }
}

private suspend fun loadDanmakuList(container: AppContainer, cid: Long): List<Danmaku> {
    val mergeWindow = container.settings.danmakuMergeWindow.first()
    val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
    val listSerializer = kotlinx.serialization.builtins.ListSerializer(Danmaku.serializer())
    return try {
        val bytes = container.api.danmakuSegment(cid, 1)
        val b64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        json.decodeFromString(
            listSerializer,
            com.pilinara.core.NativeCore.parseDanmakuSegSo(b64, mergeWindow),
        )
    } catch (_: Exception) {
        try {
            val xml = container.api.danmakuXml(cid)
            json.decodeFromString(
                listSerializer,
                com.pilinara.core.NativeCore.parseDanmakuXml(xml, mergeWindow),
            )
        } catch (_: Exception) {
            emptyList()
        }
    }
}

private fun prepareAndPlayInline(c: ExoPlayer, request: PlayRequest) {
    val extras = Bundle().apply {
        putString(PiliMediaSourceFactory.EXTRA_STREAM_TYPE, request.streamType)
        request.audioUrl?.let { putString(PiliMediaSourceFactory.EXTRA_AUDIO_URL, it) }
    }
    val item = MediaItem.Builder()
        .setMediaId(request.videoUrl)
        .setUri(request.videoUrl)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(request.title)
                .setExtras(extras)
                .build(),
        )
        .build()
    PlaybackHeaderStore.set(listOfNotNull(request.videoUrl, request.audioUrl), request.headers)
    c.setMediaItem(item, request.positionMs)
    c.playWhenReady = true
    c.prepare()
}

/** 内联 → 全屏：启动 PlayerActivity（其自身锁定横屏，返回后详情页不受影响）。 */
fun launchFullscreen(context: Context, request: PlayRequest) {
    PlayerActivity.start(context, request)
}
