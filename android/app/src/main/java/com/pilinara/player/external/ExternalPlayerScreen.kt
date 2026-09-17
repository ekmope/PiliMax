package com.pilinara.player.external

import android.util.Base64
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.pilinara.AppContainer
import com.pilinara.player.Danmaku
import com.pilinara.player.DanmakuLayer
import com.pilinara.player.PlayRequest
import com.pilinara.plugin.api.ExternalPlayerCore
import com.pilinara.plugin.api.PlaySpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * VLC / MPV 等外部内核的播放界面：SurfaceView + 自有控制层 + 弹幕层。
 * 内核实例在离开组合时释放。
 */
@Composable
fun ExternalPlayerScreen(
    container: AppContainer,
    coreId: PlayerCoreManager.CoreId,
    request: PlayRequest,
    onBack: () -> Unit,
    onFallbackMedia3: () -> Unit,
    onBrightness: (Float) -> Unit,
    onSetVolumeRatio: (Float) -> Unit,
) {
    val settings = container.settings
    val danmakuEnabled by settings.danmakuEnabled.collectAsState(true)
    val danmakuOpacity by settings.danmakuOpacity.collectAsState(0.82f)
    val danmakuScale by settings.danmakuScale.collectAsState(1.0f)
    val decodeMode by settings.decodeMode.collectAsState("auto")
    val defaultSpeed by settings.defaultSpeed.collectAsState(1f)

    var isPlaying by remember { mutableStateOf(false) }
    var isBuffering by remember { mutableStateOf(true) }
    var duration by remember { mutableStateOf(0L) }
    var position by remember { mutableStateOf(request.positionMs) }
    var controlsVisible by remember { mutableStateOf(true) }
    var scrubTarget by remember { mutableStateOf<Long?>(null) }
    var errorMsg by remember { mutableStateOf<String?>(null) }
    var speedMenu by remember { mutableStateOf(false) }
    var speed by remember { mutableFloatStateOf(defaultSpeed) }
    var danmakuList by remember { mutableStateOf<List<Danmaku>>(emptyList()) }

    val core = remember {
        container.playerCores.create(coreId)
    }

    LaunchedEffect(request.cid, danmakuEnabled) {
        danmakuList = if (request.cid > 0 && danmakuEnabled) {
            loadExternalDanmaku(container, request.cid, settings.danmakuMergeWindow.first())
        } else {
            emptyList()
        }
    }

    androidx.compose.runtime.DisposableEffect(Unit) {
        onDispose { core.release() }
    }

    LaunchedEffect(Unit) {
        core.attach(container.appContext)
        core.setCallback(object : ExternalPlayerCore.Callback {
            override fun onReady() {
                isBuffering = false
            }

            override fun onBuffering() {
                isBuffering = true
            }

            override fun onEnded() {
                isPlaying = false
            }

            override fun onError(message: String) {
                isBuffering = false
                errorMsg = message
            }

            override fun onDuration(durationMs: Long) {
                if (durationMs > 0) duration = durationMs
            }

            override fun onPosition(positionMs: Long) {
                position = positionMs
            }

            override fun onPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        })
        core.open(
            PlaySpec(
                videoUrl = request.videoUrl,
                audioUrl = request.audioUrl,
                title = request.title,
                headers = request.headers,
                startPositionMs = request.positionMs,
                hardwareDecode = decodeMode != "soft",
                rate = defaultSpeed,
            ),
        )
    }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { controlsVisible = !controlsVisible },
                    onDoubleTap = { offset ->
                        val delta = if (offset.x < size.width / 3f) -10_000L else 10_000L
                        core.seekTo((position + delta).coerceAtLeast(0L))
                    },
                )
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { scrubTarget = position },
                    onDragEnd = {
                        scrubTarget?.let { core.seekTo(it) }
                        scrubTarget = null
                    },
                    onDragCancel = { scrubTarget = null },
                ) { change, dragAmount ->
                    change.consume()
                    val total = duration.takeIf { it > 0 } ?: return@detectHorizontalDragGestures
                    val target = (scrubTarget ?: 0L) +
                        (dragAmount / size.width * total).toLong()
                    scrubTarget = target.coerceIn(0L, total)
                }
            },
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                SurfaceView(ctx).apply {
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) {
                            val f = holder.surfaceFrame
                            core.setSurface(holder.surface, f.width(), f.height())
                        }

                        override fun surfaceChanged(
                            holder: SurfaceHolder, w: Int, h: Int, format: Int,
                        ) {
                            core.setSurface(holder.surface, w.coerceAtLeast(1), h.coerceAtLeast(1))
                        }

                        override fun surfaceDestroyed(holder: SurfaceHolder) {
                            core.setSurface(null, 0, 0)
                        }
                    })
                }
            },
        )

        DanmakuLayer(
            danmaku = danmakuList,
            enabled = danmakuEnabled,
            opacity = danmakuOpacity,
            scale = danmakuScale,
            positionProvider = { scrubTarget ?: position },
            isPlayingProvider = { isPlaying },
        )

        if (isBuffering && errorMsg == null) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center).size(48.dp),
                color = Color.White,
            )
        }

        errorMsg?.let { msg ->
            Column(
                Modifier.align(Alignment.Center).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(msg, color = Color.White)
                Button(onClick = onFallbackMedia3) { Text("改用内置 Media3 播放") }
            }
        }

        AnimatedVisibility(
            visible = controlsVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize(),
        ) {
            Column(
                modifier = Modifier.fillMaxSize()
                    .background(Color(0x66000000))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回", tint = Color.White,
                        )
                    }
                    Text(
                        text = request.title,
                        color = Color.White,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        modifier = Modifier.weight(1f),
                    )
                    Box {
                        IconButton(onClick = { speedMenu = true }) {
                            Text(
                                if (speed == 1f) "倍速" else "${speed}x",
                                color = Color.White,
                            )
                        }
                        DropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                            listOf(0.75f, 1f, 1.25f, 1.5f, 2f, 3f).forEach { sp ->
                                DropdownMenuItem(
                                    text = { Text(if (sp == 1f) "正常" else "${sp}x") },
                                    onClick = {
                                        speed = sp
                                        core.setRate(sp)
                                        speedMenu = false
                                    },
                                )
                            }
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = { core.seekTo((position - 10_000L).coerceAtLeast(0L)) }) {
                        Icon(
                            Icons.Filled.RotateLeft,
                            contentDescription = "快退", tint = Color.White,
                            modifier = Modifier.size(40.dp),
                        )
                    }
                    IconButton(
                        onClick = { if (isPlaying) core.pause() else core.play() },
                        modifier = Modifier.padding(horizontal = 32.dp),
                    ) {
                        Icon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = "播放/暂停", tint = Color.White,
                            modifier = Modifier.size(56.dp),
                        )
                    }
                    IconButton(onClick = { core.seekTo(position + 10_000L) }) {
                        Icon(
                            Icons.Filled.RotateRight,
                            contentDescription = "快进", tint = Color.White,
                            modifier = Modifier.size(40.dp),
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        formatExtTime(scrubTarget ?: position),
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Slider(
                        value = (scrubTarget ?: position).toFloat(),
                        onValueChange = { scrubTarget = it.toLong() },
                        onValueChangeFinished = {
                            scrubTarget?.let { p -> core.seekTo(p) }
                            scrubTarget = null
                        },
                        valueRange = 0f..(duration.coerceAtLeast(1L)).toFloat(),
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    )
                    Text(
                        formatExtTime(duration),
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}

private suspend fun loadExternalDanmaku(
    container: AppContainer,
    cid: Long,
    mergeWindowMs: Long,
): List<Danmaku> = withContext(Dispatchers.IO) {
    val json = Json { ignoreUnknownKeys = true }
    val out = ArrayList<Danmaku>()
    runCatching {
        container.api.ensureBuvid()
        for (i in 1..20) {
            val bytes = container.api.danmakuSegment(cid, i)
            if (bytes.size < 64) break
            val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
            val s = com.pilinara.core.NativeCore.parseDanmakuSegSo(b64, mergeWindowMs)
            val arr = json.decodeFromString(ListSerializer(Danmaku.serializer()), s)
            if (arr.isEmpty()) break
            out.addAll(arr)
        }
    }
    if (out.isEmpty()) {
        runCatching {
            val xml = container.api.danmakuXml(cid)
            val s = com.pilinara.core.NativeCore.parseDanmakuXml(xml, mergeWindowMs)
            out.addAll(json.decodeFromString(ListSerializer(Danmaku.serializer()), s))
        }
    }
    out.sortedBy { it.t }
}

private fun formatExtTime(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}
