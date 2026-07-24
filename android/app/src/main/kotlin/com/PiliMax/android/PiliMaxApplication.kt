package com.PiliMax.android

import android.app.Application
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import java.util.concurrent.Executors

class PiliMaxApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AndroidMmkv.initialize(this)
        NativeCrashHandler.install(this)
        // Keep the API 30 type graph completely off Android 7-9 startup.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            executeCrashIo {
                ProcessExitCollector.collect(applicationContext)
            }
        }
    }

    internal companion object {
        private val mainHandler = Handler(Looper.getMainLooper())
        private val crashIoExecutor = Executors.newSingleThreadExecutor { task ->
            Thread(task, "PiliMax-exit-history").apply {
                isDaemon = true
            }
        }

        fun loadPendingReports(
            context: android.content.Context,
            onSuccess: (List<Map<String, Any?>>) -> Unit,
            onError: (Throwable) -> Unit,
        ) {
            executeCrashIo {
                try {
                    val reports = NativeCrashStore.pendingReports(context)
                    mainHandler.post { onSuccess(reports) }
                } catch (error: Throwable) {
                    mainHandler.post { onError(error) }
                }
            }
        }

        fun acknowledgeReports(
            context: android.content.Context,
            recordIds: List<String>,
            onSuccess: () -> Unit,
            onError: (Throwable) -> Unit,
        ) {
            executeCrashIo {
                try {
                    NativeCrashStore.acknowledge(context, recordIds)
                    mainHandler.post { onSuccess() }
                } catch (error: Throwable) {
                    mainHandler.post { onError(error) }
                }
            }
        }

        private fun executeCrashIo(operation: () -> Unit) {
            crashIoExecutor.execute {
                try {
                    Process.setThreadPriority(Process.THREAD_PRIORITY_BACKGROUND)
                } catch (_: Exception) {
                    // Work is already off the main thread; priority is best-effort.
                }
                operation()
            }
        }
    }
}
