package com.pilinara.player.media3

import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Media3 缓冲策略。
 *
 * 移植自 pili++（loneshu7/PiliPlusPlus，GPL-3.0）
 * `android/app/src/main/kotlin/com/example/piliplus/Media3BufferPolicy.kt`。
 *
 * 关键点：minBuffer 与 maxBuffer 必须**分别**约束。旧实现把 minBuffer 设成
 * `maxBuffer / 2`，弱网下缓冲上限被抬到 120s 时，minBuffer 会跟着涨到 60s——
 * 起播前要先填满一分钟数据，用户看到的就是「点开半天才出画面」。
 *
 * 直播保持 Media3 默认：其低延迟策略无法从点播的「缓冲时长」偏好推导。
 */
internal data class Media3BufferPolicy(
    val targetBufferBytes: Int,
    val minBufferMs: Int,
    val maxBufferMs: Int,
    val bufferForPlaybackMs: Int,
    val bufferForPlaybackAfterRebufferMs: Int,
    val backBufferDurationMs: Int,
)

internal fun resolveMedia3BufferPolicy(
    targetBufferBytes: Int,
    bufferDurationMs: Int,
    isLive: Boolean,
): Media3BufferPolicy? {
    if (isLive) return null
    val maximumMs = bufferDurationMs.coerceAtLeast(MIN_MEDIA3_BUFFER_DURATION_MS)
    val rebufferMs = minOf(DEFAULT_MEDIA3_REBUFFER_MS, maximumMs)
    return Media3BufferPolicy(
        targetBufferBytes = targetBufferBytes.coerceAtLeast(MIN_MEDIA3_TARGET_BUFFER_BYTES),
        minBufferMs = rebufferMs,
        maxBufferMs = maximumMs,
        bufferForPlaybackMs = minOf(DEFAULT_MEDIA3_PLAYBACK_MS, maximumMs),
        bufferForPlaybackAfterRebufferMs = rebufferMs,
        backBufferDurationMs = maximumMs,
    )
}

private const val MIN_MEDIA3_TARGET_BUFFER_BYTES = 64 * 1024
private const val MIN_MEDIA3_BUFFER_DURATION_MS = 500
private const val DEFAULT_MEDIA3_PLAYBACK_MS = 2500
private const val DEFAULT_MEDIA3_REBUFFER_MS = 5000
