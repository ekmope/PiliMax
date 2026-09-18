package com.pilinara.ui.search

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.pilinara.AppContainer
import com.pilinara.api.BiliVideo
import com.pilinara.source.SourceSearchResult
import com.pilinara.ui.common.runSuspendCatching
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 搜索页状态宿主：两个 Tab 的查询全部走 viewModelScope（生命周期长于单次组合），
 * 切 Tab 不丢结果、不再把“scope left composition”类取消呈现为错误；
 * 快速输入时旧查询通过 Job 取消，只有最新一次能写入结果。
 */
class SearchViewModel(private val c: AppContainer) : ViewModel() {

    // ---------------- 哔哩哔哩 ----------------
    val biliVideos = mutableStateListOf<BiliVideo>()
    var biliLoading by mutableStateOf(false)
        private set
    var biliError by mutableStateOf<String?>(null)
        private set
    var biliQuery by mutableStateOf("")
        private set
    var biliHasMore by mutableStateOf(true)
        private set

    private var biliPage = 1
    private var biliSearchJob: Job? = null
    private var biliDebounceJob: Job? = null

    fun biliInput(text: String) {
        biliDebounceJob?.cancel()
        if (text.isBlank()) {
            biliQuery = ""
            biliVideos.clear()
            biliError = null
            return
        }
        biliDebounceJob = viewModelScope.launch {
            delay(450)
            searchBili(text.trim(), reset = true)
        }
    }

    /** 滚到接近底部时调用。 */
    fun biliLoadMore() {
        if (biliLoading || !biliHasMore || biliQuery.isEmpty()) return
        searchBili(biliQuery, reset = false)
    }

    private fun searchBili(query: String, reset: Boolean) {
        biliSearchJob?.cancel()
        biliSearchJob = viewModelScope.launch {
            if (reset) {
                biliQuery = query
                biliPage = 1
                biliVideos.clear()
                biliError = null
                biliHasMore = true
            }
            biliLoading = true
            val page = if (reset) 1 else biliPage + 1
            launch(Dispatchers.IO) { c.searchHistory.add(query) }
            runSuspendCatching {
                withContext(Dispatchers.IO) { c.api.searchVideo(query, page) }
            }.onSuccess { list ->
                if (reset) biliVideos.clear()
                if (list.isEmpty()) {
                    biliHasMore = false
                } else {
                    // 翻页可能返回重复 bvid（接口缓存抖动），去重避免 Lazy key 崩溃。
                    list.forEach { v ->
                        if (biliVideos.none { it.bvid == v.bvid }) biliVideos.add(v)
                    }
                    biliPage = page
                }
            }.onFailure { biliError = it.message }
            biliLoading = false
        }
    }

    // ---------------- 番剧源 ----------------
    val sourceResults = mutableStateListOf<SourceSearchResult>()
    var sourceLoading by mutableStateOf(false)
        private set
    var sourceError by mutableStateOf<String?>(null)
        private set
    var sourceQuery by mutableStateOf("")
        private set

    private var sourceSearchJob: Job? = null
    private var sourceDebounceJob: Job? = null

    fun sourceInput(text: String) {
        sourceDebounceJob?.cancel()
        if (text.isBlank()) {
            sourceQuery = ""
            sourceResults.clear()
            sourceError = null
            return
        }
        sourceDebounceJob = viewModelScope.launch {
            delay(450)
            searchSource(text.trim())
        }
    }

    private fun searchSource(query: String) {
        sourceSearchJob?.cancel()
        sourceSearchJob = viewModelScope.launch {
            sourceQuery = query
            sourceResults.clear()
            sourceError = null
            sourceLoading = true
            launch(Dispatchers.IO) { c.searchHistory.add(query) }
            runSuspendCatching {
                withContext(Dispatchers.IO) {
                    c.sourceRepository.aggregateSearchStreaming(query) { partial ->
                        // 流式回填：每出一个源的结果就立刻上屏。
                        sourceResults.addAll(partial)
                    }
                }
            }.onFailure { sourceError = it.message }
            sourceLoading = false
        }
    }

    companion object {
        fun factory(container: AppContainer) = viewModelFactory {
            initializer { SearchViewModel(container) }
        }
    }
}
