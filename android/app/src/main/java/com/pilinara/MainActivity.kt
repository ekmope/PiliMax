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
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
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

private enum class Dest(val label: String) {
    HOME("首页"),
    SEARCH("搜索"),
    SOURCES("源"),
    MINE("我的"),
}

@androidx.compose.runtime.Composable
private fun AppRoot(container: AppContainer) {
    var dest by remember { mutableStateOf(Dest.HOME) }
    var showSettings by remember { mutableStateOf(false) }

    // 设置页为全屏覆盖层（返回即回到「我的」）。
    if (showSettings) {
        SettingsScreen(container = container, onBack = { showSettings = false })
        return
    }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Dest.entries.forEach { d ->
                    NavigationBarItem(
                        selected = dest == d,
                        onClick = { dest = d },
                        icon = {
                            Icon(
                                when (d) {
                                    Dest.HOME -> Icons.Filled.Home
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
        },
    ) { padding ->
        androidx.compose.foundation.layout.Box(
            Modifier.fillMaxSize().padding(padding),
        ) {
            when (dest) {
                Dest.HOME -> HomeScreen(container)
                Dest.SEARCH -> SearchScreen(container)
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
