package com.pilinara.source

import com.pilinara.core.NativeCore
import com.pilinara.data.JsonFileStore
import com.pilinara.net.Http
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.builtins.ListSerializer

/**
 * 源订阅与实例管理：订阅列表与实例 JSON（Rust 侧数据结构的序列化结果）均落盘，
 * 清单 diff / 解析全部走 Rust 核心。
 */
class SourceManager(
    private val http: Http,
    private val files: JsonFileStore,
) {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    private val mutex = Mutex()

    private val _subscriptions = MutableStateFlow<List<SourceSubscription>>(emptyList())
    val subscriptions: StateFlow<List<SourceSubscription>> = _subscriptions.asStateFlow()

    /** 全部实例的原始 JSON 文本（数组）。 */
    private val _instancesJson = MutableStateFlow("[]")
    val instancesJson: StateFlow<String> = _instancesJson.asStateFlow()

    fun load() {
        _subscriptions.value = runCatching {
            files.read(JsonFileStore.SUBSCRIPTIONS)?.let {
                json.decodeFromString(ListSerializer(SourceSubscription.serializer()), it)
            } ?: emptyList()
        }.getOrDefault(emptyList())
        _instancesJson.value = files.read(JsonFileStore.SOURCE_INSTANCES) ?: "[]"
    }

    fun instances(): List<SourceInstanceView> {
        val arr = runCatching { json.parseToJsonElement(_instancesJson.value).jsonArray }
            .getOrDefault(JsonArray(emptyList()))
        return arr.mapNotNull { el ->
            val o = el as? JsonObject ?: return@mapNotNull null
            val args = o["arguments"]?.jsonObject ?: JsonObject(emptyMap())
            SourceInstanceView(
                instanceId = o["instanceId"]?.jsonPrimitive?.content.orEmpty(),
                factoryId = o["factoryId"]?.jsonPrimitive?.content.orEmpty(),
                name = args["name"]?.jsonPrimitive?.content
                    ?: o["instanceId"]?.jsonPrimitive?.content.orEmpty(),
                description = args["description"]?.jsonPrimitive?.content.orEmpty(),
                iconUrl = args["iconUrl"]?.jsonPrimitive?.content,
                subscriptionId = o["subscriptionId"]?.jsonPrimitive?.content,
                enabled = (o["isEnabled"] as? kotlinx.serialization.json.JsonPrimitive)
                    ?.booleanOrNull ?: true,
                sortOrder = (o["sortOrder"] as? kotlinx.serialization.json.JsonPrimitive)
                    ?.intOrNull ?: 0,
                raw = o,
            )
        }.sortedBy { it.sortOrder }
    }

    /** 仅保留当前启用的实例，供聚合搜索使用。 */
    fun enabledInstanceJsonList(): List<String> =
        instances().filter { it.enabled }.map { it.raw.toString() }

    /** 添加订阅并立即拉取一次清单。 */
    suspend fun addSubscription(name: String, url: String): Result<Unit> = mutex.withLock {
        val id = subscriptionId(url)
        if (_subscriptions.value.any { it.id == id }) {
            return@withLock Result.failure(IllegalStateException("该订阅已存在"))
        }
        val sub = SourceSubscription(
            id = id,
            name = name.ifEmpty { url.substringAfter("://").substringBefore('/') },
            url = url,
            addedAt = System.currentTimeMillis(),
        )
        val updated = _subscriptions.value + sub
        persistSubs(updated)
        refreshInternal(sub)
    }

    suspend fun removeSubscription(id: String) = mutex.withLock {
        persistSubs(_subscriptions.value.filterNot { it.id == id })
        // 同步移除该订阅带来的实例。
        val arr = json.parseToJsonElement(_instancesJson.value).jsonArray
        val kept = JsonArray(arr.filter { el ->
            (el as? JsonObject)?.get("subscriptionId")?.jsonPrimitive?.content != id
        })
        _instancesJson.value = kept.toString()
        files.write(JsonFileStore.SOURCE_INSTANCES, kept.toString())
    }

    suspend fun setSubscriptionEnabled(id: String, enabled: Boolean) = mutex.withLock {
        persistSubs(_subscriptions.value.map { if (it.id == id) it.copy(enabled = enabled) else it })
        // 订阅停用则其下实例全部停用（Rust 侧只处理启用实例）。
        val arr = json.parseToJsonElement(_instancesJson.value).jsonArray
        val updated = JsonArray(arr.map { el ->
            val o = el as? JsonObject ?: return@map el
            if (o["subscriptionId"]?.jsonPrimitive?.content == id) {
                JsonObject(o + ("isEnabled" to kotlinx.serialization.json.JsonPrimitive(enabled)))
            } else el
        })
        _instancesJson.value = updated.toString()
        files.write(JsonFileStore.SOURCE_INSTANCES, updated.toString())
    }

    suspend fun setInstanceEnabled(instanceId: String, enabled: Boolean) = mutex.withLock {
        val arr = json.parseToJsonElement(_instancesJson.value).jsonArray
        val updated = JsonArray(arr.map { el ->
            val o = el as? JsonObject ?: return@map el
            if (o["instanceId"]?.jsonPrimitive?.content == instanceId) {
                JsonObject(o + ("isEnabled" to kotlinx.serialization.json.JsonPrimitive(enabled)))
            } else el
        })
        _instancesJson.value = updated.toString()
        files.write(JsonFileStore.SOURCE_INSTANCES, updated.toString())
    }

    /** 拉取某个订阅的最新清单（经 Rust 核心解析 + diff）。 */
    suspend fun refresh(subId: String): Result<Unit> = mutex.withLock {
        val sub = _subscriptions.value.firstOrNull { it.id == subId }
            ?: return@withLock Result.failure(IllegalStateException("订阅不存在"))
        refreshInternal(sub)
    }

    suspend fun refreshAll(): Result<Unit> {
        for (sub in _subscriptions.value.filter { it.enabled }) {
            val r = refresh(sub.id)
            if (r.isFailure) return r
        }
        return Result.success(Unit)
    }

    private suspend fun refreshInternal(sub: SourceSubscription): Result<Unit> {
        return try {
            val body = http.getString(
                sub.url,
                headers = mapOf("Accept" to "application/json"),
            )
            // parseManifest 负责校验结构（返回 JSON 字符串）。
            NativeCore.parseManifest(body)
            val next = NativeCore.applyManifest(sub.id, body, _instancesJson.value)
            _instancesJson.value = next
            files.write(JsonFileStore.SOURCE_INSTANCES, next)
            val count = json.parseToJsonElement(next).jsonArray.count { el ->
                (el as? JsonObject)?.get("subscriptionId")?.jsonPrimitive?.content == sub.id
            }
            persistSubs(
                _subscriptions.value.map {
                    if (it.id == sub.id) it.copy(
                        sourceCount = count,
                        lastUpdatedAt = System.currentTimeMillis(),
                        lastError = null,
                    ) else it
                },
            )
            Result.success(Unit)
        } catch (e: Exception) {
            persistSubs(
                _subscriptions.value.map {
                    if (it.id == sub.id) it.copy(lastError = e.message ?: "更新失败") else it
                },
            )
            Result.failure(e)
        }
    }

    private suspend fun persistSubs(list: List<SourceSubscription>) {
        _subscriptions.value = list
        files.write(
            JsonFileStore.SUBSCRIPTIONS,
            json.encodeToString(ListSerializer(SourceSubscription.serializer()), list),
        )
    }

    companion object {
        private val staticJson = Json { ignoreUnknownKeys = true }

        /** 订阅 ID：URL 的稳定哈希，避免文件名字符问题。 */
        fun subscriptionId(url: String): String =
            "sub_" + url.hashCode().toUInt().toString(16)

        /** 解析 assets 中的内置预设清单。 */
        fun parsePresets(raw: String): SourcePresets =
            staticJson.decodeFromString(SourcePresets.serializer(), raw)
    }
}
