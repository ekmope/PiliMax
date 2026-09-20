package com.pilinara.player

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
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.runtime.DisposableEffect
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
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.pilinara.PiliApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
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
    /** B 站视频 bvid；非空时播放器内可切换清晰度（重新拉 playurl）。 */
    val bvid: String = "",
    /** 实际选中的清晰度档位（用于播放器内清晰度菜单高亮）。 */
    val qn: Int = 0,
    val positionMs: Long = 0,
    val headers: Map<String, String> = emptyMap(),
    /** 封面图；「打开时手动播放」模式下先显示封面，点击才起播。 */
    val coverUrl: String = "",
)

class PlayerActivity : ComponentActivity() {

    private val json = Json { ignoreUnknownKeys = true }

    /** 进程内播放器（不再跨 Service 绑定 MediaController）。 */
    private var player: ExoPlayer? = null

    /** 当前播放请求（切换清晰度后更新，UI 读取 qn 高亮）。 */
    private var currentRequest by mutableStateOf<PlayRequest?>(null)

    /** 播放初始化失败信息；非 null 时渲染全屏错误页而非崩溃。 */
    private var fatalError by mutableStateOf<String?>(null)

    /** 播放器是否已就绪（设置快照读取 + ExoPlayer 构建完成）。 */
    private var ready by mutableStateOf(false)

    /** 是否走外部内核界面（设置快照读取完成后决定）。 */
    private var useExternal by mutableStateOf(false)

    /** 音轨兜底是否已用过：B 站 DASH 双轨合流中音轨 CDN 失败时，去音轨重试一次。 */
    private var audioFallbackUsed = false

    /** 播放偏好快照（协程中读取，播放全程不再阻塞主线程）。 */
    private var settingsSnapshot: PlayerSettings = PlayerSettings()

    @UnstableApi
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 全屏播放默认横屏（bilipai / 官方 App 行为）；内联播放器保持竖屏页内。
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val piliApp = application as PiliApplication

        val request = runCatching { requireNotNull(parseRequest(intent)) }.getOrNull()
        if (request == null) {
            setContent { PlayerFatalError("缺少播放参数", onBack = { finish() }) }
            return
        }
        currentRequest = request

        setContent {
            val container = (application as PiliApplication).container
            val fatal = fatalError
            when {
                fatal != null -> PlayerFatalError(fatal, onBack = { finish() })
                useExternal -> {
                    val req = currentRequest ?: return@setContent
                    com.pilinara.player.external.ExternalPlayerScreen(
                        container = container,
                        coreId = com.pilinara.player.external.PlayerCoreManager.CoreId
                            .ofSetting(settingsSnapshot.playerCore),
                        request = req,
                        onBack = { finish() },
                        onFallbackMedia3 = {
                            lifecycleScope.launch {
                                container.settings.setPlayerCore("media3")
                            }
                            // 直接就地重建内置播放器，避免 recreate() 重走整条初始化链。
                            useExternal = false
                            ready = false
                            lifecycleScope.launch { bootstrapMedia3(container, req) }
                        },
                        onBrightness = { v -> setBrightness(v) },
                        onSetVolumeRatio = { v -> setVolume(v) },
                    )
                }
                !ready -> Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White)
                }
                else -> {
                    val req = currentRequest
                    val p = player
                    if (req == null || p == null) {
                        PlayerFatalError("播放器状态异常", onBack = { finish() })
                        return@setContent
                    }
                    PlayerScreenHost(
                        container = container,
                        request = req,
                        player = p,
                        settings = settingsSnapshot,
                        loadDanmaku = { cid, window -> loadDanmaku(cid, window) },
                        onBack = { finish() },
                        onPip = { enterPip() },
                        onToggleOrientation = { toggleOrientation() },
                        onBrightness = { v -> setBrightness(v) },
                        onVolume = { v -> setVolume(v) },
                        currentBrightness = { currentBrightness() },
                        pipMode = pipMode,
                        currentQn = currentRequest?.qn ?: 0,
                        canSwitchQuality = req.bvid.isNotEmpty(),
                        onSwitchQuality = { qn -> switchQuality(qn) },
                        isLandscape = landscape,
                    )
                }
            }
        }

        // 全部初始化移入协程：设置快照读取（DataStore 磁盘 IO）绝不在主线程同步等待。
        // 这是 v0.4.12 之前「点播放即闪退」的头号根因（runBlocking 卡主线程触发系统杀进程）。
        lifecycleScope.launch {
            val snapshot = PlayerSettings.load(piliApp.container.settings)
            settingsSnapshot = snapshot

            // 外部内核分支：用户选择 VLC/MPV 且插件已安装时，直接挂载外部播放界面，
            // 不创建 ExoPlayer；未安装或加载失败则静默回落到内置 Media3。
            val selectedCore = com.pilinara.player.external.PlayerCoreManager.CoreId
                .ofSetting(snapshot.playerCore)
            if (selectedCore != com.pilinara.player.external.PlayerCoreManager.CoreId.MEDIA3 &&
                piliApp.container.playerCores.isInstalled(selectedCore)
            ) {
                useExternal = true
                return@launch
            }

            bootstrapMedia3(piliApp.container, request)
        }
    }

    /** 构建进程内 ExoPlayer 并开播。任何一步失败都落到错误页而不是闪退。 */
    @UnstableApi
    private fun bootstrapMedia3(container: com.pilinara.AppContainer, request: PlayRequest) {
        val exo = runCatching {
            PlayerEngine.create(applicationContext, container, settingsSnapshot)
        }.getOrElse {
            com.pilinara.CrashLog.write(applicationContext, Thread.currentThread(), it)
            fatalError = "播放器初始化失败：${it.message ?: it.javaClass.simpleName}"
            return
        }
        player = exo
        // 播放期错误（解码/网络/源）走 ExoPlayer 回调而非崩溃：落盘以便定位，界面给出错误页。
        exo.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                com.pilinara.CrashLog.write(applicationContext, Thread.currentThread(), error)
                val req = currentRequest
                // 双轨合流兜底：音轨 CDN 节点故障会拖垮整个 MergingMediaSource。
                // 去掉音轨以纯视频重试一次（无声但能播），而不是直接报错。
                if (!audioFallbackUsed && req != null && !req.audioUrl.isNullOrEmpty()) {
                    audioFallbackUsed = true
                    val pos = exo.currentPosition.takeIf { it > 0 } ?: req.positionMs
                    val stripped = req.copy(audioUrl = null)
                    currentRequest = stripped
                    runCatching { prepareAndPlay(exo, stripped, pos) }
                        .onFailure { fatalError = "播放出错：${error.errorCodeName}" }
                    return
                }
                // 之前只落盘不反馈：用户看到的是永远转圈的缓冲页，体感等同闪退。
                fatalError = "播放出错：${error.errorCodeName}"
            }
        })
        runCatching { prepareAndPlay(exo, request, request.positionMs) }
            .onFailure {
                com.pilinara.CrashLog.write(applicationContext, Thread.currentThread(), it)
                fatalError = "无法播放：${it.message ?: it.javaClass.simpleName}"
            }
        ready = true
    }

    private fun currentBrightness(): Float {
        val v = window.attributes.screenBrightness
        return if (v in 0f..1f) v else 0.5f
    }

    private fun parseRequest(intent: Intent): PlayRequest? =
        intent.getStringExtra(EXTRA_REQUEST)?.let {
            json.decodeFromString(PlayRequest.serializer(), it)
        }

    /** 用快照里的默认倍速/只听偏好开播——本函数内没有任何阻塞读取。 */
    private fun prepareAndPlay(c: ExoPlayer, request: PlayRequest, positionMs: Long) {
        PlaybackHeaderStore.set(listOfNotNull(request.videoUrl, request.audioUrl), request.headers)
        c.setMediaItem(buildMediaItem(request), positionMs)
        c.playWhenReady = true
        if (settingsSnapshot.defaultSpeed != 1f) c.setPlaybackSpeed(settingsSnapshot.defaultSpeed)
        if (settingsSnapshot.audioOnly) {
            c.trackSelectionParameters = c.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, true)
                .build()
        }
        c.prepare()
    }

    private fun buildMediaItem(request: PlayRequest): MediaItem {
        val extras = Bundle().apply {
            putString(PiliMediaSourceFactory.EXTRA_STREAM_TYPE, request.streamType)
            request.audioUrl?.let { putString(PiliMediaSourceFactory.EXTRA_AUDIO_URL, it) }
        }
        return MediaItem.Builder()
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
    }

    private suspend fun loadDanmaku(cid: Long, mergeWindowMs: Long): List<Danmaku> = try {
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
    } catch (ce: kotlinx.coroutines.CancellationException) {
        throw ce
    } catch (t: Throwable) {
        // 弹幕解析的任何意外都不应拖垮播放：记录日志并返回空列表。
        com.pilinara.CrashLog.write(applicationContext, Thread.currentThread(), t)
        emptyList()
    }

    /**
     * 播放器内切换清晰度：按目标 qn 重新拉 playurl，保留当前进度无缝换源。
     * 仅 B 站视频（bvid 非空）可用；失败 Toast 提示，不影响当前播放。
     */
    private fun switchQuality(targetQn: Int) {
        val req = currentRequest ?: return
        if (req.bvid.isEmpty()) return
        val pos = player?.currentPosition ?: 0L
        lifecycleScope.launch {
            val app = application as PiliApplication
            val c = app.container
            val result = runCatching {
                withContext(Dispatchers.IO) {
                    val cdn = c.settings.cdnNode.first()
                    val roaming = c.settings.roamingServer.first()
                    val weakNet = c.settings.weakNet.first()
                    val hiRes = c.settings.hiResAudio.first() && !weakNet
                    val qn = PlayerSettings.effectiveQn(targetQn, weakNet)
                    buildBiliPlayRequest(
                        c.api, req.bvid, req.cid, req.title,
                        qn, cdn, roaming, hiRes,
                    )
                }
            }
            result.onSuccess { newReq ->
                audioFallbackUsed = false
                currentRequest = newReq
                player?.let { prepareAndPlay(it, newReq, pos) }
            }.onFailure {
                android.widget.Toast.makeText(
                    this@PlayerActivity,
                    "切换清晰度失败：${it.message}",
                    android.widget.Toast.LENGTH_SHORT,
                ).show()
            }
        }
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.hasSystemFeature(
                android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE,
            )
        ) {
            runCatching {
                enterPictureInPictureMode(android.app.PictureInPictureParams.Builder().build())
            }
        }
    }

    private var landscape by mutableStateOf(false)
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
        if (player?.isPlaying == true) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipMode = isInPictureInPictureMode
    }

    private var pipMode: Boolean by mutableStateOf(false)

    override fun onDestroy() {
        runCatching { player?.release() }
        player = null
        PlaybackHeaderStore.clear()
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_REQUEST = "play_request"

        fun start(context: Context, request: PlayRequest) {
            val text = Json.encodeToString(PlayRequest.serializer(), request)
            // 调用方可能传 Application Context（详情页/源详情页的 appContext）：
            // 非 Activity 上下文 startActivity 必须带 NEW_TASK，否则抛
            // AndroidRuntimeException 直接闪退。Activity 上下文下该标志为无害
            // no-op，故无条件添加以消除一切边界情况。
            val intent = Intent(context, PlayerActivity::class.java)
                .putExtra(EXTRA_REQUEST, text)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }
}

/** 对 NativeCore 弹幕接口的薄封装（集中 JSON 反序列化）。 */
private object NativeCoreDanmaku {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseSegSo(b64: String, mergeWindowMs: Long): List<Danmaku> {
        val s = com.pilinara.core.NativeCore.parseDanmakuSegSo(b64, mergeWindowMs)
        return json.decodeFromString(kotlinx.serialization.builtins.ListSerializer(Danmaku.serializer()), s)
    }

    fun parseXml(xml: String, mergeWindowMs: Long): List<Danmaku> {
        val s = com.pilinara.core.NativeCore.parseDanmakuXml(xml, mergeWindowMs)
        return json.decodeFromString(kotlinx.serialization.builtins.ListSerializer(Danmaku.serializer()), s)
    }
}

/** 播放服务致命错误页：替代闪退，用户可返回；错误详情已写入 crash.log。 */
@Composable
private fun PlayerFatalError(message: String, onBack: () -> Unit) {
    Box(
        Modifier.fillMaxSize().background(Color.Black).padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                text = "无法播放",
                color = Color.White,
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = message,
                color = Color(0xFFCCCCCC),
                style = MaterialTheme.typography.bodyMedium,
            )
            Text(
                text = "详细信息已记录到 Android/data/com.pilinara/files/crash.log",
                color = Color(0xFF888888),
                style = MaterialTheme.typography.labelSmall,
            )
            androidx.compose.material3.Button(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                Text("  返回")
            }
        }
    }
}

/**
 * 播放页宿主：弹幕/空降跳过等副作用 + 控制层。
 * 播放器在这里一定非空（ready=true 才会组合到这里）。
 */
@Composable
private fun PlayerScreenHost(
    container: com.pilinara.AppContainer,
    request: PlayRequest,
    player: ExoPlayer,
    settings: PlayerSettings,
    loadDanmaku: suspend (Long, Long) -> List<Danmaku>,
    onBack: () -> Unit,
    onPip: () -> Unit,
    onToggleOrientation: () -> Unit,
    onBrightness: (Float) -> Unit,
    onVolume: (Float) -> Unit,
    currentBrightness: () -> Float,
    pipMode: Boolean,
    currentQn: Int,
    canSwitchQuality: Boolean,
    onSwitchQuality: (Int) -> Unit,
    isLandscape: Boolean = false,
) {
    val audioOnlyDefault = settings.audioOnly
    val danmakuEnabled by container.settings.danmakuEnabled.collectAsState(true)
    val mergeWindow by container.settings.danmakuMergeWindow.collectAsState(10_000L)
    val danmakuOpacity by container.settings.danmakuOpacity.collectAsState(0.82f)
    val danmakuScale by container.settings.danmakuScale.collectAsState(1.0f)
    val danmakuSpeed by container.settings.danmakuSpeed.collectAsState(1.0f)
    val danmakuArea by container.settings.danmakuArea.collectAsState(1.0f)
    val danmakuShowFixed by container.settings.danmakuShowFixed.collectAsState(true)
    val danmakuShowColor by container.settings.danmakuShowColor.collectAsState(true)

    var rawDanmaku by remember { mutableStateOf<List<Danmaku>>(emptyList()) }
    var danmakuVisible by remember { mutableStateOf(true) }
    var audioOnly by remember { mutableStateOf(audioOnlyDefault) }

    // 弹幕显示过滤：区域外的固定弹幕（顶/底）与彩色弹幕按设置隐藏。
    val danmakuList = remember(rawDanmaku, danmakuShowFixed, danmakuShowColor) {
        rawDanmaku.filter { d ->
            val isFixed = d.mode == 4 || d.mode == 5
            if (isFixed && !danmakuShowFixed) return@filter false
            if (!danmakuShowColor && d.color != 0xFFFFFFL) return@filter false
            true
        }
    }

    LaunchedEffect(request.cid, danmakuEnabled) {
        rawDanmaku = if (request.cid > 0 && danmakuEnabled) {
            loadDanmaku(request.cid, mergeWindow)
        } else {
            emptyList()
        }
    }

    // 空降跳过（BilibiliSponsorBlock 社区数据）：播放到广告/恰饭片段自动 seek 到段尾。
    // 分类可自定义（赞助/付费推广/自我介绍/片头/片尾/精彩看点等）。
    val sponsorSkip by container.settings.sponsorSkip.collectAsState(true)
    val sponsorCategories by container.settings.sponsorCategories
        .collectAsState(com.pilinara.data.SettingsStore.DEFAULT_SPONSOR_CATEGORIES)
    var segments by remember { mutableStateOf<List<com.pilinara.api.SponsorSegment>>(emptyList()) }
    val skippedIds = remember { mutableSetOf<String>() }
    LaunchedEffect(request.bvid, request.cid, sponsorSkip, sponsorCategories) {
        skippedIds.clear()
        segments = if (sponsorSkip && request.bvid.isNotEmpty()) {
            val cats = sponsorCategories.split(',').map { it.trim() }.filter { it.isNotEmpty() }
            withContext(Dispatchers.IO) {
                runCatching { container.api.sponsorSegments(request.bvid, request.cid, cats) }
                    .getOrDefault(emptyList())
            }
        } else {
            emptyList()
        }
    }
    LaunchedEffect(segments) {
        if (segments.isEmpty()) return@LaunchedEffect
        while (true) {
            delay(500)
            if (!player.isPlaying) continue
            val posSec = player.currentPosition / 1000f
            val seg = segments.firstOrNull {
                posSec >= it.startTime && posSec < it.endTime - 0.5f
            }
            if (seg != null && seg.uuid !in skippedIds) {
                skippedIds.add(seg.uuid)
                player.seekTo((seg.endTime * 1000).toLong())
            }
        }
    }

    PlayerScreen(
        title = request.title,
        player = player,
        onBack = onBack,
        onPip = onPip,
        onToggleOrientation = onToggleOrientation,
        defaultSpeed = settings.defaultSpeed,
        danmakuEnabled = danmakuEnabled,
        danmakuVisible = danmakuVisible,
        onToggleDanmaku = { danmakuVisible = !danmakuVisible },
        danmakuList = danmakuList,
        danmakuOpacity = danmakuOpacity,
        danmakuScale = danmakuScale,
        danmakuSpeed = danmakuSpeed,
        danmakuArea = danmakuArea,
        audioOnly = audioOnly,
        onToggleAudioOnly = { enable ->
            audioOnly = enable
            player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, enable)
                .build()
        },
        onBrightness = onBrightness,
        onVolume = onVolume,
        currentBrightness = currentBrightness,
        pipMode = pipMode,
        currentQn = currentQn,
        canSwitchQuality = canSwitchQuality,
        onSwitchQuality = onSwitchQuality,
        isLandscape = isLandscape,
    )
}

@UnstableApi
@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun PlayerScreen(
    title: String,
    player: Player,
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
    danmakuSpeed: Float,
    danmakuArea: Float,
    audioOnly: Boolean,
    onToggleAudioOnly: (Boolean) -> Unit,
    onBrightness: (Float) -> Unit,
    onVolume: (Float) -> Unit,
    currentBrightness: () -> Float,
    pipMode: Boolean,
    currentQn: Int,
    canSwitchQuality: Boolean,
    onSwitchQuality: (Int) -> Unit,
    isLandscape: Boolean = false,
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

    // 只听模式开关（含「默认只听」设置）：播放器就绪后应用一次。
    LaunchedEffect(audioOnly) {
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(androidx.media3.common.C.TRACK_TYPE_VIDEO, audioOnly)
            .build()
    }

    // 轮询进度（轻量：500ms 一次，仅读内存状态）。
    LaunchedEffect(Unit) {
        while (true) {
            position = player.currentPosition
            if (player.duration > 0) duration = player.duration
            isBuffering = player.playbackState == Player.STATE_BUFFERING
            delay(500)
        }
    }

    // 播放状态监听：直接注册/注销，不再用 Handler 轮询等待播放器就绪。
    DisposableEffect(player) {
        val l = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                isBuffering = playbackState == Player.STATE_BUFFERING
                if (player.duration > 0) duration = player.duration
            }
        }
        player.addListener(l)
        isPlaying = player.isPlaying
        onDispose { player.removeListener(l) }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            // 竖屏：底色跟随 App 主题（视频区只占上方 16:9，不再纯黑占满）；横屏才纯黑全屏
            .background(if (isLandscape) Color.Black else MaterialTheme.colorScheme.background)
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = { controlsVisible = !controlsVisible },
                    onDoubleTap = { offset ->
                        val delta = if (offset.x < size.width / 3f) -10_000L else 10_000L
                        player.seekTo((player.currentPosition + delta).coerceAtLeast(0L))
                        gestureHint = if (delta < 0) "快退 10s" else "快进 10s"
                    },
                    onLongPress = {
                        player.setPlaybackSpeed(2f)
                        gestureHint = "2 倍速"
                    },
                    onPress = {
                        awaitRelease()
                        player.setPlaybackSpeed(speed)
                        gestureHint = null
                    },
                )
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = { scrubTarget = player.currentPosition },
                    onDragEnd = {
                        scrubTarget?.let { player.seekTo(it) }
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
            modifier = if (isLandscape) { Modifier.fillMaxSize() } else {
                Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .align(Alignment.TopCenter)
            },
            factory = { ctx ->
                // PlayerView 在组合期构建，onCreate 的守卫抓不到这里的异常；
                // 失败时退化为空 View 也不能让整个播放页崩溃。
                runCatching {
                    val p = player
                    PlayerView(ctx).apply {
                        useController = false
                        this.player = p
                    }
                }.getOrElse {
                    com.pilinara.CrashLog.write(
                        ctx, Thread.currentThread(), it,
                    )
                    android.view.View(ctx)
                }
            },
            update = { view ->
                if (view is PlayerView && view.player !== player) {
                    runCatching { view.player = player }
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
                area = danmakuArea,
                speed = danmakuSpeed,
                positionProvider = { scrubTarget ?: player.currentPosition },
                isPlayingProvider = { player.isPlaying },
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
                            if (canSwitchQuality) {
                                Quality.PRESETS.forEach { q ->
                                    DropdownMenuItem(
                                        text = {
                                            Text(
                                                if (q.qn == currentQn) "清晰度：${q.label} ✓"
                                                else "清晰度：${q.label}",
                                            )
                                        },
                                        onClick = {
                                            moreMenu = false
                                            if (q.qn != currentQn) onSwitchQuality(q.qn)
                                        },
                                    )
                                }
                            }
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
                        player.seekTo((player.currentPosition - 10_000L).coerceAtLeast(0L))
                    }) {
                        Icon(Icons.Filled.RotateLeft, contentDescription = "快退", tint = Color.White, modifier = Modifier.size(40.dp))
                    }
                    IconButton(
                        onClick = {
                            if (player.isPlaying) player.pause() else player.play()
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
                        player.seekTo(player.currentPosition + 10_000L)
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
                                        player.setPlaybackSpeed(sp)
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
                        // 进度可能瞬时大于尚未就绪的 duration（直播/时长未下发），
                        // 越界值会让 Slider 直接抛 IllegalArgumentException（表现为播放中闪退）。
                        value = (scrubTarget ?: position)
                            .coerceIn(0L, duration.coerceAtLeast(1L)).toFloat(),
                        onValueChange = { scrubTarget = it.toLong() },
                        onValueChangeFinished = {
                            scrubTarget?.let { player.seekTo(it) }
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

private fun formatTime(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
}
