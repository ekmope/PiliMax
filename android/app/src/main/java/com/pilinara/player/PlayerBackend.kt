package com.pilinara.player

/** 可切换的播放内核。 */
enum class PlayerBackend {
    /** 默认内核：AndroidX Media3 / ExoPlayer。 */
    MEDIA3,

    /** Videolan libVLC。 */
    VLC,

    /** libmpv（自拉取内核）。 */
    MPV,
}