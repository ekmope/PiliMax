package com.pilinara.player

import android.content.Context
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.common.util.UnstableApi
import com.pilinara.AppContainer
import com.pilinara.net.Http
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/**
 * 进程内 ExoPlayer 工厂。
 *
 * 参考 bv / bilipai 等第三方客户端的做法：播放器直接在播放页所在进程内构建，
 * 不经由 MediaSessionService 异步绑定（跨组件绑定在服务初始化失败/机型限缩下
 * 会以「点播放即闪退」收场）。后台通知播放属于附加能力，不能绑架播放本身。
 *
 * 解码模式、缓冲时长等设置与旧 PlaybackService 保持一致，读取失败一律安全兜底。
 */
@UnstableApi
object PlayerEngine {

    fun create(context: Context, container: AppContainer): ExoPlayer {
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

        val decodeMode = runCatching {
            runBlocking { container.settings.decodeMode.first() }
        }.getOrDefault("auto")
        val bufferMs = runCatching {
            runBlocking { container.settings.bufferMs.first() }
        }.getOrDefault(50_000)

        val renderersFactory = DefaultRenderersFactory(context).apply {
            when (decodeMode) {
                "hard" ->
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
                "soft" -> {
                    setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
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
