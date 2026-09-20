package com.pilinara.player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import com.pilinara.AppContainer
import com.pilinara.data.SettingsStore
import com.pilinara.net.Http
import com.pilinara.player.media3.AudioNormalizationConfiguration
import com.pilinara.player.media3.AudioNormalizationProcessor
import com.pilinara.player.media3.resolveMedia3BufferPolicy
import kotlinx.coroutines.flow.first

/**
 * 播放相关设置的不可变快照。
 *
 * 历史教训：旧版在 [PlayerEngine.create] / PlayerActivity.onCreate 里用 `runBlocking`
 * 同步读 DataStore。DataStore 首次访问要读磁盘文件，`runBlocking` 会把主线程卡在这次
 * IO 上；Android 17 对主线程阻塞极其敏感，轻则 ANR 重则被系统直接杀进程——用户看到的
 * 就是「点播放即闪退」，而且没有任何 Java 异常可捕获。
 *
 * 现在统一改为：进入播放页后先在协程里 [load] 出快照（毫秒级，失败全量兜底默认值），
 * 再用快照构建播放器。播放页全程不再有任何主线程阻塞读取。
 */
data class PlayerSettings(
    val decodeMode: String = "auto",
    val bufferMs: Int = 50_000,
    val defaultSpeed: Float = 1f,
    val audioOnly: Boolean = false,
    val playerCore: String = "media3",
    val weakNet: Boolean = false,
    // ---- 音频处理（移植自 pili++ 的 AudioNormalizationProcessor）----
    val audioProcEnabled: Boolean = false,
    val audioGainDb: Float = 0f,
    val audioDynamic: Boolean = false,
    val audioTargetRmsDb: Float = -16f,
    val audioHighpassHz: Float = 0f,
    val audioLowpassHz: Float = 0f,
    val audioEqEnabled: Boolean = false,
    val audioEqFreqHz: Float = 1000f,
    val audioEqGainDb: Float = 0f,
    val audioEqQ: Float = 1f,
    // ---- 超分辨率（Media3 LanczosResample）----
    val superResolution: String = "disable",
) {
    companion object {
        suspend fun load(settings: SettingsStore): PlayerSettings = runCatching {
            PlayerSettings(
                decodeMode = settings.decodeMode.first(),
                bufferMs = settings.bufferMs.first(),
                defaultSpeed = settings.defaultSpeed.first(),
                audioOnly = settings.audioOnly.first(),
                playerCore = settings.playerCore.first(),
                weakNet = settings.weakNet.first(),
                audioProcEnabled = settings.audioProcEnabled.first(),
                audioGainDb = settings.audioGainDb.first(),
                audioDynamic = settings.audioDynamic.first(),
                audioTargetRmsDb = settings.audioTargetRmsDb.first(),
                audioHighpassHz = settings.audioHighpassHz.first(),
                audioLowpassHz = settings.audioLowpassHz.first(),
                audioEqEnabled = settings.audioEqEnabled.first(),
                audioEqFreqHz = settings.audioEqFreqHz.first(),
                audioEqGainDb = settings.audioEqGainDb.first(),
                audioEqQ = settings.audioEqQ.first(),
                superResolution = settings.superResolution.first(),
            )
        }.getOrDefault(PlayerSettings())

        /** 弱网/省流模式下的清晰度上限（720P）。 */
        const val WEAK_NET_MAX_QN = 64

        /** 弱网模式下把用户偏好清晰度收敛到上限内。 */
        fun effectiveQn(preferQn: Int, weakNet: Boolean): Int =
            if (weakNet) minOf(preferQn, WEAK_NET_MAX_QN) else preferQn
    }
}

/**
 * 进程内 ExoPlayer 工厂。
 *
 * 参考 bv / bilipai 等第三方客户端的做法：播放器直接在播放页所在进程内构建，
 * 不经由 MediaSessionService 异步绑定（跨组件绑定在服务初始化失败/机型限缩下
 * 会以「点播放即闪退」收场）。
 *
 * 所有偏好经 [PlayerSettings] 快照传入——本函数内部不做任何阻塞 IO。
 */
@UnstableApi
object PlayerEngine {

    fun create(context: Context, container: AppContainer, settings: PlayerSettings): ExoPlayer {
        val httpFactory = OkHttpDataSource.Factory(container.http.client)
            .setUserAgent(Http.UA_WEB)

        // 按当前播放条目注入防盗链头（MediaItem 不支持逐条头，用 ResolvingDataSource 兜底）。
        val resolvingFactory = ResolvingDataSource.Factory(httpFactory) { dataSpec ->
            val extra = PlaybackHeaderStore.forUri(dataSpec.uri.toString())
            if (extra.isNullOrEmpty()) {
                dataSpec
            } else {
                dataSpec.buildUpon()
                    .setHttpRequestHeaders(dataSpec.httpRequestHeaders + extra)
                    .build()
            }
        }

        val piliFactory = PiliMediaSourceFactory(resolvingFactory)

        // 音频处理链：配置为空时处理器直通（内部判 null 后原样 copy），无需二选一构建。
        val audioProcessor = AudioNormalizationProcessor().apply {
            setConfiguration(AudioNormalizationConfiguration.fromSettings(
                enabled = settings.audioProcEnabled,
                gainDb = settings.audioGainDb,
                dynamic = settings.audioDynamic,
                targetRmsDb = settings.audioTargetRmsDb,
                highpassHz = settings.audioHighpassHz,
                lowpassHz = settings.audioLowpassHz,
                eqEnabled = settings.audioEqEnabled,
                eqFreqHz = settings.audioEqFreqHz,
                eqGainDb = settings.audioEqGainDb,
                eqQ = settings.audioEqQ,
            ))
        }

        val renderersFactory = PiliRenderersFactory(
            context = context,
            audioProcessor = audioProcessor,
            decodeMode = settings.decodeMode,
        )

        // 缓冲策略（移植 pili++）：min/max 分别约束；时间优先；直播用 Media3 默认。
        val isLive = false
        val bufferMs = if (settings.weakNet) settings.bufferMs * 2 else settings.bufferMs
        val policy = resolveMedia3BufferPolicy(
            targetBufferBytes = DEFAULT_TARGET_BUFFER_BYTES,
            bufferDurationMs = bufferMs,
            isLive = isLive,
        )
        val loadControl = if (policy == null) {
            DefaultLoadControl.Builder().build()
        } else {
            DefaultLoadControl.Builder()
                .setBufferDurationsMsForStreaming(
                    policy.minBufferMs,
                    policy.maxBufferMs,
                    policy.bufferForPlaybackMs,
                    policy.bufferForPlaybackAfterRebufferMs,
                )
                .setTargetBufferBytes(policy.targetBufferBytes)
                .setPrioritizeTimeOverSizeThresholdsForStreaming(true)
                .setBackBuffer(policy.backBufferDurationMs, false)
                .build()
        }

        val exo = ExoPlayer.Builder(context)
            .setRenderersFactory(renderersFactory)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(piliFactory)
            .setHandleAudioBecomingNoisy(true)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                /* handleAudioFocus = */ true,
            )
            .build()

        // 超分辨率：源尺寸要等 onVideoSizeChanged 才知道，这里只登记模式，
        // 由 PlayerActivity 在拿到 videoSize 后调用 applySuperResolution。
        return exo
    }

    private const val DEFAULT_TARGET_BUFFER_BYTES = 4 * 1024 * 1024
}

/**
 * 带音频处理器的 RenderersFactory（对应 pili++ 的 NormalizingRenderersFactory）。
 *
 * 软解选择改用 MediaCodecInfo.softwareOnly 判定：旧实现按解码器名猜
 * （含 google / c2.android），在部分 OEM 固件上会把厂商硬解误判成软解。
 */
private class PiliRenderersFactory(
    context: Context,
    private val audioProcessor: AudioNormalizationProcessor,
    private val decodeMode: String,
) : DefaultRenderersFactory(context) {
    init {
        // 解码失败时回退到其它可用解码器，而不是直接报错。
        setEnableDecoderFallback(true)
        if (decodeMode == "soft") setMediaCodecSelector(SOFTWARE_VIDEO_CODEC_SELECTOR)
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParameters: Boolean,
    ): AudioSink = DefaultAudioSink.Builder(context)
        .setAudioProcessors(arrayOf(audioProcessor))
        .setEnableFloatOutput(enableFloatOutput)
        .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParameters)
        .build()

    private companion object {
        val SOFTWARE_VIDEO_CODEC_SELECTOR = MediaCodecSelector { mimeType, secure, tunneling ->
            val infos = runCatching {
                MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, secure, tunneling)
            }.getOrDefault(emptyList())
            if (MimeTypes.isVideo(mimeType)) infos.filter { it.softwareOnly } else infos
        }
    }
}
