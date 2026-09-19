package com.pilinara

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * 崩溃展示页：运行在独立 `:crash` 进程。
 *
 * 之前几轮「打开就闪退」一直无法定位，根因是拿不到真实堆栈——用户没有 adb，
 * crash.log 又在 Android/data 里不好找。本页在任意未捕获异常发生后被拉起，
 * 把最近一次崩溃的完整堆栈直接渲染在屏幕上，用户截图即可反馈。
 *
 * 刻意用纯代码 View（不依赖 Compose / 主题资源）：如果崩溃本身就是 Compose
 * 或资源初始化问题，本页仍必须能显示。独立进程保证主进程即便在
 * Application.onCreate 阶段崩溃，本页也不会被连带杀死。
 */
class CrashDisplayActivity : Activity() {

    private var crashText: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crashText = readLatestCrash()
        runCatching { buildUi() }
            .onFailure {
                // 兜底：连 LinearLayout 都建不起来时，至少给一个能显示的 TextView。
                setContentView(
                    TextView(this).apply {
                        text = crashText.ifEmpty { "发生崩溃，但无法读取崩溃日志。" }
                        setTextColor(Color.WHITE)
                        setTypeface(Typeface.MONOSPACE, Typeface.NORMAL)
                    },
                )
            }
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#0B090A"))
            setPadding(dp(16), dp(44), dp(16), dp(16))
        }

        root.addView(
            TextView(this).apply {
                text = "PiliNara 发生崩溃"
                setTextColor(Color.parseColor("#FB7299"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
                setTypeface(typeface, Typeface.BOLD)
            },
        )
        root.addView(
            TextView(this).apply {
                text = "请截图下方完整内容发给开发者，这是定位问题最直接的依据。" +
                    "也可以点「复制」后粘贴到任意输入框。"
                setTextColor(Color.parseColor("#D2C2C6"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setPadding(0, dp(6), 0, dp(14))
            },
        )

        val btnRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, 0, 0, dp(12))
        }
        btnRow.addView(makeButton("复制崩溃信息") { copyCrash() })
        btnRow.addView(makeButton("重启应用") { restart() })
        root.addView(btnRow)

        val scroll = ScrollView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            )
            setBackgroundColor(Color.parseColor("#141012"))
        }
        val hscroll = HorizontalScrollView(this)
        hscroll.addView(
            TextView(this).apply {
                text = crashText.ifEmpty { "（未读到崩溃日志，可能崩溃发生在日志写入之前）" }
                setTextColor(Color.parseColor("#E8E0E2"))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                setTypeface(Typeface.MONOSPACE, Typeface.NORMAL)
                setTextIsSelectable(true)
                setPadding(dp(10), dp(10), dp(10), dp(10))
            },
        )
        scroll.addView(hscroll)
        root.addView(scroll)

        setContentView(root)
    }

    private fun makeButton(label: String, onClick: () -> Unit): Button =
        Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.parseColor("#FB7299"))
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            lp.marginEnd = dp(10)
            layoutParams = lp
            gravity = Gravity.CENTER
            setOnClickListener { onClick() }
        }

    private fun copyCrash() {
        runCatching {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("pilinara-crash", crashText))
            Toast.makeText(this, "已复制，粘贴发给开发者即可", Toast.LENGTH_SHORT).show()
        }
    }

    private fun restart() {
        runCatching {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            startActivity(intent)
        }
        // 结束崩溃进程；主进程由系统随 MainActivity 重新拉起。
        android.os.Process.killProcess(android.os.Process.myPid())
        kotlin.system.exitProcess(0)
    }

    /** 读取 crash.log 末尾一段（最近一次崩溃），限制长度避免 TextView 过大。 */
    private fun readLatestCrash(): String = runCatching {
        val dir = getExternalFilesDir(null) ?: filesDir
        val f = java.io.File(dir, "crash.log")
        if (!f.exists()) return@runCatching ""
        val bytes = f.readBytes()
        val keep = minOf(bytes.size, 16 * 1024)
        String(bytes, bytes.size - keep, keep, Charsets.UTF_8)
    }.getOrDefault("")

    private fun dp(v: Int): Int =
        (v * resources.displayMetrics.density).toInt()

    companion object {
        /** 供 CrashLog 在崩溃发生后拉起本页。 */
        fun launch(context: Context) {
            val intent = Intent(context, CrashDisplayActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
            context.startActivity(intent)
        }
    }
}
