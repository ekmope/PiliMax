package com.pilinara

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 全局崩溃日志。
 *
 * 安装后，任意线程的未捕获异常（如 MediaController 连接失败、服务初始化异常）
 * 会先追加写入 `Android/data/com.pilinara/files/crash.log`，再交给系统默认处理器，
 * 方便在没有 adb / logcat 的情况下定位「点播放就闪退」类问题。
 */
object CrashLog {
    private const val NAME = "crash.log"
    private const val MAX_BYTES = 512 * 1024

    fun install(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching { write(context, thread, throwable) }
            previous?.uncaughtException(thread, throwable)
        }
    }

    @Synchronized
    fun write(context: Context, thread: Thread, t: Throwable) {
        val sw = StringWriter()
        t.printStackTrace(PrintWriter(sw))
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
        val section = "----- $stamp thread=${thread.name} -----\n$sw\n"

        val dir = context.getExternalFilesDir(null) ?: context.filesDir
        val f = File(dir, NAME)
        f.appendText(section)
        if (f.length() > MAX_BYTES) {
            val bytes = f.readBytes()
            val keep = MAX_BYTES * 3 / 4
            f.writeBytes(bytes.copyOfRange(bytes.size - keep, bytes.size))
        }
    }

    fun file(context: Context): File =
        File(context.getExternalFilesDir(null) ?: context.filesDir, NAME)
}
