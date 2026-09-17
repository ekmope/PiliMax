package com.pilinara.plugin.api

import android.content.Context
import android.view.Surface

/**
 * 外部播放器内核统一契约。
 *
 * 实现方打包为独立「内核 APK」，由宿主在运行期通过 DexClassLoader 按需加载
 * （Media3 内置不需要实现本接口；VLC / MPV 等内核以插件形式分发）。
 *
 * 线程模型：除 [setCallback] 外，所有方法均可能在主线程被调用，
 * 实现需自行将控制操作串行化到内部播放线程；[Callback] 回调须投递到主线程。
 */
interface ExternalPlayerCore {

    /** 内核展示名，如 "VLC"。 */
    val name: String

    /** 宿主最先调用一次，用于初始化底层库（此时尚未打开媒体）。 */
    fun attach(context: Context)

    /** 打开媒体并开始缓冲；参数不可为 null（音频分离轨见 [PlaySpec.audioUrl]）。 */
    fun open(spec: PlaySpec)

    /** 绑定/解绑输出 Surface；surface 为 null 表示进入后台或销毁。 */
    fun setSurface(surface: Surface?, width: Int, height: Int)

    fun play()
    fun pause()

    /** 绝对时间跳转（毫秒）。 */
    fun seekTo(positionMs: Long)

    /** 0.25f..4f 播放倍速，不支持时静默忽略。 */
    fun setRate(rate: Float)

    /** 0f..1f 系统音量比例（内核内部软件音量）。 */
    fun setVolume(volume: Float)

    /** 释放全部原生资源；调用后对象不可再用。 */
    fun release()

    /**
     * 内核事件回调。所有方法均在**主线程**触发。
     */
    interface Callback {
        /** 首帧可渲染 / 缓冲结束。 */
        fun onReady()

        /** 开始缓冲（首帧前或卡顿）。 */
        fun onBuffering()

        /** 播放结束。 */
        fun onEnded()

        /** 致命错误，宿主会展示提示并退回内置内核可选。 */
        fun onError(message: String)

        /** 时长更新（毫秒），未知时为 0。 */
        fun onDuration(durationMs: Long)

        /** 播放位置周期回调（建议 500ms）。 */
        fun onPosition(positionMs: Long)

        /** 播放/暂停状态变化。 */
        fun onPlayingChanged(isPlaying: Boolean)
    }

    fun setCallback(callback: Callback)
}

/**
 * 跨 ClassLoader 传递的播放描述（仅含 framework/JDK 类型与本契约模块类型）。
 */
data class PlaySpec(
    val videoUrl: String,
    /** DASH 分离音轨；内核需以 input-slave / audio-file 等方式合流。 */
    val audioUrl: String?,
    val title: String,
    /** HTTP 自定义头（Referer / User-Agent / Cookie 等），音视频流均需携带。 */
    val headers: Map<String, String>,
    val startPositionMs: Long,
    /** false 时内核应强制软件解码。 */
    val hardwareDecode: Boolean,
    val rate: Float,
)
