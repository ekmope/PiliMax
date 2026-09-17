package com.pilinara.player

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
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
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PictureInPicture
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.filled.ScreenRotation
import androidx.compose.material.icons.filled.Tune
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import androidx.media3.ui.PlayerView
import com.pilinara.PiliApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** 播放请求：由首页/详情/源页面构造，序列化为 JSON 经 Intent 传递。 */
@Serializable
data class PlayRequest(
    val title: String,
    val videoUrl: String,
    val audioUrl: String? = null,
    /** progressive | hls | dash。 */
    val streamType: String = "progressive",
    /** B 站视频 cid；> 0 时自动加载弹幕。 */
    val cid: Long = 0,
    val positionMs: Long = 0,
    val headers: Map<String, String> = emptyMap(),
)

class PlayerActivity : ComponentActivity() {

    private val json = Json { ignoreUnknownKeys = true }
    private var controller: MediaController? = null

    @UnstableApi
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val request = requireNotNull(parseRequest(intent)) { "缺少播放参数" }

        val token = SessionToken(this, android.content.ComponentName(this, PlaybackService::class.java))
        val future = MediaController.Builder(this, token).buildAsync()
        future.addListener({
            val c = future.get()
            controller = c
            prepareAndPlay(c, request)
        }, ContextCompat.getMainExecutor(this))

        setContent {
            val container = (application as PiliApplication).container

            val audioOnlyDefault by container.settings.audioOnly.collectAsState(false)
            val danmakuEnabled by container.settings.danmakuEnabled.collectAsState(true)
            val mergeWindow by container.settings.danmakuMergeWindow.collectAsState(10_000L)
            val danmakuOpacity by container.settings.danmakuOpacity.collectAsState(0.82f)
            val danmakuScale by container.settings.danmakuScale.collectAsState(1.0f)
            val defaultSpeed by container.settings.defaultSpeed.collectAsState(1.0f)

            var danmakuList by remember { mutableStateOf<List<Danmaku>>(emptyList()) }
            var danmakuVisible by remember { mutableStateOf(true) }
            var audioOnly by remember { mutableStateOf(audioOnlyDefault) }

            LaunchedEffect(request.cid, danmakuEnabled) {
                if (request.cid > 0 && danmakuEnabled) {
                    danmakuList = loadDanmaku(request.cid, mergeWindow)
                } else {
                    danmakuList = emptyList()
                }
            }

            PlayerScreen(
                title = request.title,
                controllerProvider = { controller },
                onBack = { finish() },
                onPip = { enterPip() },
                onToggleOrientation = { toggleOrientation() },
                defaultSpeed = defaultSpeed,
                danmakuEnabled = danmakuEnabled,
                danmakuVisible = danmakuVisible,
                onToggleDanmaku = { danmakuVisible = !danmakuVisible },
                danmakuList = danmakuList,
                danmakuOpacity = danmakuOpacity,
                danmakuScale = danmakuScale,
                audioOnly = audioOnly,
                onToggleAudioOnly = { enable ->
                    audioOnly = enable
                    val c = controller ?: return@PlayerScreen
                    c.trackSelectionParameters = c.trackSelectionParameters.buildUpon()
                        .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, enable)
                        .build()
                },
                onBrightness = { v -> setBrightness(v) },
                onVolume = { v -> setVolume(v) },
                currentBrightness = { currentBrightness() },
                pipMode = pipMode,
            )
        }
    }

    private fun currentBrightness(): Float {
        val v = window.attributes.screenBrightness
        return if (v in 0f..1f) v else 0.5f
    }

    private fun parseRequest(intent: Intent): PlayRequest? =
        intent.getStringExtra(EXTRA_REQUEST)?.let {
            json.decodeFromString(PlayRequest.serializer(), it)
        }

    private fun prepareAndPlay(c: MediaController, request: PlayRequest) {
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
                    .setArtworkUri(null)
                    .setExtras(extras)
                    .build(),
            )
            .build()
        // 请求头经 PlaybackHeaderStore + ResolvingDataSource 按 URL 注入。
        PlaybackHeaderStore.set(listOfNotNull(request.videoUrl, request.audioUrl), request.headers)
        c.setMediaItem(item, request.positionMs)
        c.playWhenReady = true
        // 默认倍速在 prepare 前设置，首帧即以目标速率渲染（DataStore 读取是毫秒级本地 IO）。
        val app = application as PiliApplication
        val defaultSpeed = kotlinx.coroutines.runBlocking {
            app.container.settings.defaultSpeed.first()
        }
        if (defaultSpeed != 1f) c.setPlaybackSpeed(defaultSpeed)
        c.prepare()
    }

    private suspend fun loadDanmaku(cid: Long, mergeWindowMs: Long): List<Danmaku> =
        withContext(Dispatchers.IO) {
            val api = (application as PiliApplication).container.api
            val out = ArrayList<Danmaku>()
            runCatching {
                api.ensureBuvid()
                for (i in 1..20) {
                    val bytes = api.danmakuSegment(cid, i)
                    if (bytes.size < 64) break
                    val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                    val arr = NativeCoreDanmaku.parseSegSo(b64, mergeWindowMs)
                    if (arr.isEmpty()) break
                    out.addAll(arr)
                }
            }
            if (out.isEmpty()) {
                runCatching {
                    val xml = api.danmakuXml(cid)
                    out.addAll(NativeCoreDanmaku.parseXml(xml, mergeWindowMs))
                }
            }
            out.sortedBy { it.t }
        }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.hasSystemFeature(
                android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE,
            )
        ) {
            runCatching {
                enterPictureInPictureMode(PictureInPictureParams.Builder().build())
            }
        }
    }

    private var landscape = false
    private fun toggleOrientation() {
        landscape = !landscape
        requestedOrientation = if (landscape) {
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    private fun setBrightness(v: Float) {
        val params = window.attributes
        params.screenBrightness = v.coerceIn(0.02f, 1f)
        window.attributes = params
    }

    private fun setVolume(v: Float) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        am.setStreamVolume(
            AudioManager.STREAM_MUSIC,
            (v.coerceIn(0f, 1f) * max).toInt(),
            0,
        )
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (controller?.isPlaying == true) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMode = isInPictureInPictureMode
    }

    private var pipMode: Boolean by mutableStateOf(false)

    override fun onDestroy() {
        controller?.release()
        controller = null
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_REQUEST = "play_request"

        fun start(context: Context, request: PlayRequest) {
            val text = Json.encodeToString(PlayRequest.serializer(), request)
            context.startActivity(
                Intent(context, PlayerActivity::class.java).putExtra(EXTRA_REQUEST, text),
            )
        }
    }
}

/** 对 NativeCore 弹幕接口的薄封装（集中 JSON 反序列化）。 */
private object NativeCoreDanmaku {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseSegSo(b64: String, mergeWindowMs: Long): List<Danmaku> {
        val s = com.pilinara.core.NativeCore.parseDanmakuSegSo(b64, mergeWindowMs)
        return json.decodeFromString(ListSerializer(Danmaku.serializer()), s)
    }

    fun parseXml(xml: String, mergeWindowMs: Long): List<Danmaku> {
        val s = com.pilinara.core.NativeCore.parseDanmakuXml(xml, mergeWindowMs)
        return json.decodeFromString(ListSerializer(Danmaku.serializer()), s)
    }
}

@UnstableApi
@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun PlayerScreen(
    title: String,
    controllerProvider: () -> MediaController?,
    onBack: () -> Unit,
    onPip: () -> Unit,
    onToggleOrientation: () -> Unit,
    defaultSpeed: Float,
    danmakuEnabled: Boolean,
    danmakuVisible: Boolean,
    onToggleDanmaku: () -> Unit,
    danmakuList: List<Danmaku>,
    danmakuOpacity: Float,
    danmakuScale: Float,
    audioOnly: Boolean,
    onToggleAudioOnly: (Boolean) -> Unit,
    onBrightness: (Float) -> Unit,
    onVolume: (Float) -> Unit,
    currentBrightness: () -> Float,
    pipMode: Boolean,
) {
    val context = LocalContext.current
    val audioManager = remember {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    var isPlaying by remember { mutableStateOf(false) }
    var isBuffering by remember { mutableStateOf(true) }
    var duration by remember { mutableStateOf(0L) }
    var position by remember { mutableStateOf(0L) }
    var controlsVisible by remember { mutableStateOf(true) }
    var scrubTarget by remember { mutableStateOf<Long?>(null) }
    var speedMenu by remember { mutableStateOf(false) }
    var moreMenu by remember { mutableStateOf(false) }
    var gestureHint by remember { mutableStateOf<String?>(null) }
    var speed by remember { mutableFloatStateOf(defaultSpeed) }

    LaunchedEffect(gestureHint) {
        if (gestureHint != null) {
            delay(800)
            gestureHint = null
        }
    }

    // 只听模式开关（含「默认只听」设置）：控制器异步就绪后轮询一次再应用。
    LaunchedEffect(audioOnly) {
        var c = controllerProvider()
        while (c == null) {
            delay(100)
            c = controllerProvider()
        }
        c.trackSelectionParameters = c.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, audioOnly)
            .build()
    }

    // 轮询进度。
    LaunchedEffect(Unit) {
        while (true) {
            val c = controllerProvider()
            if (c != null) {
                position = c.currentPosition
                if (c.duration > 0) duration = c.duration
                isBuffering = c.playbackState == Player.STATE_BUFFERING
            }
            delay(500)
        }
    }

    // 播放状态监听。
    DisposableListener(controllerProvider) { c ->
        isPlaying = c.isPlaying
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { controlsVisible = !controlsVisible },
                    onDoubleTap = { offset ->
                        val c = controllerProvider() ?: return@detectTapGestures
                        val delta = if (offset.x < size.width / 3f) -10_000L else 10_000L
                        c.seekTo((c.currentPosition + delta).coerceAtLeast(0L))
                        gestureHint = if (delta < 0) "快退 10s" else "快进 10s"
                    },
                    onLongPress = {
                        controllerProvider()?.setPlaybackSpeed(2f)
                        gestureHint = "2 倍速"
                    },
                    onPress = {
                        awaitRelease()
                        controllerProvider()?.setPlaybackSpeed(speed)
                        gestureHint = null
                    },
                )
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { scrubTarget = controllerProvider()?.currentPosition ?: 0L },
                    onDragEnd = {
                        scrubTarget?.let { controllerProvider()?.seekTo(it) }
                        scrubTarget = null
                    },
                    onDragCancel = { scrubTarget = null },
                ) { change, dragAmount ->
                    change.consume()
                    val total = duration.takeIf { it > 0 } ?: return@detectHorizontalDragGestures
                    val target = (scrubTarget ?: 0L) + (dragAmount / size.width * total).toLong()
                    scrubTarget = target.coerceIn(0L, total)
                }
            }
            .pointerInput(Unit) {
                var verticalStart = 0f
                var isBrightnessSide = false
                detectVerticalDragGestures(
                    onDragStart = { offset ->
                        if (offset.x < size.width / 2f) {
                            isBrightnessSide = true
                            verticalStart = currentBrightness()
                        } else {
                            isBrightnessSide = false
                            verticalStart = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() /
                                audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        }
                    },
                ) { change, dragAmount ->
                    change.consume()
                    val next = (verticalStart - dragAmount / size.height).coerceIn(0f, 1f)
                    if (isBrightnessSide) onBrightness(next) else onVolume(next)
                    gestureHint = if (isBrightnessSide) "亮度 ${(next * 100).toInt()}%"
                    else "音量 ${(next * 100).toInt()}%"
                }
            },
    ) {
        // 视频画面。
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    controllerProvider()?.let { player = it }
                    // 控制器可能晚于视图创建。
                    post { controllerProvider()?.let { player = it } }
                }
            },
            update = { view ->
                if (view.player !== controllerProvider()) {
                    view.player = controllerProvider()
                }
            },
        )

        // 弹幕层（音频模式下隐藏）。
        if (!audioOnly) {
            DanmakuLayer(
                danmaku = danmakuList,
                enabled = danmakuEnabled && danmakuVisible,
                opacity = danmakuOpacity,
                scale = danmakuScale,
                positionProvider = { scrubTarget ?: controllerProvider()?.currentPosition ?: 0L },
                isPlayingProvider = { controllerProvider()?.isPlaying == true },
            )
        }

        if (isBuffering) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center).size(48.dp),
                color = Color.White,
            )
        }

        gestureHint?.let {
            Text(
                text = it,
                color = Color.White,
                modifier = Modifier.align(Alignment.Center)
                    .background(Color(0x88000000), MaterialTheme.shapes.medium)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

        // 控制栏（画中画时隐藏）。
        AnimatedVisibility(
            visible = controlsVisible && !pipMode,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize(),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color(0x66000000))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回", tint = Color.White)
                    }
                    Text(
                        text = title,
                        color = Color.White,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(onClick = onPip) {
                        Icon(Icons.Filled.PictureInPicture, contentDescription = "画中画", tint = Color.White)
                    }
                    IconButton(onClick = onToggleOrientation) {
                        Icon(Icons.Filled.ScreenRotation, contentDescription = "横竖屏", tint = Color.White)
                    }
                    Box {
                        IconButton(onClick = { moreMenu = true }) {
                            Icon(Icons.Filled.Tune, contentDescription = "更多", tint = Color.White)
                        }
                        DropdownMenu(expanded = moreMenu, onDismissRequest = { moreMenu = false }) {
                            if (danmakuEnabled) {
                                DropdownMenuItem(
                                    text = { Text(if (danmakuVisible) "关闭弹幕" else "开启弹幕") },
                                    onClick = {
                                        onToggleDanmaku()
                                        moreMenu = false
                                    },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text(if (audioOnly) "关闭只听模式" else "只听模式") },
                                onClick = {
                                    onToggleAudioOnly(!audioOnly)
                                    moreMenu = false
                                },
                            )
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = {
                        val c = controllerProvider() ?: return@IconButton
                        c.seekTo((c.currentPosition - 10_000L).coerceAtLeast(0L))
                    }) {
                        Icon(Icons.Filled.RotateLeft, contentDescription = "快退", tint = Color.White, modifier = Modifier.size(40.dp))
                    }
                    IconButton(
                        onClick = {
                            val c = controllerProvider() ?: return@IconButton
                            if (c.isPlaying) c.pause() else c.play()
                        },
                        modifier = Modifier.padding(horizontal = 32.dp),
                    ) {
                        Icon(
                            if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = "播放/暂停",
                            tint = Color.White,
                            modifier = Modifier.size(56.dp),
                        )
                    }
                    IconButton(onClick = {
                        val c = controllerProvider() ?: return@IconButton
                        c.seekTo(c.currentPosition + 10_000L)
                    }) {
                        Icon(Icons.Filled.RotateRight, contentDescription = "快进", tint = Color.White, modifier = Modifier.size(40.dp))
                    }
                    Box {
                        IconButton(onClick = { speedMenu = true }) {
                            Icon(Icons.Filled.MoreHoriz, contentDescription = "倍速", tint = Color.White)
                        }
                        DropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                            listOf(0.75f, 1f, 1.25f, 1.5f, 2f, 3f).forEach { sp ->
                                DropdownMenuItem(
                                    text = { Text(if (sp == 1f) "倍速：正常" else "倍速：${sp}x") },
                                    onClick = {
                                        speed = sp
                                        controllerProvider()?.setPlaybackSpeed(sp)
                                        speedMenu = false
                                    },
                                )
                            }
                        }
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        formatTime(scrubTarget ?: position),
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Slider(
                        value = (scrubTarget ?: position).toFloat(),
                        onValueChange = { scrubTarget = it.toLong() },
                        onValueChangeFinished = {
                            scrubTarget?.let { controllerProvider()?.seekTo(it) }
                            scrubTarget = null
                        },
                        valueRange = 0f..(duration.coerceAtLeast(1L)).toFloat(),
                        modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                    )
                    Text(
                        formatTime(duration),
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
    }
}

/** 绑定 Player.Listener 到控制器（控制器是异步就绪的）。 */
@Composable
private fun DisposableListener(
    controllerProvider: () -> MediaController?,
    onState: (MediaController) -> Unit,
) {
    androidx.compose.runtime.DisposableEffect(Unit) {
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var listener: Player.Listener? = null
        var attached: Player? = null
        val poll = object : Runnable {
            override fun run() {
                val c = controllerProvider()
                if (c != null && attached !== c) {
                    attached = c
                    val l = object : Player.Listener {
                        override fun onIsPlayingChanged(isPlaying: Boolean) {
                            onState(c)
                        }

                        override fun onPlaybackStateChanged(playbackState: Int) {
                            onState(c)
                        }
                    }
                    listener = l
                    c.addListener(l)
                    onState(c)
                } else {
                    handler.postDelayed(this, 250)
                }
            }
        }
        handler.post(poll)
        onDispose {
            handler.removeCallbacks(poll)
            attached?.let { p -> listener?.let { p.removeListener(it) } }
        }
    }
}

private fun formatTime(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}
