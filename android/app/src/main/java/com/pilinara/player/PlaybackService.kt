package com.pilinara.player

import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.pilinara.PiliApplication
import com.pilinara.net.Http
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/**
 * 后台播放服务：单 ExoPlayer + MediaSession，系统媒体通知 / 蓝牙耳机键 / 锁屏控制全部由
 * Media3 接管。视频轨/音频轨合并、HLS/DASH 分流由 [PiliMediaSourceFactory] 完成；
 * 网络层复用全局 OkHttp（Cookie、连接池、VIP 改写后的防盗链）。
 */
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as PiliApplication
        val container = app.container

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

        // 视频走 HLS/DASH/合流工厂，B 站双轨 DASH 在此合并为一路可播媒体。
        val piliFactory = PiliMediaSourceFactory(resolvingFactory)

        // 用户解码 / 缓冲偏好（在服务创建时读取；更改后下次播放生效）。
        val decodeMode = runBlocking { container.settings.decodeMode.first() }
        val bufferMs = runBlocking { container.settings.bufferMs.first() }

        val renderersFactory = DefaultRenderersFactory(this).apply {
            when (decodeMode) {
                "hard" ->
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                "soft" -> {
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                    // 仅保留平台软解（OMX.google / c2.android）；无匹配时回退全部。
                    setMediaCodecSelector { mimeType, secure, tunneling ->
                        val infos = MediaCodecUtil.getDecoderInfos(mimeType, secure, tunneling)
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

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                (bufferMs / 2).coerceIn(1_000, 60_000),
                bufferMs.coerceIn(2_000, 120_000),
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_MS,
                DefaultLoadControl.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS,
            )
            .build()

        val player = ExoPlayer.Builder(this)
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

        mediaSession = MediaSession.Builder(this, player).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession

    override fun onTaskRemoved(rootIntent: android.content.Intent?) {
        val player = mediaSession?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}
