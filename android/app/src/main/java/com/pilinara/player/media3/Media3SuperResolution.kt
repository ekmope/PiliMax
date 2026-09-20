package com.pilinara.player.media3

import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 超分辨率目标尺寸计算（配合 Media3 的 LanczosResample 视频效果）。
 *
 * 移植自 pili++（loneshu7/PiliPlusPlus，GPL-3.0）
 * `android/app/src/main/kotlin/com/example/piliplus/Media3SuperResolution.kt`。
 *
 * 只放大不缩小：源分辨率已达标时返回 null（此时不挂 effect，省 GPU）。
 */
internal enum class Media3SuperResolutionMode {
    DISABLE,
    EFFICIENCY,
    QUALITY,
    ;

    companion object {
        fun fromName(value: String): Media3SuperResolutionMode = when (value.lowercase()) {
            "disable" -> DISABLE
            "efficiency" -> EFFICIENCY
            "quality" -> QUALITY
            else -> DISABLE
        }
    }
}

internal data class Media3SuperResolutionTarget(
    val width: Int,
    val height: Int,
)

internal fun resolveMedia3SuperResolutionTarget(
    mode: Media3SuperResolutionMode,
    sourceWidth: Int,
    sourceHeight: Int,
): Media3SuperResolutionTarget? {
    if (mode == Media3SuperResolutionMode.DISABLE || sourceWidth <= 0 || sourceHeight <= 0) {
        return null
    }
    val desiredScale: Double
    val maximumLongEdge: Int
    val maximumShortEdge: Int
    when (mode) {
        Media3SuperResolutionMode.DISABLE -> return null
        Media3SuperResolutionMode.EFFICIENCY -> {
            desiredScale = 1.5
            maximumLongEdge = 1920
            maximumShortEdge = 1080
        }

        Media3SuperResolutionMode.QUALITY -> {
            desiredScale = 2.0
            maximumLongEdge = 3840
            maximumShortEdge = 2160
        }
    }
    val longEdge = maxOf(sourceWidth, sourceHeight)
    val shortEdge = minOf(sourceWidth, sourceHeight)
    val scale = min(
        desiredScale,
        min(
            maximumLongEdge.toDouble() / longEdge,
            maximumShortEdge.toDouble() / shortEdge,
        ),
    )
    if (scale <= 1.0) return null
    return Media3SuperResolutionTarget(
        width = (sourceWidth * scale).roundToInt().coerceAtLeast(sourceWidth),
        height = (sourceHeight * scale).roundToInt().coerceAtLeast(sourceHeight),
    )
}
