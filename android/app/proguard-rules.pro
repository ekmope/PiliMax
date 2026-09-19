# Rust 核心 JNI 桥：native 以符号名回调，禁止混淆/裁剪。
-keep class com.pilinara.core.NativeCore { *; }

# 外部播放器内核插件通过 DexClassLoader 加载并按原始方法名实现契约，
# 契约类一旦被 R8 重命名，插件将出现 ClassCastException / AbstractMethodError。
-keep class com.pilinara.plugin.api.** { *; }

# kotlinx.serialization：序列化器在运行期通过注解（@Serializable/@SerialName）与反射
# 定位伴生对象的 serializer()。R8 full mode 默认会移除全部注解并内联/重命名
# @Serializable 类，导致 release 版字段名映射错乱、反序列化崩（debug 正常、release 闪退）。
# 必须：① 保留注解与签名；② 保留伴生对象 serializer() 查找链。规则取自 kotlinx.serialization 官方 README。
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}

-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}

-if @kotlinx.serialization.Serializable class ** {
    public static ** INSTANCE;
}
-keepclassmembers class <1> {
    public static <1> INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp 5 / Coil3 / Media3 均自带 consumer rules，这里仅兜底。
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
