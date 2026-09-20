package com.pilinara

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ManageSearch
import androidx.compose.material.icons.filled.Explore
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.pilinara.ui.common.FavoritesScreen
import com.pilinara.ui.common.PagedVideoListScreen
import com.pilinara.ui.home.HomeScreen
import com.pilinara.ui.mine.MineScreen
import com.pilinara.ui.mine.SettingsScreen
import com.pilinara.ui.search.SearchScreen
import com.pilinara.ui.source.SourceScreen
import com.pilinara.ui.theme.PiliTheme

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as PiliApplication).container

        setContent {
            val dynamicColor by container.settings.dynamicColor.collectAsState(initial = true)
            PiliTheme(dynamicColor = dynamicColor) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                ) {
                    AppRoot(container)
                }
            }
        }
    }
}

enum class Dest(
    val id: String,
    val label: String,
    /** 该页需要 B 站登录态；未登录时展示「去登录」提示而非报错。 */
    val needsLogin: Boolean = false,
) {
    HOME("home", "首页"),
    DYNAMIC("dynamic", "动态", true),
    HISTORY("history", "历史", true),
    FAVORITES("favorites", "收藏", true),
    SEARCH("search", "搜索"),
    SOURCES("sources", "源"),
    MINE("mine", "我的"),
    ;

    companion object {
        val DEFAULT_ORDER = listOf(
            HOME, DYNAMIC, HISTORY, FAVORITES, SEARCH, SOURCES, MINE,
        )

        /** 解析设置里的启用列表（至少保留两项；首页/我的为必备兜底）。 */
        fun enabledFrom(setting: String): List<Dest> {
            val ids = setting.split(',').map { it.trim() }.toSet()
            val list = DEFAULT_ORDER.filter { it.id in ids }
            return if (list.size >= 2) list else listOf(HOME, MINE)
        }
    }
}

@androidx.compose.runtime.Composable
private fun AppRoot(container: AppContainer) {
    val bottomTabsSetting by container.settings.bottomTabs
        .collectAsState(initial = "home,search,sources,mine")
    val tabs = remember(bottomTabsSetting) { Dest.enabledFrom(bottomTabsSetting) }
    var dest by remember { mutableStateOf(Dest.HOME) }
    var showSettings by remember { mutableStateOf(false) }
    // 全屏子页（视频详情）打开时隐藏底栏——B 站官方/bilipai 详情页都是沉浸式全屏，
    // 底部导航会挤压视频区与内容区。
    var immersive by remember { mutableStateOf(false) }

    // 底栏配置变化后，若当前页被移除则回到第一个启用页。
    androidx.compose.runtime.LaunchedEffect(tabs) {
        if (dest !in tabs) dest = tabs.first()
    }

    // 设置页为全屏覆盖层（返回即回到「我的」）。
    if (showSettings) {
        SettingsScreen(container = container, onBack = { showSettings = false })
        return
    }

    Scaffold(
        bottomBar = {
            if (!immersive) {
            NavigationBar {
                tabs.forEach { d ->
                    NavigationBarItem(
                        selected = dest == d,
                        onClick = { dest = d },
                        icon = {
                            Icon(
                                when (d) {
                                    Dest.HOME -> Icons.Filled.Home
                                    Dest.DYNAMIC -> Icons.Filled.Subscriptions
                                    Dest.HISTORY -> Icons.Filled.History
                                    Dest.FAVORITES -> Icons.Filled.Star
                                    Dest.SEARCH -> Icons.AutoMirrored.Filled.ManageSearch
                                    Dest.SOURCES -> Icons.Filled.Explore
                                    Dest.MINE -> Icons.Filled.Person
                                },
                                contentDescription = d.label,
                            )
                        },
                        label = { Text(d.label) },
                    )
                }
            }
            }
        },
    ) { padding ->
        androidx.compose.foundation.layout.Box(
            Modifier.fillMaxSize().padding(padding),
        ) {
            when (dest) {
                Dest.HOME -> HomeScreen(container, onImmersive = { immersive = it })
                Dest.DYNAMIC -> PagedVideoListScreen(
                    container = container,
                    title = "动态",
                    loginHint = "登录后查看关注的 UP 最新视频",
                    onImmersive = { immersive = it },
                    pageLoader = { page -> container.api.dynamicFeed(page) },
                )

                Dest.HISTORY -> PagedVideoListScreen(
                    container = container,
                    title = "历史",
                    loginHint = "登录后查看观看历史",
                    onImmersive = { immersive = it },
                    // 历史接口是游标式（max=0 取最近一批），一次性取完，不做分页。
                    paged = false,
                    pageLoader = {
                        container.api.history(100).map { h ->
                            com.pilinara.api.BiliVideo(
                                aid = h.aid,
                                bvid = h.bvid,
                                cid = h.history?.cid ?: 0L,
                                title = h.title,
                                pic = h.pic,
                                duration = h.duration,
                                tname = h.tname.orEmpty(),
                                owner = com.pilinara.api.BiliOwner(
                                    name = h.owner?.name.orEmpty(),
                                ),
                            )
                        }
                    },
                )

                Dest.FAVORITES -> FavoritesScreen(
                    container = container,
                    onImmersive = { immersive = it },
                )
                Dest.SEARCH -> SearchScreen(container, onImmersive = { immersive = it })
                Dest.SOURCES -> SourceScreen(container)
                Dest.MINE -> MineScreen(
                    container = container,
                    onOpenSettings = { showSettings = true },
                    onOpenSources = { dest = Dest.SOURCES },
                )
            }
        }
    }
}
