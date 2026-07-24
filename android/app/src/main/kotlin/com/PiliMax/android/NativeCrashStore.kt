package com.PiliMax.android

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong

internal object NativeCrashStore {
    private const val DIRECTORY_NAME = "native_crashes"
    private const val MAX_REPORTS = 12
    private const val MAX_MESSAGE_LENGTH = 4096
    private const val MAX_STACK_LENGTH = 131_072
    private const val MAX_THREAD_NAME_LENGTH = 256
    private val recordSequence = AtomicLong()

    fun writeUncaught(context: Context, thread: Thread, error: Throwable) {
        val timestamp = System.currentTimeMillis()
        val record = baseRecord(context, timestamp, "android_uncaught").apply {
            put("severity", "fatal")
            put("module", moduleFrom(error))
            put("reason", "uncaught_exception")
            put("exceptionType", error.javaClass.name)
            put(
                "message",
                sanitizeAndTruncate(error.message ?: error.toString(), MAX_MESSAGE_LENGTH),
            )
            put(
                "threadName",
                sanitizeAndTruncate(thread.name, MAX_THREAD_NAME_LENGTH),
            )
            put("threadId", thread.id)
            put(
                "stackTrace",
                sanitizeAndTruncate(Log.getStackTraceString(error), MAX_STACK_LENGTH),
            )
        }
        writeRecord(context, record)
    }

    fun writeProcessExit(
        context: Context,
        recordId: String,
        timestamp: Long,
        reason: String,
        description: String,
        status: Int,
        importance: Int,
        pss: Long,
        rss: Long,
        processName: String,
        trace: String,
    ) {
        if (reason == "java_crash" &&
            hasNearbyUncaught(context, timestamp, processName)
        ) return
        val record = baseRecord(context, timestamp, "android_exit_info").apply {
            put("severity", "fatal")
            put("module", "android_process")
            put("reason", reason)
            put("exceptionType", "ApplicationExitInfo")
            put(
                "message",
                sanitizeAndTruncate(description.ifBlank { reason }, MAX_MESSAGE_LENGTH),
            )
            put("threadName", "unknown")
            put("processName", processName)
            put("status", status)
            put("importance", importance)
            put("pss", pss)
            put("rss", rss)
            put("stackTrace", sanitizeAndTruncate(trace, MAX_STACK_LENGTH))
        }
        writeRecord(context, record, recordId)
    }

    fun processExitRecordId(exitKey: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(exitKey.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        return "exit_$digest"
    }

    fun pendingReports(context: Context): List<Map<String, Any?>> {
        return reportDirectory(context)
            .listFiles { file -> file.extension == "json" }
            ?.sortedBy(File::lastModified)
            ?.mapNotNull { file ->
                try {
                    jsonToMap(JSONObject(file.readText())).toMutableMap().apply {
                        put("recordId", file.nameWithoutExtension)
                    }
                } catch (_: Exception) {
                    file.delete()
                    null
                }
            }
            ?: emptyList()
    }

    fun acknowledge(context: Context, recordIds: List<String>) {
        val directory = reportDirectory(context)
        for (recordId in recordIds) {
            if (!recordId.matches(Regex("^[A-Za-z0-9_-]{1,128}$"))) continue
            File(directory, "$recordId.json").delete()
        }
    }

    private fun baseRecord(context: Context, timestamp: Long, source: String) =
        JSONObject().apply {
            put("version", 1)
            put("timestamp", timestamp)
            put("source", source)
            put("pid", Process.myPid())
            put("processName", processName(context))
            put("packageName", context.packageName)
            put("appVersion", appVersion(context))
            put("androidRelease", Build.VERSION.RELEASE)
            put("sdk", Build.VERSION.SDK_INT)
            put("manufacturer", Build.MANUFACTURER)
            put("model", Build.MODEL)
        }

    private fun writeRecord(
        context: Context,
        record: JSONObject,
        stableRecordId: String? = null,
    ) {
        val directory = reportDirectory(context)
        val recordId = stableRecordId
            ?: "${record.optLong("timestamp")}_${Process.myPid()}_${recordSequence.incrementAndGet()}"
        val target = File(directory, "$recordId.json")
        val temporary = File(
            directory,
            "${recordId}_${Process.myPid()}_${recordSequence.incrementAndGet()}.tmp",
        )
        temporary.writeText(record.toString())
        if (!temporary.renameTo(target)) {
            temporary.copyTo(target, overwrite = true)
            temporary.delete()
        }
        directory.listFiles { file -> file.extension == "json" }
            ?.sortedByDescending(File::lastModified)
            ?.drop(MAX_REPORTS)
            ?.forEach(File::delete)
    }

    private fun reportDirectory(context: Context) =
        File(context.noBackupFilesDir, DIRECTORY_NAME).apply { mkdirs() }

    private fun hasNearbyUncaught(
        context: Context,
        timestamp: Long,
        processName: String,
    ): Boolean {
        return reportDirectory(context)
            .listFiles { file -> file.extension == "json" }
            ?.any { file ->
                try {
                    val json = JSONObject(file.readText())
                    json.optString("source") == "android_uncaught" &&
                        json.optString("processName") == processName &&
                        kotlin.math.abs(json.optLong("timestamp") - timestamp) <= 5000
                } catch (_: Exception) {
                    false
                }
            }
            ?: false
    }

    private fun moduleFrom(error: Throwable): String {
        for (frame in error.stackTrace) {
            val className = frame.className
            if (!className.startsWith("com.PiliMax.android.")) continue
            return className.removePrefix("com.PiliMax.android.").substringBefore('.')
        }
        return "android"
    }

    private fun appVersion(context: Context): String {
        return try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= 28) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName} ($versionCode)"
        } catch (_: Exception) {
            "unknown"
        }
    }

    private fun processName(context: Context): String =
        if (Build.VERSION.SDK_INT >= 28) Application.getProcessName() else context.packageName

    private fun jsonToMap(json: JSONObject): Map<String, Any?> = buildMap {
        for (key in json.keys()) {
            val value = json.opt(key)
            put(key, if (value == JSONObject.NULL) null else value)
        }
    }

    private fun truncate(value: String, maxLength: Int): String =
        if (value.length <= maxLength) value else value.substring(0, maxLength)

    private fun sanitizeAndTruncate(value: String, maxLength: Int): String =
        truncate(NativeCrashSanitizer.sanitize(value), maxLength)
}
