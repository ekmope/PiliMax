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
    }

    private fun <T> pref(key: Preferences.Key<T>, default: T): Flow<T> =
        context.dataStore.data.map { it[key] ?: default }

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

    private suspend fun edit(block: (MutablePreferences) -> Unit) {
        context.dataStore.edit(block)
    }
}
