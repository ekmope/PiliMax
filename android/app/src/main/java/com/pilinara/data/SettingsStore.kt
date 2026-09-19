package com.pilinara.data

import android.content.Context
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.pilinara.vip.VipTrialConfig
import com.pilinara.vip.VipTrialGate
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "pilinara_settings")

/**
 * 全部用户设置（DataStore Preferences）。
 * 启动时调用 [bootstrap] 把大会员配置同步到 [VipTrialGate]。
 */
class SettingsStore(private val context: Context) {

    private object Keys {
        val VIP_ENABLED = booleanPreferencesKey("vip_enabled")
        val VIP_TYPE = intPreferencesKey("vip_type")
        val VIP_EXTEND_DAYS = longPreferencesKey("vip_extend_days")

        val DANMAKU_ENABLED = booleanPreferencesKey("danmaku_enabled")
        val DANMAKU_MERGE_WINDOW = longPreferencesKey("danmaku_merge_window")
        val DANMAKU_OPACITY = floatPreferencesKey("danmaku_opacity")
        val DANMAKU_SCALE = floatPreferencesKey("danmaku_scale")
        val DANMAKU_SPEED = floatPreferencesKey("danmaku_speed")

        val DEFAULT_PLAYBACK_SPEED = floatPreferencesKey("default_speed")
        val AUDIO_ONLY = booleanPreferencesKey("audio_only")
        val PREFER_QN = intPreferencesKey("prefer_qn")
        val CDN_NODE = stringPreferencesKey("cdn_node")
        val DYNAMIC_COLOR = booleanPreferencesKey("dynamic_color")

        // 播放内核：media3（默认）/ vlc / mpv（后两者按需下载插件）。
        val PLAYER_CORE = stringPreferencesKey("player_core")
        // 解码模式：auto（硬解优先） / hard / soft。
        val DECODE_MODE = stringPreferencesKey("decode_mode")
        // 缓冲时长（毫秒）。
        val BUFFER_MS = intPreferencesKey("buffer_ms")
        // 是否允许 Hi-Res FLAC / 杜比音轨（默认关闭，避免无解码器设备无声）。
        val HIRES_AUDIO = booleanPreferencesKey("hires_audio")
        // 哔哩漫游式解析服务器（空=不启用）。
        val ROAMING_SERVER = stringPreferencesKey("roaming_server")
        // 信息流过滤竖屏视频（默认开：横屏长视频体验优先，可关）。
        val FILTER_VERTICAL = booleanPreferencesKey("filter_vertical")
        // 空降跳过（BilibiliSponsorBlock 社区数据，默认开）。
        val SPONSOR_SKIP = booleanPreferencesKey("sponsor_skip")
    }

    private fun <T> pref(key: Preferences.Key<T>, default: T): Flow<T> =
        context.dataStore.data
            // 设置文件损坏 / 存储层 IOException（如底层 close 返回 EIO）时，异常会顺着
            // Flow 冲进 Compose 的 collectAsState 收集协程——那里没有兜底，直接杀进程。
            // 所有设置读取一律降级为默认值：播放页是全部播放路径的汇合点，绝不能因
            // 一个可选设置的本地 IO 故障而闪退。
            .catch {
                com.pilinara.CrashLog.write(context, Thread.currentThread(), it)
                emit(androidx.datastore.preferences.core.emptyPreferences())
            }
            .map { it[key] ?: default }

    val vipEnabled = pref(Keys.VIP_ENABLED, true)
    val vipType = pref(Keys.VIP_TYPE, 2)
    val vipExtendDays = pref(Keys.VIP_EXTEND_DAYS, 3650L)

    val danmakuEnabled = pref(Keys.DANMAKU_ENABLED, true)
    val danmakuMergeWindow = pref(Keys.DANMAKU_MERGE_WINDOW, 10_000L)
    val danmakuOpacity = pref(Keys.DANMAKU_OPACITY, 0.82f)
    val danmakuScale = pref(Keys.DANMAKU_SCALE, 1.0f)
    val danmakuSpeed = pref(Keys.DANMAKU_SPEED, 1.0f)

    val defaultSpeed = pref(Keys.DEFAULT_PLAYBACK_SPEED, 1.0f)
    val audioOnly = pref(Keys.AUDIO_ONLY, false)
    val preferQn = pref(Keys.PREFER_QN, 127)
    val cdnNode = pref(Keys.CDN_NODE, "auto")
    val dynamicColor = pref(Keys.DYNAMIC_COLOR, true)

    val playerCore = pref(Keys.PLAYER_CORE, "media3")
    val decodeMode = pref(Keys.DECODE_MODE, "auto")
    val bufferMs = pref(Keys.BUFFER_MS, 50_000)
    val hiResAudio = pref(Keys.HIRES_AUDIO, false)
    val roamingServer = pref(Keys.ROAMING_SERVER, "")
    val filterVertical = pref(Keys.FILTER_VERTICAL, true)
    val sponsorSkip = pref(Keys.SPONSOR_SKIP, true)

    suspend fun bootstrap() {
        VipTrialGate.config = VipTrialConfig(
            enabled = vipEnabled.first(),
            vipType = vipType.first().toLong(),
            extendDays = vipExtendDays.first(),
        )
    }

    suspend fun setVip(config: VipTrialConfig) {
        VipTrialGate.config = config
        context.dataStore.edit { p ->
            p[Keys.VIP_ENABLED] = config.enabled
            p[Keys.VIP_TYPE] = config.vipType.toInt()
            p[Keys.VIP_EXTEND_DAYS] = config.extendDays
        }
    }

    suspend fun setDanmakuEnabled(v: Boolean) = edit { it[Keys.DANMAKU_ENABLED] = v }
    suspend fun setDanmakuMergeWindow(v: Long) = edit { it[Keys.DANMAKU_MERGE_WINDOW] = v }
    suspend fun setDanmakuOpacity(v: Float) = edit { it[Keys.DANMAKU_OPACITY] = v }
    suspend fun setDanmakuScale(v: Float) = edit { it[Keys.DANMAKU_SCALE] = v }
    suspend fun setDefaultSpeed(v: Float) = edit { it[Keys.DEFAULT_PLAYBACK_SPEED] = v }
    suspend fun setAudioOnly(v: Boolean) = edit { it[Keys.AUDIO_ONLY] = v }
    suspend fun setPreferQn(v: Int) = edit { it[Keys.PREFER_QN] = v }
    suspend fun setCdnNode(v: String) = edit { it[Keys.CDN_NODE] = v }
    suspend fun setDynamicColor(v: Boolean) = edit { it[Keys.DYNAMIC_COLOR] = v }
    suspend fun setPlayerCore(v: String) = edit { it[Keys.PLAYER_CORE] = v }
    suspend fun setDecodeMode(v: String) = edit { it[Keys.DECODE_MODE] = v }
    suspend fun setBufferMs(v: Int) = edit { it[Keys.BUFFER_MS] = v }
    suspend fun setHiResAudio(v: Boolean) = edit { it[Keys.HIRES_AUDIO] = v }
    suspend fun setRoamingServer(v: String) = edit { it[Keys.ROAMING_SERVER] = v }
    suspend fun setFilterVertical(v: Boolean) = edit { it[Keys.FILTER_VERTICAL] = v }
    suspend fun setSponsorSkip(v: Boolean) = edit { it[Keys.SPONSOR_SKIP] = v }

    private suspend fun edit(block: (MutablePreferences) -> Unit) {
        // 写入失败（文件损坏 / 存储 IO 错误）只记录，不向调用协程抛异常：
        // 调用方大多是 rememberCoroutineScope 的设置点击，未捕获即闪退。
        runCatching { context.dataStore.edit(block) }
            .onFailure { com.pilinara.CrashLog.write(context, Thread.currentThread(), it) }
    }
}
