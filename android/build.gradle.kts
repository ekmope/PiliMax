// 顶层构建脚本：仅声明插件版本，不在此处 apply。
plugins {
    // AGP 9.0 起内置 Kotlin 支持（org.jetbrains.kotlin.android 不再需要、也不允许 apply）。
    id("com.android.application") version "9.4.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.3.21" apply false
}
