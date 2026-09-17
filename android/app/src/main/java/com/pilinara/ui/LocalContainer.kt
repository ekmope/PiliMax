package com.pilinara.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.pilinara.AppContainer
import com.pilinara.PiliApplication

/** 直接从 Application 取容器：全应用唯一实例，无需层层传参。 */
@Composable
fun rememberContainer(): AppContainer {
    val context = LocalContext.current
    return remember(context) {
        (context.applicationContext as PiliApplication).container
    }
}
