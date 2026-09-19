package com.pilinara.data

import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * 简单的 JSON 文本文件存储：订阅、源实例、过滤规则等结构化数据以「整个文件」为粒度
 * 读写（这些文件都很小，频率低；真正的高频计算在 Rust 核心）。
 */
class JsonFileStore(dir: File) {

    private val root = File(dir, "pilinara").apply { mkdirs() }
    private val mutex = Mutex()

    fun read(name: String): String? {
        val f = File(root, name)
        return if (f.exists()) f.readText() else null
    }

    suspend fun write(name: String, text: String): Unit = mutex.withLock {
        withContext(Dispatchers.IO) {
            val f = File(root, name)
            val tmp = File(root, "$name.tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(f)) {
                f.delete()
                tmp.renameTo(f)
            }
        }
    }

    companion object {
        const val SUBSCRIPTIONS = "subscriptions.json"
        const val SOURCE_INSTANCES = "source_instances.json"
        const val FEED_RULES = "feed_rules.json"
        const val FOLLOWED = "followed.json"
    }
}
