package com.PiliMax.android

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.io.ByteArrayOutputStream
import java.io.InputStream

internal object ProcessExitCollector {
    private const val PREFERENCES_NAME = "native_crash_exit_state"
    private const val LAST_EXIT_TIMESTAMP = "last_exit_timestamp"
    private const val LAST_EXIT_KEYS = "last_exit_keys"
    private const val MAX_TRACE_BYTES = 131_072
    private const val FIRST_COLLECTION_WINDOW_MS = 10 * 60 * 1000L

    fun collect(context: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        try {
            val activityManager = context.getSystemService(ActivityManager::class.java) ?: return
            val exits = activityManager.getHistoricalProcessExitReasons(
                context.packageName,
                0,
                32,
            )
            val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            val initialized = preferences.contains(LAST_EXIT_TIMESTAMP)
            if (exits.isEmpty()) {
                if (!initialized) {
                    persistCursor(
                        context = context,
                        timestamp = System.currentTimeMillis(),
                        keys = emptySet(),
                    )
                }
                return
            }
            val latestTimestamp = exits.maxOf { it.timestamp }
            val lastTimestamp = if (initialized) {
                preferences.getLong(LAST_EXIT_TIMESTAMP, 0)
            } else {
                System.currentTimeMillis() - FIRST_COLLECTION_WINDOW_MS
            }
            val lastKeys = if (initialized) {
                preferences.getStringSet(LAST_EXIT_KEYS, emptySet())?.toSet() ?: emptySet()
            } else {
                emptySet()
            }
            exits.asSequence()
                .filter {
                    it.timestamp > lastTimestamp ||
                        (it.timestamp == lastTimestamp && exitKey(it) !in lastKeys)
                }
                .filter(::isReportable)
                .sortedBy { it.timestamp }
                .forEach { info -> writeExit(context, info) }
            val latestKeys = exits.asSequence()
                .filter { it.timestamp == latestTimestamp }
                .map(::exitKey)
                .toSet()
            val nextTimestamp = maxOf(lastTimestamp, latestTimestamp)
            val nextKeys = when {
                latestTimestamp > lastTimestamp -> latestKeys
                latestTimestamp == lastTimestamp -> lastKeys + latestKeys
                else -> lastKeys
            }
            persistCursor(
                context = context,
                timestamp = nextTimestamp,
                keys = nextKeys,
            )
        } catch (_: Exception) {
            // Exit history is best-effort and varies across OEM implementations.
        } catch (_: LinkageError) {
            // Older or modified frameworks may not expose the expected API surface.
        }
    }

    private fun isReportable(info: ApplicationExitInfo): Boolean {
        return when (info.reason) {
            ApplicationExitInfo.REASON_CRASH,
            ApplicationExitInfo.REASON_CRASH_NATIVE,
            ApplicationExitInfo.REASON_ANR,
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE,
            -> true
            else -> false
        }
    }

    private fun writeExit(context: Context, info: ApplicationExitInfo) {
        val trace = if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
            // Native crash traces are tombstone protobufs, not UTF-8 text.
            // Keep them out of the local text report instead of emitting
            // binary noise which cannot be safely redacted or shared.
            "Native tombstone trace omitted (binary protobuf)."
        } else {
            try {
                readTrace(info.traceInputStream)
            } catch (_: Exception) {
                ""
            }
        }
        NativeCrashStore.writeProcessExit(
            context = context,
            recordId = NativeCrashStore.processExitRecordId(exitKey(info)),
            timestamp = info.timestamp,
            reason = reasonName(info.reason),
            description = info.description ?: "",
            status = info.status,
            importance = info.importance,
            pss = info.pss,
            rss = info.rss,
            processName = info.processName,
            trace = trace,
        )
    }

    private fun readTrace(input: InputStream?): String {
        if (input == null) return ""
        return try {
            input.use { stream ->
                val buffer = ByteArray(8192)
                val output = ByteArrayOutputStream()
                while (output.size() < MAX_TRACE_BYTES) {
                    val count = stream.read(
                        buffer,
                        0,
                        minOf(buffer.size, MAX_TRACE_BYTES - output.size()),
                    )
                    if (count <= 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray().toString(Charsets.UTF_8).replace("\u0000", "")
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_CRASH -> "java_crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
        else -> "reason_$reason"
    }

    private fun exitKey(info: ApplicationExitInfo): String =
        "${info.timestamp}|${info.pid}|${info.reason}|${info.status}|${info.processName}"

    private fun persistCursor(
        context: Context,
        timestamp: Long,
        keys: Set<String>,
    ) {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val storedTimestamp = preferences.getLong(LAST_EXIT_TIMESTAMP, Long.MIN_VALUE)
        val storedKeys = preferences.getStringSet(LAST_EXIT_KEYS, emptySet())?.toSet() ?: emptySet()
        val mergedTimestamp = maxOf(storedTimestamp, timestamp)
        val mergedKeys = when {
            timestamp > storedTimestamp -> keys
            timestamp == storedTimestamp -> storedKeys + keys
            else -> storedKeys
        }
        // A failed synchronous commit deliberately leaves the old cursor in place.
        // Stable process-exit record IDs make the resulting retry idempotent.
        preferences.edit()
            .putLong(LAST_EXIT_TIMESTAMP, mergedTimestamp)
            .putStringSet(LAST_EXIT_KEYS, mergedKeys)
            .commit()
    }
}
