package com.PiliMax.android

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class NativeCrashChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getPendingReports" -> PiliMaxApplication.loadPendingReports(
                    context = context,
                    onSuccess = result::success,
                    onError = { error -> reportError(result, error) },
                )
                "acknowledgeReports" -> {
                    val recordIds = call.argument<List<*>>("recordIds")
                        ?.filterIsInstance<String>()
                        ?: emptyList()
                    PiliMaxApplication.acknowledgeReports(
                        context = context,
                        recordIds = recordIds,
                        onSuccess = { result.success(null) },
                        onError = { error -> reportError(result, error) },
                    )
                }
                else -> result.notImplemented()
            }
        } catch (exception: Exception) {
            result.error("native_crash_store_failed", exception.message, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun reportError(result: MethodChannel.Result, error: Throwable) {
        result.error("native_crash_store_failed", error.message, null)
    }

    private companion object {
        const val CHANNEL_NAME = "com.PiliMax.android/native_crash"
    }
}
