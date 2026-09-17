package com.pilinara.plugin.vlc

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import com.pilinara.plugin.api.ExternalPlayerCore
import com.pilinara.plugin.api.PlaySpec
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer

/**
 * 基于 libVLC 3.6.x 的外部播放内核实现。
 *
 * - 所有 VLC 原生调用串行在专属 HandlerThread（libVLC 要求事件线程带 Looper）；
 * - B 站 DASH 的分离音轨通过 `input-slave` 合流，HTTP 头以全局参数注入音视频两路；
 * - 输出目标为宿主提供的 Surface（经 IVLCVout.setVideoSurface）。
 */
class VlcCore : ExternalPlayerCore {

    override val name: String = "VLC"

    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("vlc-core").apply { start() }
    private val worker = Handler(thread.looper)

    private var appContext: Context? = null
    private var libVlc: LibVLC? = null
    private var player: MediaPlayer? = null

    private var surface: Surface? = null
    private var surfaceW = 0
    private var surfaceH = 0
    private var rate = 1f
    private var volume = 100
    private var callback: ExternalPlayerCore.Callback? = null

    private val eventListener = MediaPlayer.EventListener { ev ->
        when (ev.type) {
            MediaPlayer.Event.Opening, MediaPlayer.Event.Buffering -> {
                if (ev.type == MediaPlayer.Event.Buffering && ev.buffering >= 99.9f) {
                    dispatch { onReady() }
                    player?.takeIf { it.length > 0 }?.let { dispatch { onDuration(it.length) } }
                } else {
                    dispatch { onBuffering() }
                }
            }
            MediaPlayer.Event.Playing -> {
                dispatch {
                    onPlayingChanged(true)
                    onReady()
                }
                player?.takeIf { it.length > 0 }?.let { mp ->
                    dispatch { onDuration(mp.length) }
                }
            }
            MediaPlayer.Event.Paused -> dispatch { onPlayingChanged(false) }
            MediaPlayer.Event.EndReached -> dispatch { onEnded() }
            MediaPlayer.Event.EncounteredError ->
                dispatch { onError("VLC 播放失败（EncounteredError）") }
            MediaPlayer.Event.TimeChanged -> dispatch { onPosition(ev.timeChanged) }
            MediaPlayer.Event.LengthChanged -> player?.length
                ?.takeIf { it > 0 }?.let { len -> dispatch { onDuration(len) } }
        }
    }

    private inline fun dispatch(crossinline block: ExternalPlayerCore.Callback.() -> Unit) {
        val cb = callback ?: return
        main.post { runCatching { cb.block() } }
    }

    override fun attach(context: Context) {
        appContext = context.applicationContext
    }

    override fun open(spec: PlaySpec) {
        val ctx = appContext ?: error("VlcCore.attach 尚未调用")
        rate = spec.rate
        worker.post {
            teardownLocked()

            val options = buildLibOptions(spec)
            val vlc = LibVLC(ctx, options)
            val mp = MediaPlayer(vlc)
            mp.setEventListener(eventListener)

            val media = Media(vlc, Uri.parse(spec.videoUrl)).apply {
                setHWDecoderEnabled(spec.hardwareDecode, spec.hardwareDecode)
                if (!spec.hardwareDecode) addOption(":avcodec-hw=none")
                // B 站 DASH：分离音轨作为从属输入合流（HTTP 头由全局参数覆盖）。
                if (!spec.audioUrl.isNullOrBlank()) {
                    addOption(":input-slave=${spec.audioUrl}")
                }
                if (spec.startPositionMs > 0) {
                    addOption(":start-time=${spec.startPositionMs / 1000.0}")
                }
                addOption(":network-caching=2000")
                addOption(":http-reconnect")
            }
            mp.media = media
            media.release()

            libVlc = vlc
            player = mp

            attachSurfaceLocked()
            mp.volume = volume
            mp.rate = rate
            mp.play()
        }
    }

    override fun setSurface(surface: Surface?, width: Int, height: Int) {
        worker.post {
            this.surface = surface
            this.surfaceW = width
            this.surfaceH = height
            attachSurfaceLocked()
        }
    }

    private fun attachSurfaceLocked() {
        val mp = player ?: return
        val vout = mp.getVLCVout()
        if (vout.areViewsAttached()) vout.detachViews()
        val s = surface ?: return
        if (surfaceW > 0 && surfaceH > 0) vout.setWindowSize(surfaceW, surfaceH)
        runCatching {
            vout.setVideoSurface(s, null)
            vout.attachViews()
        }.onFailure { Log.w(TAG, "attachSurface failed", it) }
    }

    override fun play() {
        worker.post { player?.play() }
    }

    override fun pause() {
        worker.post { player?.pause() }
    }

    override fun seekTo(positionMs: Long) {
        worker.post { player?.time = positionMs }
    }

    override fun setRate(rate: Float) {
        this.rate = rate
        worker.post { player?.rate = rate }
    }

    override fun setVolume(volume: Float) {
        this.volume = (volume.coerceIn(0f, 1f) * 100f).toInt()
        worker.post { player?.volume = this.volume }
    }

    override fun setCallback(callback: ExternalPlayerCore.Callback) {
        this.callback = callback
    }

    override fun release() {
        worker.post {
            teardownLocked()
        }
        worker.post { thread.quitSafely() }
    }

    private fun teardownLocked() {
        runCatching {
            player?.let { p ->
                runCatching { p.getVLCVout().detachViews() }
                p.stop()
                p.setEventListener(null)
                p.release()
            }
        }
        player = null
        runCatching { libVlc?.release() }
        libVlc = null
    }

    private fun buildLibOptions(spec: PlaySpec): List<String> {
        val opts = ArrayList<String>()
        opts.add("--no-video-title-show")
        opts.add("--no-stats")
        opts.add("--audio-time-stretch")
        val referer = spec.headers["Referer"] ?: spec.headers["referer"]
        val ua = spec.headers["User-Agent"] ?: spec.headers["user-agent"]
        referer?.let { opts.add("--http-referrer=$it") }
        ua?.let { opts.add("--http-user-agent=$it") }
        // 其余自定义头（如 Cookie）统一通过 http-header-fields 注入。
        val extra = spec.headers.filterKeys {
            val k = it.lowercase()
            k != "referer" && k != "user-agent"
        }.map { (k, v) -> "$k: $v" }
        if (extra.isNotEmpty()) {
            opts.add("--http-header-fields=${extra.joinToString("\r\n")}")
        }
        return opts
    }

    private companion object {
        const val TAG = "VlcCore"
    }
}
