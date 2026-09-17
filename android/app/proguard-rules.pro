# Rust 核心 JNI 桥：native 以符号名回调，禁止混淆/裁剪。
-keep class com.pilinara.core.NativeCore { *; }

# 外部播放器内核插件通过 DexClassLoader 加载并按原始方法名实现契约，
# 契约类一旦被 R8 重命名，插件将出现 ClassCastException / AbstractMethodError。
-keep class com.pilinara.plugin.api.** { *; }

# kotlinx.serialization 生成的 serializer 全静态可达，无需保留 @Serializable 模型；
# 但保留实体类成员以稳妥规避 R8 full mode 的激进内联。
-keepclassmembers class com.pilinara.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp 5 / Coil3 / Media3 均自带 consumer rules，这里仅兜底。
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
