package com.pilinara.player.external

import android.content.Context
import com.pilinara.BuildConfig
import com.pilinara.plugin.api.ExternalPlayerCore
import dalvik.system.PathClassLoader
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.zip.ZipFile

/**
 * 外部播放器内核（VLC / MPV）的下载、校验与动态加载。
 *
 * 插件是一个仅含代码与原生库的 APK：
 * 1. 下载到 filesDir/cores/<id>/core.apk（原子替换）；
 * 2. 校验 ZIP 结构、classes.dex、入口类存在；
 * 3. 将 lib 下对应 ABI 的 .so 解包到 lib/（PathClassLoader 原生库搜索路径）；
 * 4. 以宿主 ClassLoader 为 parent 构造 PathClassLoader，反射实例化入口。
 */
class PlayerCoreManager(private val context: Context) {

    enum class CoreId(
        val settingId: String,
        val displayName: String,
        val entryClass: String,
        val defaultUrl: String,
    ) {
        MEDIA3("media3", "Media3（内置）", "", ""),
        VLC(
            "vlc", "VLC",
            "com.pilinara.plugin.vlc.VlcCore",
            BuildConfig.CORE_URL_VLC,
        ),
        MPV(
            "mpv", "MPV",
            "com.pilinara.plugin.mpv.MpvCore",
            BuildConfig.CORE_URL_MPV,
        );

        companion object {
            fun ofSetting(id: String?): CoreId =
                entries.firstOrNull { it.settingId == id } ?: MEDIA3
        }
    }

    private val root: File = File(context.filesDir, "cores")

    private fun dir(id: CoreId) = File(root, id.settingId)
    private fun apk(id: CoreId) = File(dir(id), "core.apk")
    private fun libDir(id: CoreId) = File(dir(id), "lib")

    fun isInstalled(id: CoreId): Boolean {
        if (id == CoreId.MEDIA3) return true
        val f = apk(id)
        return f.isFile && f.length() > 1024
    }

    /** 已安装内核版本（APK 大小 + 修改时间派生的简要标识），未安装返回 null。 */
    fun installedLabel(id: CoreId): String? {
        if (!isInstalled(id)) return null
        val f = apk(id)
        return "%.1f MB".format(f.length() / 1_048_576.0)
    }

    /**
     * 下载并安装内核。[onProgress] 回调 0..1。
     * @return 安装成功后的内核实例
     */
    suspend fun install(
        id: CoreId,
        url: String = id.defaultUrl,
        onProgress: (Float) -> Unit = {},
    ): ExternalPlayerCore {
        require(id != CoreId.MEDIA3) { "内置内核无需安装" }
        require(url.startsWith("http://") || url.startsWith("https://")) { "下载地址必须为 http(s)" }

        val target = dir(id)
        target.mkdirs()
        val tmp = File(target, "download.tmp")

        val client = OkHttpClient.Builder().followRedirects(true).build()
        val resp = client.newCall(Request.Builder().url(url).build()).execute()
        resp.use {
            if (!it.isSuccessful) error("下载失败：HTTP ${it.code}")
            val body = it.body ?: error("下载失败：空响应")
            val total = body.contentLength()
            tmp.outputStream().use { out ->
                val buf = ByteArray(64 * 1024)
                var copied = 0L
                while (true) {
                    val n = body.source().read(buf)
                    if (n == -1) break
                    out.write(buf, 0, n)
                    copied += n
                    if (total > 0) onProgress((copied.toFloat() / total).coerceIn(0f, 1f))
                }
                out.flush()
            }
        }
        onProgress(1f)
        return finalizeInstall(id, tmp)
    }

    /**
     * 从本地文件（SAF 内容 URI 已由调用方拷为 File）安装。
     */
    fun installFromFile(id: CoreId, file: File): ExternalPlayerCore {
        require(id != CoreId.MEDIA3)
        val target = dir(id)
        target.mkdirs()
        val tmp = File(target, "install.tmp")
        file.copyTo(tmp, overwrite = true)
        return finalizeInstall(id, tmp)
    }

    private fun finalizeInstall(id: CoreId, tmp: File): ExternalPlayerCore {
        // 1. 结构校验 + 入口类存在。
        validateApk(tmp, id)
        // 2. 解包原生库。
        extractNativeLibs(tmp, id)
        // 3. 原子替换。
        val dst = apk(id)
        dst.delete()
        if (!tmp.renameTo(dst)) tmp.copyTo(dst, overwrite = true).also { tmp.delete() }
        // 4. 实际加载一次，失败即回滚安装。
        return runCatching { create(id) }.getOrElse {
            dst.delete()
            libDir(id).deleteRecursively()
            error("内核加载失败：${it.message}")
        }
    }

    private fun validateApk(file: File, id: CoreId) {
        require(file.length() > 1024) { "文件过小，不是有效内核" }
        ZipFile(file).use { zip ->
            require(zip.getEntry("classes.dex") != null) { "包内缺少 classes.dex" }
            // 入口类在 dex 中，简单以 zip 注释/条目无法直接判断；
            // 用 Entry 名中的 plugin 包做弱校验，强校验延迟到 create()。
            require(
                zip.getEntry("AndroidManifest.xml") != null,
            ) { "包内缺少 AndroidManifest.xml" }
        }
    }

    private fun extractNativeLibs(file: File, id: CoreId) {
        val outDir = libDir(id)
        outDir.mkdirs()
        ZipFile(file).use { zip ->
            val entries = zip.entries()
            var found = false
            while (entries.hasMoreElements()) {
                val e = entries.nextElement()
                if (e.isDirectory) continue
                // 仅解包 arm64-v8a（宿主唯一 ABI）。
                if (!e.name.startsWith("lib/arm64-v8a/") || !e.name.endsWith(".so")) continue
                val name = e.name.substringAfterLast('/')
                zip.getInputStream(e).use { input ->
                    File(outDir, name).outputStream().use { input.copyTo(it) }
                }
                found = true
            }
            // 部分插件可能直接把 so 放在 APK 根（uncompressed 装载），允许没有解包产物。
            @Suppress("UNUSED_EXPRESSION")
            found
        }
    }

    /**
     * 创建内核实例（每次播放独立实例）。失败抛异常。
     */
    fun create(id: CoreId): ExternalPlayerCore {
        if (id == CoreId.MEDIA3) error("Media3 不经由插件管理器")
        val apkFile = apk(id)
        require(apkFile.isFile) { "内核未安装" }
        val parent = ExternalPlayerCore::class.java.classLoader
        val loader = PathClassLoader(
            apkFile.absolutePath,
            libDir(id).takeIf { it.isDirectory }?.absolutePath,
            parent,
        )
        val cls = loader.loadClass(id.entryClass)
        val instance = cls.getDeclaredConstructor().newInstance()
        return instance as? ExternalPlayerCore
            ?: error("入口类未实现 ExternalPlayerCore")
    }

    fun uninstall(id: CoreId) {
        if (id == CoreId.MEDIA3) return
        dir(id).deleteRecursively()
    }
}
