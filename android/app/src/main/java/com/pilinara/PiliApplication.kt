package com.pilinara

import android.app.Application
import com.pilinara.api.BiliApi
import com.pilinara.data.JsonFileStore
import com.pilinara.data.SearchHistoryStore
import com.pilinara.data.SettingsStore
import com.pilinara.net.Http
import com.pilinara.source.SourceManager
import com.pilinara.source.SourceRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.io.File

/**
 * 手工依赖容器（本项目刻意不引入 Hilt/Koin：少一层注解处理 = 更少的编译开销与方法数）。
 * 全应用单例：网络、设置、API、源管理共享同一实例，连接池/Cookie/缓存全局复用。
 */
class AppContainer(application: Application) {

    /** 供需要 Context 的场景（启动 Activity / Toast）使用。 */
    val appContext: android.content.Context = application.applicationContext

    val settings: SettingsStore = SettingsStore(application)

    val http: Http = Http(
        cacheDir = application.cacheDir,
        cookieFile = File(application.filesDir, "cookies.json"),
    )

    val files: JsonFileStore = JsonFileStore(application.filesDir)

    val api: BiliApi = BiliApi(http)

    val sources: SourceManager = SourceManager(http, files)

    val sourceRepository: SourceRepository = SourceRepository(http, sources)

    val searchHistory: SearchHistoryStore = SearchHistoryStore(files)
}

class PiliApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        // 读取本地小文件并把 VIP 配置同步到拦截器闸门（必须在首个网络请求前完成）。
        runBlocking(Dispatchers.IO) {
            container.settings.bootstrap()
            container.sources.load()
            container.searchHistory.load()
        }
        // 后台预热 B 站风控指纹与 WBI 密钥（不阻塞冷启动；接口内部幂等）。
        appScope.launch(Dispatchers.IO) {
            runCatching {
                container.api.ensureBuvid()
                container.api.nav()
            }
        }
    }

    companion object {
        private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    }
}
