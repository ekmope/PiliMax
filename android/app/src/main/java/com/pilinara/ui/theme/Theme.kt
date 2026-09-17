package com.pilinara.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * PiliNara 品牌色：B 站粉为核心色，辅以冷调青。默认深色优先（AMOLED 纯黑是视频类应用
 * 在骁龙 8 Elite 上最省电的底色 —— OLED 黑色像素不发光）。
 */
val PiliPink = Color(0xFFFB7299)
val PiliPinkDeep = Color(0xFFE2487B)
val PiliCyan = Color(0xFF23ADE5)

private val LightColors = lightColorScheme(
    primary = PiliPinkDeep,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFD9E2),
    onPrimaryContainer = Color(0xFF3E001D),
    secondary = PiliCyan,
    tertiary = Color(0xFF6E5DFF),
    surface = Color(0xFFFBFAFA),
    background = Color(0xFFFBFAFA),
)

private val DarkColors = darkColorScheme(
    primary = PiliPink,
    onPrimary = Color(0xFF4A0023),
    primaryContainer = Color(0xFF73173B),
    onPrimaryContainer = Color(0xFFFFD9E2),
    secondary = PiliCyan,
    tertiary = Color(0xFFB7A6FF),
    surface = Color(0xFF100E0F),
    background = Color(0xFF0B090A),
    surfaceVariant = Color(0xFF21191C),
    onSurfaceVariant = Color(0xFFD2C2C6),
)

@Composable
fun PiliTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val colorScheme = when {
        // Android 12+ 动态取色；Android 17 上走 MONET 最新色表。
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)

        darkTheme -> DarkColors
        else -> LightColors
    }
    MaterialTheme(
        colorScheme = colorScheme,
        typography = PiliTypography,
        content = content,
    )
}
