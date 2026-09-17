package com.pilinara.ui.source

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.source.SourcePresets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SourceScreen(container: AppContainer) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val subscriptions by container.sources.subscriptions.collectAsState()
    // 实例 JSON 变化时重新渲染开关列表。
    val instancesTick by container.sources.instancesJson.collectAsState()
    val instances = remember(instancesTick) { container.sources.instances() }

    var showAdd by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    val presets = remember {
        runCatching {
            val raw = context.assets.open("sources/presets.json").bufferedReader().use { it.readText() }
            com.pilinara.source.SourceManager.parsePresets(raw)
        }.getOrDefault(SourcePresets())
    }

    fun toast(s: String) {
        message = s
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("源中心") },
                actions = {
                    IconButton(onClick = {
                        if (busy) return@IconButton
                        scope.launch {
                            busy = true
                            val r = withContext(Dispatchers.IO) { container.sources.refreshAll() }
                            toast(if (r.isSuccess) "全部订阅已更新" else "部分订阅更新失败：${r.exceptionOrNull()?.message}")
                            busy = false
                        }
                    }) { Icon(Icons.Filled.Refresh, contentDescription = "全部更新") }
                    IconButton(onClick = { showAdd = true }) {
                        Icon(Icons.Filled.Add, contentDescription = "添加订阅")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                Text(
                    "内置订阅预设（Kazumi/Animeko 兼容清单，开箱即用）",
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            items(presets.presets) { preset ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp)) {
                        Text(preset.name, style = MaterialTheme.typography.titleMedium)
                        if (preset.description.isNotEmpty()) {
                            Text(
                                preset.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(top = 4.dp),
                            )
                        }
                        val subscribed = subscriptions.any { it.url == preset.url }
                        Button(
                            enabled = !subscribed && !busy,
                            onClick = {
                                scope.launch {
                                    busy = true
                                    val r = withContext(Dispatchers.IO) {
                                        container.sources.addSubscription(preset.name, preset.url)
                                    }
                                    toast(if (r.isSuccess) "已添加：${preset.name}" else "添加失败：${r.exceptionOrNull()?.message}")
                                    busy = false
                                }
                            },
                            modifier = Modifier.padding(top = 10.dp),
                        ) { Text(if (subscribed) "已添加" else "添加此订阅") }
                    }
                }
            }

            item {
                HorizontalDivider(Modifier.padding(vertical = 6.dp))
                Text("我的订阅", style = MaterialTheme.typography.titleMedium)
            }

            if (subscriptions.isEmpty()) {
                item {
                    Text(
                        "还没有订阅，点击右上角 + 粘贴清单地址，或直接添加上方预设。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            items(subscriptions, key = { it.id }) { sub ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(sub.name, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    text = "${sub.sourceCount} 个源 · " +
                                        if (sub.lastError != null) "更新失败：${sub.lastError}"
                                        else "正常",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (sub.lastError != null)
                                        MaterialTheme.colorScheme.error
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                            }
                            Switch(
                                checked = sub.enabled,
                                onCheckedChange = { en ->
                                    scope.launch {
                                        withContext(Dispatchers.IO) {
                                            container.sources.setSubscriptionEnabled(sub.id, en)
                                        }
                                    }
                                },
                            )
                            IconButton(onClick = {
                                scope.launch {
                                    withContext(Dispatchers.IO) {
                                        container.sources.removeSubscription(sub.id)
                                    }
                                }
                            }) { Icon(Icons.Filled.Delete, contentDescription = "删除订阅") }
                        }
                        OutlinedButton(
                            enabled = !busy,
                            onClick = {
                                scope.launch {
                                    busy = true
                                    val r = withContext(Dispatchers.IO) {
                                        container.sources.refresh(sub.id)
                                    }
                                    toast(if (r.isSuccess) "已更新：${sub.name}" else "更新失败：${r.exceptionOrNull()?.message}")
                                    busy = false
                                }
                            },
                            modifier = Modifier.padding(top = 6.dp),
                        ) { Text("立即更新") }
                    }
                }
            }

            item {
                HorizontalDivider(Modifier.padding(vertical = 6.dp))
                Text("源开关（停用的源不参与聚合搜索）", style = MaterialTheme.typography.titleMedium)
            }
            if (instances.isEmpty()) {
                item {
                    Text(
                        "添加订阅并更新后，这里会列出全部源实例。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            items(instances, key = { it.instanceId }) { inst ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(inst.name, style = MaterialTheme.typography.titleMedium)
                        if (inst.description.isNotEmpty()) {
                            Text(
                                inst.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                            )
                        }
                    }
                    Switch(
                        checked = inst.enabled,
                        onCheckedChange = { en ->
                            scope.launch {
                                withContext(Dispatchers.IO) {
                                    container.sources.setInstanceEnabled(inst.instanceId, en)
                                }
                            }
                        },
                    )
                }
            }
        }
    }

    if (showAdd) {
        AddSubscriptionDialog(
            onDismiss = { showAdd = false },
            onConfirm = { name, url ->
                showAdd = false
                scope.launch {
                    busy = true
                    val r = withContext(Dispatchers.IO) {
                        container.sources.addSubscription(name, url.trim())
                    }
                    toast(if (r.isSuccess) "订阅添加成功" else "添加失败：${r.exceptionOrNull()?.message}")
                    busy = false
                }
            },
        )
    }

    message?.let {
        android.widget.Toast.makeText(LocalContext.current, it, android.widget.Toast.LENGTH_SHORT).show()
        message = null
    }
}

@Composable
private fun AddSubscriptionDialog(
    onDismiss: () -> Unit,
    onConfirm: (name: String, url: String) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加源订阅") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("粘贴 animeko/kazumi 兼容的订阅清单 URL：", style = MaterialTheme.typography.bodyMedium)
                androidx.compose.material3.OutlinedTextField(
                    value = url,
                    onValueChange = { url = it },
                    label = { Text("清单 URL") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                androidx.compose.material3.OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("备注名（可留空）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = url.startsWith("http"),
                onClick = { onConfirm(name, url) },
            ) { Text("添加并更新") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}
