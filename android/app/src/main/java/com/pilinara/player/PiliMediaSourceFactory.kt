package com.pilinara.player

import androidx.media3.common.MediaItem
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManagerProvider
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/**
 * 自定义媒体源工厂，按 MediaItem.extras 中的 [EXTRA_STREAM_TYPE] 选择：
 * - progressive（B 站 DASH 独立 fMP4 轨）：把 video 轨与 audio 轨合并（[MergingMediaSource]）；
 * - hls / dash：交给对应源（第三方嗅探地址）。
 *
 * 请求头（Referer/UA 等）不在 MediaItem 上携带，而由上层 ResolvingDataSource 注入。
 */
class PiliMediaSourceFactory(
    private val dataSourceFactory: DataSource.Factory,
) : MediaSource.Factory {

    private var drmSessionManagerProvider: DrmSessionManagerProvider =
        DefaultDrmSessionManagerProvider()
    private var loadErrorHandlingPolicy: LoadErrorHandlingPolicy =
        DefaultLoadErrorHandlingPolicy()

    override fun createMediaSource(item: MediaItem): MediaSource {
        val extras = item.mediaMetadata.extras
        val streamType = extras?.getString(EXTRA_STREAM_TYPE) ?: TYPE_PROGRESSIVE
        val audioUrl = extras?.getString(EXTRA_AUDIO_URL)

        return when (streamType) {
            TYPE_HLS -> hlsFactory().createMediaSource(item)
            TYPE_DASH -> dashFactory().createMediaSource(item)
            else -> {
                val video = progressiveFactory().createMediaSource(item)
                if (audioUrl.isNullOrEmpty()) {
                    video
                } else {
                    val audioItem = MediaItem.Builder()
                        .setUri(audioUrl)
                        .setMediaId(item.mediaId + "#audio")
                        .build()
                    val audio = progressiveFactory().createMediaSource(audioItem)
                    MergingMediaSource(video, audio)
                }
            }
        }
    }

    override fun getSupportedTypes(): IntArray = intArrayOf(
        androidx.media3.common.C.CONTENT_TYPE_OTHER,
        androidx.media3.common.C.CONTENT_TYPE_HLS,
        androidx.media3.common.C.CONTENT_TYPE_DASH,
    )

    override fun setDrmSessionManagerProvider(
        drmSessionManagerProvider: DrmSessionManagerProvider,
    ): MediaSource.Factory = apply {
        this.drmSessionManagerProvider = drmSessionManagerProvider
    }

    override fun setLoadErrorHandlingPolicy(
        loadErrorHandlingPolicy: LoadErrorHandlingPolicy,
    ): MediaSource.Factory = apply {
        this.loadErrorHandlingPolicy = loadErrorHandlingPolicy
    }

    private fun progressiveFactory(): ProgressiveMediaSource.Factory =
        ProgressiveMediaSource.Factory(dataSourceFactory)
            .setDrmSessionManagerProvider(drmSessionManagerProvider)
            .setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)

    private fun hlsFactory(): HlsMediaSource.Factory =
        HlsMediaSource.Factory(dataSourceFactory)
            .setDrmSessionManagerProvider(drmSessionManagerProvider)
            .setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)

    private fun dashFactory(): DashMediaSource.Factory =
        DashMediaSource.Factory(dataSourceFactory)
            .setDrmSessionManagerProvider(drmSessionManagerProvider)
            .setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)

    companion object {
        const val EXTRA_STREAM_TYPE = "pili_stream_type"
        const val EXTRA_AUDIO_URL = "pili_audio_url"

        const val TYPE_PROGRESSIVE = "progressive"
        const val TYPE_HLS = "hls"
        const val TYPE_DASH = "dash"
    }
}
