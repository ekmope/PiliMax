package com.pilinara.player

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.Toast

/**
 * 最小视频播放页：通过 [CorePlayerFactory] 创建所选内核（Media3 / VLC / MPV），
 * 用 [SurfaceView] 渲染，点击画面暂停/继续。
 */
class PlayerActivity : Activity(), SurfaceHolder.Callback {

    private var player: CorePlayer? = null
    private var backend: PlayerBackend = PlayerBackend.MEDIA3
    private var url: String = DEFAULT_URL
    private var surface: SurfaceView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        backend = CorePlayerFactory.parse(intent.getStringExtra(EXTRA_BACKEND))
        url = intent.getStringExtra(EXTRA_URL) ?: DEFAULT_URL

        val surfaceView = SurfaceView(this).apply {
            holder.addCallback(this@PlayerActivity)
            setOnClickListener { togglePlayPause() }
        }
        surface = surfaceView

        val label = TextView(this).apply {
            text = "内核：${backend.name}  点击画面 暂停/继续"
            setTextColor(Color.WHITE)
            textSize = 12f
            setPadding(16, 16, 16, 16)
            setBackgroundColor(Color.argb(120, 0, 0, 0))
        }

        setContentView(
            FrameLayout(this).apply {
                setBackgroundColor(Color.BLACK)
                addView(
                    surfaceView,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT,
                    ),
                )
                addView(
                    label,
                    FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        Gravity.TOP or Gravity.START,
                    ),
                )
            },
        )
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        val p = CorePlayerFactory(this).create(backend)
        player = p
        p.attachSurface(holder.surface, holder)
        p.play(url)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        // 交给各内核根据 media 尺寸自行适配布局。
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        releasePlayer()
    }

    private fun togglePlayPause() {
        val p = player ?: return
        if (p.isPlaying) {
            p.pause()
        } else {
            p.resume()
        }
    }

    private fun releasePlayer() {
        player?.release()
        player = null
    }

    override fun onDestroy() {
        releasePlayer()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_URL = "com.pilinara.player.extra.url"
        const val EXTRA_BACKEND = "com.pilinara.player.extra.backend"
        const val DEFAULT_URL =
            "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

        private const val MATCH_PARENT = ViewGroup.LayoutParams.MATCH_PARENT
    }
}