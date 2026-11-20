package com.PiliMax.android

import android.content.Context
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject

/** Small, bounded release diagnostics. Never stores titles, routes, IDs or URLs. */
internal object PlaybackExitSnapshot {
    private const val PREFERENCES_NAME = "playback_exit_snapshot"
    private const val SNAPSHOT_KEY = "last_state"
    private const val MAX_EVENTS = 12
    private const val MAX_SNAPSHOT_AGE_MS = 24 * 60 * 60 * 1000L
    const val MAX_EXPORT_LENGTH = 8192
    private val booleanKeys = setOf(
        "enabled", "playing", "buffering", "hasMediaItem", "hasOwner",
        "hasPlaybackIntent", "isRecovering", "isBackground",
        "onlyAudio", "continueInBackground", "shutdownTimerActive", "metadataFallback",
    )
    private val enumKeys = setOf("status", "clearReason", "mediaKind")
    private val enumValue = Regex("^[A-Za-z0-9_.-]{1,64}$")

    data class ExitSnapshot(
        val json: String,
        val appVersion: String?,
        val ageMillis: Long,
        val playbackAgeMillis: Long?,
    )

    fun recordProcessStarted(context: Context) {
        val observedAt = System.currentTimeMillis()
        PiliMaxApplication.updateExitSnapshot {
            update(context, observedAt) {
                put("processStartedAt", observedAt)
                true
            }
        }
    }

    fun recordPlayback(context: Context, state: Map<*, *>) {
        val safeState = buildMap<String, Any> {
            for (key in booleanKeys) {
                (state[key] as? Boolean)?.let { put(key, it) }
            }
            for (key in enumKeys) {
                val value = state[key] as? String ?: continue
                if (value.matches(enumValue)) put(key, value)
            }
        }
        if (safeState.isEmpty()) return
        recordEvent(context, "playback", JSONObject(safeState))
    }

    fun recordActivityForeground(context: Context, foreground: Boolean) =
        recordEvent(context, "activityForeground", foreground)

    @JvmStatic
    fun recordForegroundService(context: Context, foreground: Boolean) =
        recordEvent(context, "foregroundService", foreground)

    @JvmStatic
    fun recordForegroundServiceStartFailed(context: Context) =
        recordEvent(context, "foregroundStartFailed", true)

    fun recordRestoreDecision(context: Context, decision: String, reason: String) {
        val observedAt = System.currentTimeMillis()
        PiliMaxApplication.updateExitSnapshot {
            update(context, observedAt) {
                put("restoreTimestamp", observedAt)
                put("restoreDecision", decision.take(32))
                put("restoreReason", NativeCrashSanitizer.sanitize(reason).take(128))
                true
            }
        }
    }

    fun forExit(context: Context, pid: Int, timestamp: Long): ExitSnapshot? {
        return try {
            val snapshot = read(context) ?: return null
            val capturedAt = snapshot.optLong("timestamp")
            if (snapshot.optInt("pid", -1) != pid || capturedAt > timestamp ||
                capturedAt <= 0 || timestamp - capturedAt > MAX_SNAPSHOT_AGE_MS
            ) return null
            val playbackAt = snapshot.optLong("playbackTimestamp")
            val json = snapshot.toString()
            if (json.length > MAX_EXPORT_LENGTH) return null
            ExitSnapshot(
                json = json,
                appVersion = snapshot.optString("appVersion").takeIf(String::isNotBlank),
                ageMillis = timestamp - capturedAt,
                playbackAgeMillis = playbackAt.takeIf { it in 1..timestamp }
                    ?.let { timestamp - it },
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun recordEvent(context: Context, key: String, value: Any) {
        val observedAt = System.currentTimeMillis()
        PiliMaxApplication.updateExitSnapshot {
            update(context, observedAt) {
                if (opt(key)?.toString() == value.toString()) return@update false
                put(key, value)
                put("${key}Timestamp", observedAt)
                val events = optJSONArray("events") ?: JSONArray()
                val retained = JSONArray()
                for (index in maxOf(0, events.length() - MAX_EVENTS + 1) until events.length()) {
                    retained.put(events.opt(index))
                }
                retained.put(JSONObject().apply {
                    put("time", observedAt)
                    put("kind", key)
                    put("value", value)
                })
                put("events", retained)
                true
            }
        }
    }

    // All access is serialized with exit collection, before the next Dart session
    // can replace the previous process's state. Only state changes write to disk.
    private fun update(context: Context, observedAt: Long, edit: JSONObject.() -> Boolean) {
        val snapshot = read(context)?.takeIf { it.optInt("pid") == Process.myPid() }
            ?: JSONObject().apply {
                put("pid", Process.myPid())
                put("appVersion", NativeCrashStore.appVersion(context))
            }
        if (!snapshot.edit()) return
        snapshot.put("timestamp", maxOf(snapshot.optLong("timestamp"), observedAt))
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit().putString(SNAPSHOT_KEY, snapshot.toString()).commit()
    }

    private fun read(context: Context): JSONObject? = try {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .getString(SNAPSHOT_KEY, null)?.let(::JSONObject)
    } catch (_: Exception) {
        null
    }
}
