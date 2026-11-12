package com.PiliMax.android

import android.content.Context
import android.os.Process
import org.json.JSONObject

/** Small, bounded release diagnostics. Never stores titles, routes, IDs or URLs. */
internal object PlaybackExitSnapshot {
    private const val PREFERENCES_NAME = "playback_exit_snapshot"
    private const val SNAPSHOT_KEY = "last_state"
    private val booleanKeys = setOf(
        "enabled", "playing", "buffering", "hasMediaItem", "hasOwner",
    )
    private val enumKeys = setOf("status", "clearReason", "mediaKind")

    fun recordPlayback(context: Context, state: Map<*, *>) {
        val safeState = buildMap<String, Any> {
            for (key in booleanKeys) {
                (state[key] as? Boolean)?.let { put(key, it) }
            }
            for (key in enumKeys) {
                val value = state[key] as? String ?: continue
                if (value.matches(Regex("^[A-Za-z0-9_.-]{1,64}$"))) put(key, value)
            }
        }
        PiliMaxApplication.updateExitSnapshot {
            update(context) { put("playback", JSONObject(safeState)) }
        }
    }

    fun recordRestoreDecision(context: Context, decision: String, reason: String) {
        PiliMaxApplication.updateExitSnapshot {
            update(context) {
                put("restoreDecision", decision.take(32))
                put("restoreReason", NativeCrashSanitizer.sanitize(reason).take(128))
            }
        }
    }

    fun forExit(context: Context, pid: Int, timestamp: Long): String {
        return try {
            val snapshot = read(context) ?: return ""
            val capturedAt = snapshot.optLong("timestamp")
            if (snapshot.optInt("pid", -1) != pid || capturedAt > timestamp ||
                capturedAt <= 0 || timestamp - capturedAt > 24 * 60 * 60 * 1000L
            ) return ""
            snapshot.toString().take(2048)
        } catch (_: Exception) {
            ""
        }
    }

    // All access is serialized with exit collection, before the next Dart session
    // can replace the previous process's state. Only state changes write to disk.
    private fun update(context: Context, edit: JSONObject.() -> Unit) {
        val snapshot = read(context)?.takeIf { it.optInt("pid") == Process.myPid() }
            ?: JSONObject().put("pid", Process.myPid())
        snapshot.put("timestamp", System.currentTimeMillis())
        snapshot.edit()
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
