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
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching { write(context, thread, throwable) }
            // EIO / ErrnoException 一类属于「磁盘层抖动」（缓存文件被系统回收、
            // 外部分区瞬断），把整个进程杀掉代价太大。吞掉并让线程退出：
            // OkHttp/协程会把 IO 失败以 IOException 形式回传给调用方，UI 层已有兜底。
            val isIoNoise = runCatching {
                var t: Throwable? = throwable
                while (t != null) {
                    if (t is android.system.ErrnoException &&
                        t.errno == android.system.OsConstants.EIO
                    ) {
                        return@runCatching true
                    }
                    // close failed: EIO 形态的包装异常（如来自 libcore 的 IOException）。
                    if ((t.message ?: "").contains("EIO")) return@runCatching true
                    t = t.cause
                }
                false
            }.getOrDefault(false)
            if (isIoNoise) {
                android.util.Log.e("CrashLog", "suppressed IO-noise crash on ${thread.name}", throwable)
                return@setDefaultUncaughtExceptionHandler
            }
            // 写日志后拉起崩溃展示页（独立 :crash 进程），把堆栈直接显示给用户截图，
            // 替代「需要 adb 才能拿日志」的困境。随后直接结束本进程，跳过系统崩溃弹窗。
            runCatching { CrashDisplayActivity.launch(context) }
            Thread.sleep(400)
            android.os.Process.killProcess(android.os.Process.myPid())
            kotlin.system.exitProcess(2)
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
