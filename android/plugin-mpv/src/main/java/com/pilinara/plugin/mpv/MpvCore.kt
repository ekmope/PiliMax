package com.pilinara.plugin.mpv

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import com.pilinara.plugin.api.ExternalPlayerCore
import com.pilinara.plugin.api.PlaySpec
import dev.jdtech.mpv.MPVLib

/**
 * 基于 libmpv 的外部播放内核实现（`dev.jdtech.mpv:libmpv` 提供原生库与 Kotlin 绑定）。
 *
 * 与 VLC 内核保持一致的线程模型：所有 mpv 原生调用串行在专属 HandlerThread（mpv 要求
 * 事件线程带 Looper），[Callback] 回调投递到主线程（与 VlcCore 的约定一致）。
 *
 * B 站 DASH 分离音轨通过 `audio-add`（把音频轨作为外部音轨合流，等价 VLC 的 `input-slave`）；
 * B 站防盗链头（Referer/UA/Cookie）通过 `referrer`/`user-agent`/`http-header-fields` 注入。
 */
class MpvCore : ExternalPlayerCore {

    override val name: String = "MPV"

    private val main = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("mpv-core").apply { start() }
    private val worker = Handler(thread.looper)

    private var appContext: Context? = null
    private var mpv: MPVLib? = null

    @Volatile
    private var surface: Surface? = null
    private var surfaceW = 0
    private var surfaceH = 0

    private var rate = 1.0
    private var volume = 100
    private var callback: ExternalPlayerCore.Callback? = null

    /** mpv 事件回调（在 mpv 事件线程触发 → post 回主线程）。 */
    private val observer = object : MPVLib.EventObserver {
        override fun eventProperty(property: String) = Unit

        override fun eventProperty(property: String, value: Long) {
            when (property) {
                "time-pos" -> dispatch { onPosition(value * 1000) }
                "duration" -> if (value > 0) dispatch { onDuration(value * 1000) }
            }
        }

        override fun eventProperty(property: String, value: Double) {
            when (property) {
                "time-pos" -> dispatch { onPosition((value * 1000).toLong()) }
                "duration" -> if (value > 0) dispatch { onDuration((value * 1000).toLong()) }
            }
        }

        override fun eventProperty(property: String, value: Boolean) {
            if (property == "pause") dispatch { onPlayingChanged(!value) }
        }

        override fun eventProperty(property: String, value: String) = Unit

        override fun event(ev: Int) {
            when (ev) {
                MPVLib.MpvEvent.MPV_EVENT_FILE_LOADED,
                MPVLib.MpvEvent.MPV_EVENT_START_FILE,
                -> dispatch { onReady() }
                MPVLib.MpvEvent.MPV_EVENT_END_FILE -> dispatch { onEnded() }
                MPVLib.MpvEvent.MPV_EVENT_IDLE -> dispatch { onBuffering() }
            }
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
        val ctx = appContext ?: error("MpvCore.attach 尚未调用")
        rate = spec.rate.toDouble()
        worker.post {
            runCatching { teardownLocked() }
            // MPVLib.create 返回 MPVLib?（原生库加载失败时为 null）。
            // 这里在 runCatching 内断言非空：失败会被捕获并落盘，不会让进程闪退。
            runCatching {
                val lib = MPVLib.create(ctx)!!
                lib.addObserver(observer)
            // 选项必须在 init() 之前设置（部分选项 init 后只读）。
                applyOptions(lib, spec)
                lib.init()
                mpv = lib
                attachSurfaceLocked()
                lib.setPropertyDouble("speed", rate)
                lib.setPropertyInt("volume", volume)
                lib.command(arrayOf("loadfile", spec.videoUrl))
                if (!spec.audioUrl.isNullOrBlank()) {
                    // B 站 DASH：分离音轨作为外部音轨合流。
                    lib.command(arrayOf("audio-add", spec.audioUrl!!, "auto"))
                }
                if (spec.startPositionMs > 0) {
                    lib.command(arrayOf("seek", (spec.startPositionMs / 1000.0).toString(), "absolute"))
                }
                // 观察进度与时长，驱动 UI。
                lib.observeProperty("time-pos", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
                lib.observeProperty("duration", MPVLib.MpvFormat.MPV_FORMAT_DOUBLE)
                lib.observeProperty("pause", MPVLib.MpvFormat.MPV_FORMAT_FLAG)
            }.onFailure {
                // 插件模块不依赖宿主（CrashLog 在 :app）。只落 Log（避免未解析引用）。
                android.util.Log.e(TAG, "mpv open failed", it)
            }
        }
    }

    private fun applyOptions(lib: MPVLib, spec: PlaySpec) {
        // 硬解：优先 mediacodec（骁龙平台硬解，低功耗）；关闭时退回软解。
        lib.setOptionString("hwdec", if (spec.hardwareDecode) "mediacodec" else "no")
        lib.setOptionString("hwdec-codecs", "all")
        lib.setOptionString("vo", "gpu")
        lib.setOptionString("gpu-context", "android")
        lib.setOptionString("cache", "yes")
        lib.setOptionString("demuxer-max-bytes", "64MiB")
        lib.setOptionString("network-timeout", "20")
        // 防盗链与自定义头。
        val referer = spec.headers["Referer"] ?: spec.headers["referer"]
        val ua = spec.headers["User-Agent"] ?: spec.headers["user-agent"]
        if (!referer.isNullOrEmpty()) lib.setOptionString("referrer", referer)
        if (!ua.isNullOrEmpty()) lib.setOptionString("user-agent", ua)
        val extra = spec.headers.filterKeys {
            val k = it.lowercase()
            k != "referer" && k != "user-agent"
        }.map { (k, v) -> "$k: $v" }
        if (extra.isNotEmpty()) {
            // 现代 libmpv 支持 \n 分隔多项 header。
            lib.setOptionString("http-header-fields", extra.joinToString("\n"))
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
        val lib = mpv ?: return
        if (surfaceW > 0 && surfaceH > 0) {
            runCatching {
                lib.setPropertyString("android-surface-size", "${surfaceW}x$surfaceH")
            }
        }
        val s = surface ?: return
        runCatching {
            lib.attachSurface(s)
        }.onFailure { Log.w(TAG, "attachSurface failed", it) }
    }

    override fun play() {
        worker.post { mpv?.setPropertyBoolean("pause", false) }
    }

    override fun pause() {
        worker.post { mpv?.setPropertyBoolean("pause", true) }
    }

    override fun seekTo(positionMs: Long) {
        worker.post {
            runCatching {
                mpv?.command(arrayOf("seek", (positionMs / 1000.0).toString(), "absolute"))
            }
        }
    }

    override fun setRate(rate: Float) {
        this.rate = rate.toDouble()
        worker.post { runCatching { mpv?.setPropertyDouble("speed", this.rate) } }
    }

    override fun setVolume(volume: Float) {
        this.volume = (volume.coerceIn(0f, 1f) * 100f).toInt()
        worker.post { runCatching { mpv?.setPropertyInt("volume", this.volume) } }
    }

    override fun setCallback(callback: ExternalPlayerCore.Callback) {
        this.callback = callback
    }

    override fun release() {
        worker.post { teardownLocked() }
        worker.post { thread.quitSafely() }
    }

    private fun teardownLocked() {
        runCatching {
            mpv?.let { lib ->
                runCatching { lib.detachSurface() }
                runCatching { lib.removeObserver(observer) }
                runCatching { lib.command(arrayOf("stop")) }
                runCatching { lib.destroy() }
            }
        }
        mpv = null
    }

    private companion object {
        const val TAG = "MpvCore"
    }
}
