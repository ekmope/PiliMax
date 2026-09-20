package com.pilinara.player.media3

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * 播放链路上的音频处理器：增益 / 峰值限幅 / 动态响度归一 / 一阶高低通 / 参量均衡。
 *
 * 移植自 pili++（loneshu7/PiliPlusPlus，GPL-3.0）
 * `android/app/src/main/kotlin/com/example/piliplus/AudioNormalizationProcessor.kt`，
 * 上游源头为 PiliPlus（bggRGjQaUbCoE）。本文件沿用 GPL-3.0。
 * 逻辑保持与上游一致，仅改包名并去掉 Flutter 通道相关的构造。
 *
 * 只处理 PCM 16bit / float；其余编码抛 [AudioProcessor.UnhandledAudioFormatException]，
 * 由 Media3 走原链路（不能为了「处理成功」而破坏不支持的格式）。
 */
internal class AudioNormalizationProcessor : BaseAudioProcessor() {

    @Volatile
    private var configuration: AudioNormalizationConfiguration? = null
    private var appliedConfiguration: AudioNormalizationConfiguration? = null
    private var limiterGain = 1.0
    private var dynamicGain = 1.0
    private var rmsSum = 0.0
    private var rmsFrames = 0
    private var previousInput = DoubleArray(0)
    private var previousOutput = DoubleArray(0)
    private var previousLowpassOutput = DoubleArray(0)
    private var equalizerStages = emptyList<EqualizerStage>()
    private var equalizerSampleRate = 0
    private var highpassAlpha = 1.0
    private var lowpassAlpha = 0.0

    fun setConfiguration(configuration: AudioNormalizationConfiguration?) {
        this.configuration = configuration
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT
        ) {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return inputAudioFormat
    }

    override fun isActive(): Boolean = super.isActive()

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        val outputBuffer = replaceOutputBuffer(inputBuffer.remaining()).order(inputBuffer.order())
        val activeConfiguration = configuration
        if (activeConfiguration !== appliedConfiguration) {
            resetState(activeConfiguration)
        }
        if (activeConfiguration == null) {
            outputBuffer.put(inputBuffer)
            outputBuffer.flip()
            return
        }
        val channels = inputAudioFormat.channelCount
        val sampleRate = inputAudioFormat.sampleRate
        if (previousInput.size != channels) {
            previousInput = DoubleArray(channels)
            previousOutput = DoubleArray(channels)
            previousLowpassOutput = DoubleArray(channels)
            equalizerStages.forEach { it.reset(channels) }
        }
        val highpassHz = activeConfiguration.highpassHz
        highpassAlpha = if (highpassHz != null) {
            val cutoff = highpassHz.coerceIn(1.0, sampleRate / 2.0 - 1.0)
            val rc = 1.0 / (2.0 * PI * cutoff)
            rc / (rc + 1.0 / sampleRate)
        } else {
            1.0
        }
        val lowpassHz = activeConfiguration.lowpassHz
        lowpassAlpha = if (lowpassHz != null) {
            val cutoff = lowpassHz.coerceIn(1.0, sampleRate / 2.0 - 1.0)
            val rc = 1.0 / (2.0 * PI * cutoff)
            (1.0 / sampleRate) / (rc + 1.0 / sampleRate)
        } else {
            0.0
        }
        val equalizerBands = activeConfiguration.equalizerBands.ifEmpty {
            val frequency = activeConfiguration.equalizerFrequencyHz
            val gain = activeConfiguration.equalizerGainDb
            val q = activeConfiguration.equalizerQ
            if (frequency != null && gain != null && q != null) {
                listOf(EqualizerBand(frequency, gain, q))
            } else {
                emptyList()
            }
        }
        if (equalizerSampleRate != sampleRate ||
            equalizerStages.size != equalizerBands.size
        ) {
            equalizerStages = equalizerBands.map { band ->
                val frequency = band.frequencyHz.coerceIn(1.0, sampleRate / 2.0 - 1.0)
                val omega = 2.0 * PI * frequency / sampleRate
                val alpha = sin(omega) / (2.0 * band.q)
                val amplitude = 10.0.pow(band.gainDb / 40.0)
                val cosine = cos(omega)
                val coefficients = when (band.type) {
                    "q" -> {
                        val denominator = 1.0 + alpha / amplitude
                        doubleArrayOf(
                            (1.0 + alpha * amplitude) / denominator,
                            (-2.0 * cosine) / denominator,
                            (1.0 - alpha * amplitude) / denominator,
                            (-2.0 * cosine) / denominator,
                            (1.0 - alpha / amplitude) / denominator,
                        )
                    }

                    "lowshelf" -> {
                        val beta = 2.0 * sqrt(amplitude) * alpha
                        val b0 = amplitude * ((amplitude + 1.0) -
                            (amplitude - 1.0) * cosine + beta)
                        val b1 = 2.0 * amplitude * ((amplitude - 1.0) -
                            (amplitude + 1.0) * cosine)
                        val b2 = amplitude * ((amplitude + 1.0) -
                            (amplitude - 1.0) * cosine - beta)
                        val a0 = (amplitude + 1.0) +
                            (amplitude - 1.0) * cosine + beta
                        val a1 = -2.0 * ((amplitude - 1.0) +
                            (amplitude + 1.0) * cosine)
                        val a2 = (amplitude + 1.0) +
                            (amplitude - 1.0) * cosine - beta
                        doubleArrayOf(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
                    }

                    "highshelf" -> {
                        val beta = 2.0 * sqrt(amplitude) * alpha
                        val b0 = amplitude * ((amplitude + 1.0) +
                            (amplitude - 1.0) * cosine + beta)
                        val b1 = -2.0 * amplitude * ((amplitude - 1.0) +
                            (amplitude + 1.0) * cosine)
                        val b2 = amplitude * ((amplitude + 1.0) +
                            (amplitude - 1.0) * cosine - beta)
                        val a0 = (amplitude + 1.0) -
                            (amplitude - 1.0) * cosine + beta
                        val a1 = 2.0 * ((amplitude - 1.0) -
                            (amplitude + 1.0) * cosine)
                        val a2 = (amplitude + 1.0) -
                            (amplitude - 1.0) * cosine - beta
                        doubleArrayOf(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
                    }

                    else -> error("Unsupported equalizer type: ${band.type}")
                }
                EqualizerStage(
                    coefficients = coefficients,
                    channelCount = channels,
                )
            }
            equalizerSampleRate = sampleRate
        }
        val frame = DoubleArray(channels)
        val windowFrames = if (activeConfiguration.dynamic) {
            maxOf(1, activeConfiguration.frameMs * sampleRate / 1000)
        } else {
            Int.MAX_VALUE
        }
        val releaseStep = (activeConfiguration.gain / sampleRate / RELEASE_SECONDS).coerceAtLeast(0.0)
        while (inputBuffer.hasRemaining()) {
            var framePeak = 0.0
            var frameSumSquares = 0.0
            repeat(channels) { channel ->
                val input = when (inputAudioFormat.encoding) {
                    C.ENCODING_PCM_16BIT -> inputBuffer.short / 32768.0
                    C.ENCODING_PCM_FLOAT -> inputBuffer.float.toDouble()
                    else -> error("Unexpected PCM encoding: ${inputAudioFormat.encoding}")
                }
                frame[channel] = if (highpassHz != null) {
                    val output = highpassAlpha * (previousOutput[channel] + input - previousInput[channel])
                    previousInput[channel] = input
                    previousOutput[channel] = output
                    output
                } else {
                    input
                }
                if (lowpassHz != null) {
                    val output = previousLowpassOutput[channel] +
                        lowpassAlpha * (frame[channel] - previousLowpassOutput[channel])
                    previousLowpassOutput[channel] = output
                    frame[channel] = output
                }
                equalizerStages.forEach { stage ->
                    frame[channel] = stage.process(frame[channel], channel)
                }
                framePeak = maxOf(framePeak, abs(frame[channel]))
                frameSumSquares += frame[channel] * frame[channel]
            }
            var effectiveGain = activeConfiguration.gain
            if (activeConfiguration.dynamic) {
                rmsSum += frameSumSquares
                rmsFrames += 1
                if (rmsFrames >= windowFrames) {
                    val rms = sqrt(rmsSum / (rmsFrames * channels))
                    val targetLevel = 10.0.pow(activeConfiguration.targetRmsDb / 20.0)
                    val desired = if (rms > 0.0) {
                        (targetLevel / rms).coerceIn(MIN_DYNAMIC_GAIN, activeConfiguration.maxGain)
                    } else {
                        activeConfiguration.maxGain
                    }
                    dynamicGain += (desired - dynamicGain) * activeConfiguration.smoothing.coerceIn(0.001, 1.0)
                    rmsSum = 0.0
                    rmsFrames = 0
                }
                effectiveGain = dynamicGain
            }
            val peakLimitedGain = if (framePeak == 0.0) {
                effectiveGain
            } else {
                min(effectiveGain, activeConfiguration.peak / framePeak)
            }
            limiterGain = if (peakLimitedGain < limiterGain) {
                peakLimitedGain
            } else {
                min(peakLimitedGain, limiterGain + releaseStep)
            }
            repeat(channels) { channel ->
                val processed = frame[channel] * limiterGain
                when (inputAudioFormat.encoding) {
                    C.ENCODING_PCM_16BIT -> outputBuffer.putShort(
                        (processed * 32767.0).toInt()
                            .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                            .toShort(),
                    )

                    C.ENCODING_PCM_FLOAT -> outputBuffer.putFloat(processed.toFloat())
                }
            }
        }
        outputBuffer.flip()
    }

    override fun onFlush() {
        resetState(configuration)
    }

    override fun onReset() {
        resetState(configuration)
    }

    private fun resetState(configuration: AudioNormalizationConfiguration?) {
        appliedConfiguration = configuration
        limiterGain = configuration?.gain ?: 1.0
        dynamicGain = configuration?.gain ?: 1.0
        rmsSum = 0.0
        rmsFrames = 0
        previousInput = DoubleArray(0)
        previousOutput = DoubleArray(0)
        previousLowpassOutput = DoubleArray(0)
        equalizerStages = emptyList()
        equalizerSampleRate = 0
        highpassAlpha = 1.0
        lowpassAlpha = 0.0
    }

    companion object {
        private const val RELEASE_SECONDS = 0.08
        private const val MIN_DYNAMIC_GAIN = 0.01
    }

    private class EqualizerStage(
        private val coefficients: DoubleArray,
        channelCount: Int,
    ) {
        private var input1 = DoubleArray(channelCount)
        private var input2 = DoubleArray(channelCount)
        private var output1 = DoubleArray(channelCount)
        private var output2 = DoubleArray(channelCount)

        fun reset(channelCount: Int) {
            input1 = DoubleArray(channelCount)
            input2 = DoubleArray(channelCount)
            output1 = DoubleArray(channelCount)
            output2 = DoubleArray(channelCount)
        }

        fun process(input: Double, channel: Int): Double {
            val output = coefficients[0] * input +
                coefficients[1] * input1[channel] +
                coefficients[2] * input2[channel] -
                coefficients[3] * output1[channel] -
                coefficients[4] * output2[channel]
            input2[channel] = input1[channel]
            input1[channel] = input
            output2[channel] = output1[channel]
            output1[channel] = output
            return output
        }
    }
}

internal data class EqualizerBand(
    val frequencyHz: Double,
    val gainDb: Double,
    val q: Double,
    val type: String = "q",
) {
    init {
        require(frequencyHz.isFinite() && frequencyHz > 0.0) {
            "Invalid equalizer frequency: $frequencyHz"
        }
        require(gainDb.isFinite()) { "Invalid equalizer gain: $gainDb" }
        require(q.isFinite() && q > 0.0) { "Invalid equalizer Q: $q" }
        require(type in setOf("q", "highshelf", "lowshelf")) {
            "Unsupported equalizer type: $type"
        }
    }
}

internal data class AudioNormalizationConfiguration(
    val gain: Double = 1.0,
    val peak: Double = 1.0,
    val filter: String? = null,
    val dynamic: Boolean = false,
    val targetRmsDb: Double = -16.0,
    val maxGain: Double = 10.0,
    val frameMs: Int = 1000,
    val smoothing: Double = 0.5,
    val highpassHz: Double? = null,
    val lowpassHz: Double? = null,
    val equalizerFrequencyHz: Double? = null,
    val equalizerGainDb: Double? = null,
    val equalizerQ: Double? = null,
    val equalizerBands: List<EqualizerBand> = emptyList(),
) {
    init {
        require(gain.isFinite() && gain >= 0.0) { "Invalid normalization gain: $gain" }
        require(peak.isFinite() && peak in 0.0..1.0) { "Invalid normalization peak: $peak" }
        require(targetRmsDb.isFinite()) { "Invalid normalization target: $targetRmsDb" }
        require(maxGain.isFinite() && maxGain >= 1.0) { "Invalid normalization max gain: $maxGain" }
        require(frameMs > 0) { "Invalid normalization frame: $frameMs" }
        require(smoothing.isFinite() && smoothing in 0.0..1.0) {
            "Invalid normalization smoothing: $smoothing"
        }
        require(highpassHz == null || highpassHz.isFinite() && highpassHz > 0.0) {
            "Invalid highpass frequency: $highpassHz"
        }
        require(lowpassHz == null || lowpassHz.isFinite() && lowpassHz > 0.0) {
            "Invalid lowpass frequency: $lowpassHz"
        }
        require(equalizerFrequencyHz == null || equalizerFrequencyHz.isFinite() && equalizerFrequencyHz > 0.0) {
            "Invalid equalizer frequency: $equalizerFrequencyHz"
        }
        require(equalizerGainDb == null || equalizerGainDb.isFinite()) {
            "Invalid equalizer gain: $equalizerGainDb"
        }
        require(equalizerQ == null || equalizerQ.isFinite() && equalizerQ > 0.0) {
            "Invalid equalizer Q: $equalizerQ"
        }
        require(
            listOf(equalizerFrequencyHz, equalizerGainDb, equalizerQ).count { it != null } in listOf(0, 3),
        ) {
            "Equalizer frequency, gain, and Q must be configured together"
        }
    }

    companion object {
        /** 从设置项构造；全部关闭时返回 null（处理器直通）。 */
        fun fromSettings(
            enabled: Boolean,
            gainDb: Float,
            dynamic: Boolean,
            targetRmsDb: Float,
            highpassHz: Float,
            lowpassHz: Float,
            eqEnabled: Boolean,
            eqFreqHz: Float,
            eqGainDb: Float,
            eqQ: Float,
        ): AudioNormalizationConfiguration? {
            if (!enabled && !eqEnabled) return null
            val gain = if (enabled) 10.0.pow(gainDb / 20.0) else 1.0
            return AudioNormalizationConfiguration(
                gain = gain,
                peak = 1.0,
                dynamic = enabled && dynamic,
                targetRmsDb = targetRmsDb.toDouble(),
                maxGain = 10.0,
                frameMs = 1000,
                smoothing = 0.5,
                highpassHz = if (enabled && highpassHz > 0f) highpassHz.toDouble() else null,
                lowpassHz = if (enabled && lowpassHz > 0f) lowpassHz.toDouble() else null,
                equalizerFrequencyHz = if (eqEnabled) eqFreqHz.toDouble() else null,
                equalizerGainDb = if (eqEnabled) eqGainDb.toDouble() else null,
                equalizerQ = if (eqEnabled) eqQ.toDouble() else null,
            )
        }
    }
}
