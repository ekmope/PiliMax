package com.pilinara.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
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
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
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

private enum class SearchTab(val label: String) {
    BILI("哔哩哔哩"),
    SOURCE("番剧源"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    container: AppContainer,
    onImmersive: (Boolean) -> Unit = {},
) {
    var tab by remember { mutableStateOf(SearchTab.BILI) }
    var keyword by remember { mutableStateOf("") }
    var biliSelected by remember { mutableStateOf<BiliVideo?>(null) }
    var sourceSelected by remember { mutableStateOf<SourceSearchResult?>(null) }

    val vm: SearchViewModel = viewModel(factory = SearchViewModel.factory(container))

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
        VideoDetailScreen(
            container = container,
            video = sel,
            onBack = { biliSelected = null },
            onOpenVideo = { biliSelected = it },
            onImmersive = onImmersive,
        )
        return
    }

    // 只把当前 Tab 的输入喂给 VM（内部 450ms 防抖；切 Tab 不丢另一 Tab 结果）。
    LaunchedEffect(keyword, tab) {
        when (tab) {
            SearchTab.BILI -> vm.biliInput(keyword)
            SearchTab.SOURCE -> vm.sourceInput(keyword)
        }
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
                SearchTab.BILI -> BiliSearchTab(
                    container, vm,
                    onOpen = { biliSelected = it },
                    onFillKeyword = { kw -> keyword = kw },
                )
                SearchTab.SOURCE -> SourceSearchTab(
                    container, vm,
                    onOpen = { sourceSelected = it },
                    onFillKeyword = { kw -> keyword = kw },
                )
            }
        }
    }
}

@Composable
private fun BiliSearchTab(
    container: AppContainer,
    vm: SearchViewModel,
    onOpen: (BiliVideo) -> Unit,
    onFillKeyword: (String) -> Unit,
) {
    val listState = rememberLazyListState()

    // 接近底部自动翻页。
    LaunchedEffect(listState, vm.biliVideos.size, vm.biliHasMore, vm.biliLoading) {
        snapshotAtEnd(listState) { vm.biliLoadMore() }
    }

    when {
        vm.biliQuery.isEmpty() ->
            EmptyHistory(container, "输入关键词搜索哔哩哔哩", onFillKeyword)
        vm.biliLoading && vm.biliVideos.isEmpty() -> LoadingBox()
        vm.biliError != null && vm.biliVideos.isEmpty() -> ErrorBox("搜索失败：${vm.biliError}")
        vm.biliVideos.isEmpty() -> Hint("没有找到「${vm.biliQuery}」相关视频")
        else -> LazyColumn(
            state = listState,
            contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            items(vm.biliVideos, key = { it.bvid }) { v ->
                VideoCard(v = v, onClick = { onOpen(v) })
            }
            if (vm.biliLoading) item {
                Box(Modifier.fillMaxWidth().padding(12.dp), contentAlignment = Alignment.Center) {
                    androidx.compose.material3.CircularProgressIndicator()
                }
            }
            if (!vm.biliHasMore) item {
                Text(
                    "没有更多了",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                )
            }
        }
    }
}

/** 监听滚动，最后一项可见时触发一次 [atEnd]（由调用方状态保证不重复）。 */
private suspend fun snapshotAtEnd(
    listState: androidx.compose.foundation.lazy.LazyListState,
    atEnd: () -> Unit,
) {
    androidx.compose.runtime.snapshotFlow {
        val info = listState.layoutInfo
        val last = info.visibleItemsInfo.lastOrNull()?.index ?: return@snapshotFlow false
        val total = info.totalItemsCount
        total > 0 && last >= total - 3
    }.collect { nearEnd -> if (nearEnd) atEnd() }
}

@Composable
private fun SourceSearchTab(
    container: AppContainer,
    vm: SearchViewModel,
    onOpen: (SourceSearchResult) -> Unit,
    onFillKeyword: (String) -> Unit,
) {
    when {
        vm.sourceQuery.isEmpty() ->
            EmptyHistory(container, "输入番名，在全部已启用源中并发聚合搜索", onFillKeyword)
        vm.sourceLoading && vm.sourceResults.isEmpty() -> LoadingBox()
        vm.sourceError != null && vm.sourceResults.isEmpty() ->
            ErrorBox("聚合搜索失败：${vm.sourceError}")
        vm.sourceResults.isEmpty() ->
            Hint("所有源均未找到「${vm.sourceQuery}」（可在「源」页添加订阅）")
        else -> Box {
            LazyColumn(
                contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(vm.sourceResults.size) { i ->
                    val r = vm.sourceResults[i]
                    Surface(
                        shape = RoundedCornerShape(14.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier.fillMaxWidth().clickable { onOpen(r) },
                    ) {
                        Row(
                            Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
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
            if (vm.sourceLoading) {
                Text(
                    "仍在搜索更多源…",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(12.dp),
                )
            }
        }
    }
}

@Composable
private fun Hint(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** 未输入关键词时：顶部显示搜索历史，下方居中提示。 */
@Composable
private fun EmptyHistory(
    container: AppContainer,
    hint: String,
    onFillKeyword: (String) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        SearchHistoryRow(container, onPick = onFillKeyword)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(hint, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** 横向滚动的历史词 Chip：点击回填关键词，长按单条删除。 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
private fun SearchHistoryRow(container: AppContainer, onPick: (String) -> Unit) {
    val history by container.searchHistory.items.collectAsState()
    val scope = rememberCoroutineScope()
    if (history.isEmpty()) return

    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "搜索历史",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = { scope.launch(Dispatchers.IO) { container.searchHistory.clear() } },
            ) {
                Text("清空")
            }
        }
        LazyRow(
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(history, key = { it }) { kw ->
                Surface(
                    shape = RoundedCornerShape(50),
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier.combinedClickable(
                        interactionSource = remember {
                            androidx.compose.foundation.interaction.MutableInteractionSource()
                        },
                        indication = androidx.compose.foundation.LocalIndication.current,
                        onLongClick = {
                            scope.launch(Dispatchers.IO) { container.searchHistory.remove(kw) }
                        },
                        onClick = { onPick(kw) },
                    ),
                ) {
                    Text(
                        kw,
                        style = MaterialTheme.typography.labelLarge,
                        maxLines = 1,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}
