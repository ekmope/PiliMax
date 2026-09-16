package com.pilinara.player

import android.content.Context
import android.view.Surface
import android.view.SurfaceHolder
import dev.jdtech.mpv.MPVLib

/** MPV 内核：基于 libmpv Android（`dev.jdtech.mpv:libmpv`，自拉取内核）。 */
class MpvCorePlayer(context: Context) : CorePlayer {

    override val backend: PlayerBackend = PlayerBackend.MPV

    private val mpv: MPVLib? = MPVLib.create(context.applicationContext)
    private var initialized = false
    private var attached = false

    private fun requireMpv(): MPVLib =
        mpv ?: throw IllegalStateException("MPV 内核初始化失败")

    private fun ensureInit() {
        val m = requireMpv()
        if (!initialized) {
            m.init()
            initialized = true
        }
    }

    override fun attachSurface(surface: Surface, holder: SurfaceHolder?) {
        ensureInit()
        requireMpv().attachSurface(surface)
        attached = true
    }

    override fun play(url: String) {
        ensureInit()
        val m = requireMpv()
        m.command(arrayOf("loadfile", url))
        m.setPropertyString("pause", "no")
    }

    override fun pause() {
        requireMpv().setPropertyString("pause", "yes")
    }

    override fun resume() {
        requireMpv().setPropertyString("pause", "no")
    }

    override fun seekTo(positionMs: Long) {
        requireMpv().command(arrayOf("seek", (positionMs / 1000.0).toString(), "absolute"))
    }

    override fun setPlaybackSpeed(speed: Float) {
        requireMpv().setPropertyDouble("speed", speed.toDouble())
    }

    override val isPlaying: Boolean
        get() = mpv?.getPropertyBoolean("pause")?.not() ?: false

    override fun release() {
        val m = mpv ?: return
        if (attached) {
            m.detachSurface()
            attached = false
        }
        m.destroy()
    }
}