package com.pilinara.player

import android.content.Context
import android.view.Surface
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer

/** 默认内核：基于 AndroidX Media3 / ExoPlayer 的实现。 */
class Media3CorePlayer(context: Context) : CorePlayer {

    override val backend: PlayerBackend = PlayerBackend.MEDIA3

    private val player: ExoPlayer = ExoPlayer.Builder(context.applicationContext).build()

    override fun attachSurface(surface: Surface, holder: SurfaceHolder?) {
        player.setVideoSurface(surface)
    }

    override fun play(url: String) {
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.play()
    }

    override fun pause() {
        player.pause()
    }

    override fun resume() {
        player.play()
    }

    override fun seekTo(positionMs: Long) {
        player.seekTo(positionMs)
    }

    override fun setPlaybackSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
    }

    override val isPlaying: Boolean
        get() = player.isPlaying

    override fun release() {
        player.release()
    }
}