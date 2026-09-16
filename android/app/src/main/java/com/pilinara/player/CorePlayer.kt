package com.pilinara.player

import android.view.Surface
import android.view.SurfaceHolder

/**
 * 统一播放内核抽象：屏蔽 Media3 / VLC / MPV 三套后端的差异。
 *
 * 上层（[PlayerActivity] 等）只需面向该接口编程，配合 [CorePlayerFactory] 即可动态切换内核。
 */
interface CorePlayer {
    val backend: PlayerBackend

    /** 绑定渲染 [Surface]（在 [play] 之前调用）。 */
    fun attachSurface(surface: Surface, holder: SurfaceHolder?)

    /** 加载并播放指定 URL。 */
    fun play(url: String)

    fun pause()

    fun resume()

    /** 跳转到指定位置（毫秒）。 */
    fun seekTo(positionMs: Long)

    /** 设置倍速。 */
    fun setPlaybackSpeed(speed: Float)

    val isPlaying: Boolean

    /** 释放播放资源。 */
    fun release()
}