package com.pilinara.player

import android.content.Context

/**
 * 播放内核工厂：根据 [PlayerBackend] 创建对应的 [CorePlayer] 实现。
 *
 * 默认内核为 [PlayerBackend.MEDIA3]（Media3 / ExoPlayer）。
 */
class CorePlayerFactory(private val context: Context) {

    fun create(backend: PlayerBackend): CorePlayer = when (backend) {
        PlayerBackend.MEDIA3 -> Media3CorePlayer(context)
        PlayerBackend.VLC -> VlcCorePlayer(context)
        PlayerBackend.MPV -> MpvCorePlayer(context)
    }

    companion object {
        /** 解析后端名（大小写不敏感），未知值回退到默认内核。 */
        fun parse(name: String?): PlayerBackend = when (name?.trim()?.uppercase()) {
            "VLC" -> PlayerBackend.VLC
            "MPV" -> PlayerBackend.MPV
            else -> PlayerBackend.MEDIA3
        }

        fun defaultBackend(): PlayerBackend = PlayerBackend.MEDIA3
    }
}