import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.gradle.api.GradleException
import org.jetbrains.kotlin.konan.properties.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val agpMajorVersion = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
    .substringBefore('.')
    .toInt()
val builtInKotlinProperty = providers.gradleProperty("android.builtInKotlin").orNull
val isBuiltInKotlinEnabled = agpMajorVersion >= 9 &&
        (builtInKotlinProperty == null || builtInKotlinProperty.toBoolean())
val isDiagnosticRelease = providers.gradleProperty("pilimaxDiagnosticRelease")
    .orNull
    ?.toBoolean() == true
val diagnosticApplicationId = providers.gradleProperty("pilimaxDiagnosticApplicationId")
    .orElse("com.pilimax.debug")
val isDiagnosticImpellerEnabled = isDiagnosticRelease &&
        (providers.gradleProperty("pilimaxEnableImpeller").orNull?.toBoolean() == true)
if (!isBuiltInKotlinEnabled) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.PiliMax.android"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (isDiagnosticRelease) {
            diagnosticApplicationId.get()
        } else {
            "com.PiliMax.android"
        }
        manifestPlaceholders["enableImpeller"] = isDiagnosticImpellerEnabled.toString()
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packagingOptions.jniLibs.useLegacyPackaging = true

    val keyProperties = Properties().also {
        val properties = rootProject.file("key.properties")
        if (properties.exists())
            it.load(properties.inputStream())
    }

    val config = keyProperties.getProperty("storeFile")?.let {
        signingConfigs.create("release") {
            storeFile = file(it)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildFeatures {
        if (project.hasProperty("dev") || isDiagnosticRelease) {
            resValues = true
        }
    }

    buildTypes {
        release {
            if (isDiagnosticRelease) {
                signingConfig = config
                    ?: throw GradleException("Missing diagnostic release signing config. Create android/key.properties.")
                resValue(
                    type = "string",
                    name = "app_name",
                    value = if (isDiagnosticImpellerEnabled) {
                        "PiliMax FPS Impeller"
                    } else {
                        "PiliMax FPS Skia"
                    },
                )
            } else if (project.hasProperty("dev")) {
                signingConfig = config ?: signingConfigs["debug"]
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "PiliMax dev",
                )
            } else {
                signingConfig = config
                    ?: throw GradleException("Missing release signing config. Create android/key.properties or configure GitHub Actions signing secrets.")
            }
//            proguardFiles(
//                getDefaultProguardFile("proguard-android-optimize.txt"),
//                "proguard-rules.pro"
//            )
        }
        debug {
            signingConfig = signingConfigs["debug"]
            applicationIdSuffix = ".debug"
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = flutter.versionCode
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.tencent:mmkv-static:1.3.14")
}
