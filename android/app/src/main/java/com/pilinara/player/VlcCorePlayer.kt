package com.pilinara.player

import android.content.Context
import android.net.Uri
import android.view.Surface
import android.view.SurfaceHolder
import org.videolan.libvlc.LibVLC
import org.videolan.libvlc.Media
import org.videolan.libvlc.MediaPlayer
import org.videolan.libvlc.interfaces.IVLCVout

/** VLC 内核：基于 Videolan libVLC Android 绑定。 */
class VlcCorePlayer(context: Context) : CorePlayer {

    override val backend: PlayerBackend = PlayerBackend.VLC

    private val libVLC: LibVLC = LibVLC(context.applicationContext)
    private val mediaPlayer: MediaPlayer = MediaPlayer(libVLC)
    private val vout: IVLCVout
        get() = mediaPlayer.getVLCVout()

    override fun attachSurface(surface: Surface, holder: SurfaceHolder?) {
        vout.setVideoSurface(surface, holder)
    }

    override fun play(url: String) {
        mediaPlayer.setMedia(Media(libVLC, Uri.parse(url)))
        mediaPlayer.play()
    }

    override fun pause() {
        mediaPlayer.pause()
    }

    override fun resume() {
        mediaPlayer.play()
    }

    override fun seekTo(positionMs: Long) {
        mediaPlayer.setTime(positionMs)
    }

    override fun setPlaybackSpeed(speed: Float) {
        mediaPlayer.setRate(speed)
    }

    override val isPlaying: Boolean
        get() = mediaPlayer.isPlaying

    override fun release() {
        mediaPlayer.stop()
        mediaPlayer.release()
        libVLC.release()
    }
}