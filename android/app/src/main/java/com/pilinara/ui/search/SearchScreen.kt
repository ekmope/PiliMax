package com.pilinara.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.api.BiliVideo
import com.pilinara.source.SourceSearchResult
import com.pilinara.ui.bili.VideoDetailScreen
import com.pilinara.ui.common.ErrorBox
import com.pilinara.ui.common.LoadingBox
import com.pilinara.ui.common.VideoCard
import com.pilinara.ui.source.SourceDetailScreen
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class SearchTab(val label: String) {
    BILI("哔哩哔哩"),
    SOURCE("番剧源"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(container: AppContainer) {
    var tab by remember { mutableStateOf(SearchTab.BILI) }
    var keyword by remember { mutableStateOf("") }
    var biliSelected by remember { mutableStateOf<BiliVideo?>(null) }
    var sourceSelected by remember { mutableStateOf<SourceSearchResult?>(null) }

    sourceSelected?.let { sel ->
        SourceDetailScreen(
            container = container,
            sourceName = sel.sourceName,
            subjectUrl = sel.subject.url,
            subjectName = sel.subject.name,
            onBack = { sourceSelected = null },
        )
        return
    }
    biliSelected?.let { sel ->
        VideoDetailScreen(container = container, video = sel, onBack = { biliSelected = null })
        return
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(title = { Text("搜索") })
                TextField(
                    value = keyword,
                    onValueChange = { keyword = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
                    placeholder = { Text("搜索视频 / 番剧 / UP 主") },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                    singleLine = true,
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        imeAction = ImeAction.Search,
                    ),
                    keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                        onSearch = { tab = tab /* 触发子组件通过 keyword 变化自动搜索 */ },
                    ),
                )
                PrimaryTabRow(selectedTabIndex = tab.ordinal) {
                    SearchTab.entries.forEach { t ->
                        Tab(selected = tab == t, onClick = { tab = t }, text = { Text(t.label) })
                    }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (tab) {
                SearchTab.BILI -> BiliSearchTab(container, keyword) { biliSelected = it }
                SearchTab.SOURCE -> SourceSearchTab(container, keyword) { sourceSelected = it }
            }
        }
    }
}

@Composable
private fun BiliSearchTab(
    container: AppContainer,
    keyword: String,
    onOpen: (BiliVideo) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val videos = remember { mutableStateListOf<BiliVideo>() }
    var page by remember { mutableIntStateOf(1) }
    var loading by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    // 输入停顿 500ms 后自动发起搜索。
    LaunchedEffect(keyword) {
        if (keyword.isBlank()) return@LaunchedEffect
        kotlinx.coroutines.delay(500)
        if (query != keyword.trim()) {
            query = keyword.trim()
            videos.clear()
            page = 1
            error = null
        }
    }

    LaunchedEffect(query) {
        if (query.isEmpty()) return@LaunchedEffect
        loading = true
        runCatching { withContext(Dispatchers.IO) { container.api.searchVideo(query, page) } }
            .onSuccess { videos.addAll(it) }
            .onFailure { error = it.message }
        loading = false
    }

    when {
        query.isEmpty() -> Hint("输入关键词搜索哔哩哔哩")
        loading && videos.isEmpty() -> LoadingBox()
        error != null && videos.isEmpty() -> ErrorBox("搜索失败：$error")
        videos.isEmpty() -> Hint("没有找到「$query」相关视频")
        else -> LazyColumn(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(videos, key = { it.bvid }) { v ->
                VideoCard(v = v, onClick = { onOpen(v) })
            }
        }
    }
}

@Composable
private fun SourceSearchTab(
    container: AppContainer,
    keyword: String,
    onOpen: (SourceSearchResult) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val results = remember { mutableStateListOf<SourceSearchResult>() }
    var query by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(keyword) {
        if (keyword.isBlank()) return@LaunchedEffect
        kotlinx.coroutines.delay(500)
        query = keyword.trim()
    }

    LaunchedEffect(query) {
        if (query.isEmpty()) return@LaunchedEffect
        results.clear()
        loading = true
        error = null
        runCatching { withContext(Dispatchers.IO) { container.sourceRepository.aggregateSearch(query) } }
            .onSuccess { results.addAll(it) }
            .onFailure { error = it.message }
        loading = false
    }

    when {
        query.isEmpty() -> Hint("输入番名，在全部已启用源中并发聚合搜索")
        loading -> LoadingBox()
        error != null -> ErrorBox("聚合搜索失败：$error")
        results.isEmpty() -> Hint("所有源均未找到「$query」（可在「源」页添加订阅）")
        else -> LazyColumn(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(results.size) { i ->
                val r = results[i]
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier.fillMaxWidth().clickable { onOpen(r) },
                ) {
                    Row(
                        Modifier.padding(14.dp),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(r.subject.name, style = MaterialTheme.typography.titleMedium)
                            Text(
                                r.sourceName,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Hint(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
