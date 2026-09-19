package com.pilinara.ui.source

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.viewinterop.AndroidView
import com.pilinara.PiliApplication
import com.pilinara.net.Http
import java.net.URI

/**
 * 订阅源账号登录：WebView 打开源站首页，用户自行登录；
 * 期间 WebView 的 Cookie 实时同步进全局 [Http.cookieJar]，
 * 之后该源的所有抓取/解析请求自动携带登录态（会员集数、用户书架等）。
 * 登录态仅落本机，不上传任何地方。
 */
@OptIn(ExperimentalMaterial3Api::class)
class SourceLoginActivity : ComponentActivity() {

    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as PiliApplication).container
        val host = intent.getStringExtra(EXTRA_HOST).orEmpty()
        val name = intent.getStringExtra(EXTRA_NAME).orEmpty()
        if (host.isEmpty()) {
            finish()
            return
        }
        val startUrl = intent.getStringExtra(EXTRA_URL) ?: "https://$host/"

        // WebView 自带 CookieManager → 全局 jar：登录一次，OkHttp 全链路可用。
        CookieManager.getInstance().setAcceptCookie(true)

        setContentView(
            ComposeView(this).apply {
                setContent {
                    var title by mutableStateOf("登录 $name")
                    BackHandler { finish() }
                    Scaffold(
                        topBar = {
                            TopAppBar(
                                title = { Text(title, maxLines = 1) },
                                navigationIcon = {
                                    IconButton(onClick = { finish() }) {
                                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                                    }
                                },
                                actions = {
                                    IconButton(onClick = { finish() }) {
                                        Icon(Icons.Filled.Close, "完成")
                                    }
                                },
                            )
                        },
                    ) { padding ->
                        AndroidView(
                            modifier = Modifier.fillMaxSize().padding(padding),
                            factory = { ctx ->
                                WebView(ctx).apply {
                                    settings.javaScriptEnabled = true
                                    settings.domStorageEnabled = true
                                    settings.userAgentString = Http.UA_WEB
                                    webViewClient = object : WebViewClient() {
                                        override fun onPageFinished(view: WebView?, url: String?) {
                                            super.onPageFinished(view, url)
                                            title = view?.title?.takeIf { it.isNotBlank() }
                                                ?: "登录 $name"
                                            syncCookies(container.http, host)
                                        }

                                        override fun shouldOverrideUrlLoading(
                                            view: WebView?,
                                            request: WebResourceRequest?,
                                        ): Boolean {
                                            // 站外跳转（如第三方 OAuth）也允许在本 WebView 内完成。
                                            return false
                                        }
                                    }
                                    webView = this
                                    loadUrl(startUrl)
                                }
                            },
                        )
                    }
                }
            },
        )
    }

    override fun onDestroy() {
        // 退出前再同步一次，保证登录 Cookie 不丢。
        runCatching {
            syncCookies((application as PiliApplication).container.http, intent.getStringExtra(EXTRA_HOST).orEmpty())
        }
        webView?.destroy()
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_HOST = "host"
        private const val EXTRA_NAME = "name"
        private const val EXTRA_URL = "url"

        fun intent(context: Context, host: String, name: String, url: String? = null): Intent =
            Intent(context, SourceLoginActivity::class.java)
                .putExtra(EXTRA_HOST, host)
                .putExtra(EXTRA_NAME, name)
                .putExtra(EXTRA_URL, url)

        /** 把 WebView CookieManager 里该域（含子域）的 Cookie 灌进全局 jar。 */
        fun syncCookies(http: Http, host: String) {
            val raw = CookieManager.getInstance().getCookie("https://$host/") ?: return
            raw.split(';').forEach { pair ->
                val idx = pair.indexOf('=')
                if (idx <= 0) return@forEach
                val n = pair.substring(0, idx).trim()
                val v = pair.substring(idx + 1).trim()
                if (n.isEmpty() || v.isEmpty()) return@forEach
                http.cookieJar.put(host, n, v, maxAgeSeconds = 30L * 24 * 3600)
            }
        }

        fun hostOf(url: String): String = runCatching { URI(url).host }.getOrDefault("")
    }
}
