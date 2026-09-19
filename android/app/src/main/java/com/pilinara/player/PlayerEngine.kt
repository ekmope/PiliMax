package com.pilinara.player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.common.util.UnstableApi
import com.pilinara.AppContainer
import com.pilinara.data.SettingsStore
import com.pilinara.net.Http
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
) {
    companion object {
        suspend fun load(settings: SettingsStore): PlayerSettings = runCatching {
            PlayerSettings(
                decodeMode = settings.decodeMode.first(),
                bufferMs = settings.bufferMs.first(),
                defaultSpeed = settings.defaultSpeed.first(),
                audioOnly = settings.audioOnly.first(),
                playerCore = settings.playerCore.first(),
            )
        }.getOrDefault(PlayerSettings())
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

        val renderersFactory = DefaultRenderersFactory(context).apply {
            when (settings.decodeMode) {
                "hard" ->
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                "soft" -> {
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                    setMediaCodecSelector { mimeType, secure, tunneling ->
                        // 解码器枚举在个别固件上会抛 DecoderQueryException；
                        // 兜底为默认选择器，绝不让软解偏好把播放炸掉。
                        val infos = runCatching {
                            MediaCodecUtil.getDecoderInfos(mimeType, secure, tunneling)
                        }.getOrElse {
                            return@setMediaCodecSelector MediaCodecSelector.DEFAULT
                                .getDecoderInfos(mimeType, secure, tunneling)
                        }
                        infos.filter {
                            val n = it.name.lowercase()
                            n.contains("google") || n.contains("c2.android")
                        }.ifEmpty { infos }
                    }
                }
                else ->
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER)
            }
        }

        val bufferMs = settings.bufferMs
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                (bufferMs / 2).coerceIn(1_000, 60_000),
                bufferMs.coerceIn(2_000, 120_000),
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
            )
            .build()

        return ExoPlayer.Builder(context)
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
    }
}
