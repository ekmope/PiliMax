package com.pilinara.player

import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable
import kotlin.math.max

/** Rust 核心输出的弹幕模型（字段名与 core/src/danmaku.rs 一致）。 */
@Serializable
data class Danmaku(
    val t: Double = 0.0,
    val mode: Int = 1,
    val color: Long = 0xFFFFFF,
    val text: String = "",
    val count: Int = 1,
)

private const val FIXED_DURATION_SEC = 4.5
private val ROLLING_MODES = setOf(1, 2, 3, 6)

private class Measured(
    val d: Danmaku,
    val display: String,
    val layout: TextLayoutResult,
)

private class Placed(val m: Measured, val lane: Int)

private class Fixed(val m: Measured, val slot: Int, val endAtSec: Double)

private class Placement(
    val rolling: List<Placed>,
    val fixed: List<Fixed>,
    val lanes: Int,
    val laneHeight: Float,
    val pxPerSec: Float,
)

/**
 * 弹幕渲染层。
 *
 * 轨道分配在尺寸/数据变化时一次性完成（按时间贪心），每帧只做线性插值绘制、无堆分配；
 * 暂停时帧循环降频，配合 Rust（Oryon 定向编译）的解析合并，实现低功耗弹幕渲染。
 */
@Composable
fun DanmakuLayer(
    danmaku: List<Danmaku>,
    enabled: Boolean,
    opacity: Float,
    scale: Float,
    positionProvider: () -> Long,
    isPlayingProvider: () -> Boolean,
    modifier: Modifier = Modifier,
) {
    if (!enabled || danmaku.isEmpty()) return

    val measurer = rememberTextMeasurer()
    val fontSize = (15f * scale).sp

    val measured = remember(danmaku, fontSize) {
        danmaku.map { d ->
            val display = if (d.count > 1) "${d.text} ×${d.count}" else d.text
            Measured(
                d,
                display,
                measurer.measure(
                    AnnotatedString(display),
                    style = TextStyle(fontSize = fontSize, fontWeight = FontWeight.Medium),
                ),
            )
        }
    }

    var viewport by remember { mutableStateOf(IntSize.Zero) }

    var frame by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        while (true) {
            if (isPlayingProvider()) {
                withInfiniteAnimationFrameNanos { frame = it / 1_000_000 }
            } else {
                frame = System.currentTimeMillis()
                delay(150)
            }
        }
    }

    val placement = remember(measured, viewport) {
        place(measured, viewport)
    }

    Canvas(modifier = modifier.fillMaxSize().onSizeChanged { viewport = it }) {
        @Suppress("UNUSED_EXPRESSION") frame
        if (viewport == IntSize.Zero) return@Canvas

        val posSec = positionProvider() / 1000.0
        val alpha = opacity.coerceIn(0.2f, 1f)

        // 顶部/底部固定弹幕。
        for (f in placement.fixed) {
            if (posSec < f.m.d.t || posSec > f.endAtSec) continue
            val ySlot = if (f.m.d.mode == 5) f.slot else placement.lanes - 1 - f.slot
            val y = ySlot * placement.laneHeight +
                (placement.laneHeight - f.m.layout.size.height) / 2f
            val x = (size.width - f.m.layout.size.width) / 2f
            drawDanmaku(f.m.layout, x, y, f.m.d.color, alpha)
        }

        // 滚动弹幕。
        for (p in placement.rolling) {
            val phase = (posSec - p.m.d.t).toFloat()
            if (phase < 0f) continue
            val x = size.width - phase * placement.pxPerSec
            if (x + p.m.layout.size.width < 0f || x > size.width) continue
            val y = p.lane * placement.laneHeight +
                (placement.laneHeight - p.m.layout.size.height) / 2f
            drawDanmaku(p.m.layout, x, y, p.m.d.color, alpha)
        }
    }
}

private fun place(measured: List<Measured>, viewport: IntSize): Placement {
    if (viewport.width == 0 || viewport.height == 0) {
        return Placement(emptyList(), emptyList(), 1, 0f, 0f)
    }
    val w = viewport.width.toFloat()
    val h = viewport.height.toFloat()
    // sp 已在 measure 时换算成 px；lane 高度按字号的 1.35 倍估计。
    val laneHeight = measured.firstOrNull()?.layout?.size?.height?.times(1.35f) ?: 40f
    val lanes = max(1, (h * 0.82f / laneHeight).toInt())
    val fixedSlots = max(2, lanes / 3)
    // 参考穿屏时间约 8.5 秒。
    val pxPerSec = w / 8.5f

    // 滚动轨道：同一轨道两条弹幕不能在入口处重叠。
    val tailTime = DoubleArray(lanes)
    val tailClearSec = FloatArray(lanes)
    val rolling = ArrayList<Placed>()
    for (m in measured.filter { it.d.mode in ROLLING_MODES }.sortedBy { it.d.t }) {
        val needClear = m.layout.size.width / pxPerSec
        var lane = -1
        var earliest = 0
        for (l in 0 until lanes) {
            if (tailTime[l] + tailClearSec[l] <= m.d.t) {
                lane = l
                break
            }
            if (tailTime[l] + tailClearSec[l] < tailTime[earliest] + tailClearSec[earliest]) {
                earliest = l
            }
        }
        if (lane < 0) lane = earliest
        rolling.add(Placed(m, lane))
        tailTime[lane] = m.d.t
        tailClearSec[lane] = needClear
    }

    // 顶部（5）/ 底部（4）固定轨道。
    val slotEnd = DoubleArray(fixedSlots)
    val fixed = ArrayList<Fixed>()
    for (m in measured.filter { it.d.mode == 4 || it.d.mode == 5 }.sortedBy { it.d.t }) {
        var slot = 0
        for (s in 0 until fixedSlots) {
            if (slotEnd[s] <= m.d.t) {
                slot = s
                break
            }
        }
        val end = m.d.t + FIXED_DURATION_SEC
        slotEnd[slot] = end
        fixed.add(Fixed(m, slot, end))
    }

    return Placement(rolling, fixed, lanes, laneHeight, pxPerSec)
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawDanmaku(
    layout: TextLayoutResult,
    x: Float,
    y: Float,
    rgb: Long,
    alpha: Float,
) {
    val fill = Color(
        red = ((rgb shr 16) and 0xFF) / 255f,
        green = ((rgb shr 8) and 0xFF) / 255f,
        blue = (rgb and 0xFF) / 255f,
        alpha = alpha,
    )
    val edge = Color.Black.copy(alpha = alpha * 0.6f)
    for ((dx, dy) in listOf(-1.6f to 0f, 1.6f to 0f, 0f to -1.6f, 0f to 1.6f)) {
        drawText(layout, color = edge, topLeft = Offset(x + dx, y + dy))
    }
    drawText(layout, color = fill, topLeft = Offset(x, y))
}
