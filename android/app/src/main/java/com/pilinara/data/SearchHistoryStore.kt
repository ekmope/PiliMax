package com.pilinara.data

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer

/**
 * 搜索历史（LRU，最多 [MAX_ITEMS] 条）。B 站搜索与番剧源聚合搜索共用一份。
 * 内存态即时可用，落盘走 [JsonFileStore]（文件极小，整块覆写）。
 */
class SearchHistoryStore(private val files: JsonFileStore) {

    private val json = Json { ignoreUnknownKeys = true }

    private val _items = MutableStateFlow<List<String>>(emptyList())
    val items: StateFlow<List<String>> = _items.asStateFlow()

    /** 应用启动时从磁盘恢复（与 SourceManager.load 同批执行）。 */
    fun load() {
        _items.value = runCatching {
            files.read(FILE_NAME)?.let {
                json.decodeFromString(ListSerializer(serializer<String>()), it)
            } ?: emptyList()
        }.getOrDefault(emptyList())
    }

    /** 记录一次搜索：已存在则置顶；超长按 LRU 丢弃。 */
    suspend fun add(keyword: String) {
        val kw = keyword.trim()
        if (kw.isEmpty()) return
        val next = (listOf(kw) + _items.value.filterNot { it == kw }).take(MAX_ITEMS)
        _items.value = next
        persist(next)
    }

    suspend fun remove(keyword: String) {
        val next = _items.value.filterNot { it == keyword }
        _items.value = next
        persist(next)
    }

    suspend fun clear() {
        _items.value = emptyList()
        persist(emptyList())
    }

    private suspend fun persist(list: List<String>) {
        files.write(
            FILE_NAME,
            json.encodeToString(ListSerializer(serializer<String>()), list),
        )
    }

    companion object {
        private const val FILE_NAME = "search_history.json"
        private const val MAX_ITEMS = 20
    }
}
