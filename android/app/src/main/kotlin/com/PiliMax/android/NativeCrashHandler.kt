package com.PiliMax.android

import android.content.Context
import android.os.Process
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.system.exitProcess

internal class NativeCrashHandler private constructor(
    private val context: Context,
    private val previous: Thread.UncaughtExceptionHandler?,
) : Thread.UncaughtExceptionHandler {
    private val handling = AtomicBoolean(false)

    override fun uncaughtException(thread: Thread, error: Throwable) {
        if (handling.compareAndSet(false, true)) {
            try {
                NativeCrashStore.writeUncaught(context, thread, error)
            } catch (_: Throwable) {
                // A fatal path must always continue to Android's original handler.
            }
        }
        val delegate = previous
        if (delegate != null && delegate !== this) {
            delegate.uncaughtException(thread, error)
        } else {
            Process.killProcess(Process.myPid())
            exitProcess(10)
        }
    }

    companion object {
        fun install(context: Context) {
            val current = Thread.getDefaultUncaughtExceptionHandler()
            if (current is NativeCrashHandler) return
            Thread.setDefaultUncaughtExceptionHandler(
                NativeCrashHandler(context.applicationContext, current),
            )
        }
    }
}
