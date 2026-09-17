// 外部播放器内核插件与宿主共享的契约模块。
// 宿主（:app）implementation 本模块并随 APK 打包；插件模块 compileOnly 引用，
// 运行时由宿主 ClassLoader 提供，从而保证接口类型在跨 DexClassLoader 时同一。
plugins {
    id("com.android.library")
}

android {
    namespace = "com.pilinara.plugin.api"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
