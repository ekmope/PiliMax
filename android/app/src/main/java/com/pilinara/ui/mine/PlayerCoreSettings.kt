package com.pilinara.ui.mine

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.player.external.PlayerCoreManager
import kotlinx.coroutines.launch

/**
 * 播放内核选择行：点击当前内核弹出管理对话框（下载/切换/卸载/自定义下载地址）。
 */
@Composable
fun PlayerCoreRow(container: AppContainer) {
    val s = container.settings
    val coreId by s.playerCore.collectAsState("media3")
    var dialogFor by remember { mutableStateOf<PlayerCoreManager.CoreId?>(null) }

    val current = PlayerCoreManager.CoreId.ofSetting(coreId)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("播放内核", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        TextButton(onClick = { dialogFor = current }) {
            Text(
                current.displayName + when {
                    current == PlayerCoreManager.CoreId.MEDIA3 -> ""
                    container.playerCores.isInstalled(current) -> " · 已安装"
                    else -> " · 未安装"
                },
            )
        }
    }

    dialogFor?.let { id ->
        CoreManageDialog(
            container = container,
            target = id,
            selectedId = current,
            onDismiss = { dialogFor = null },
        )
    }
}

@Composable
private fun CoreManageDialog(
    container: AppContainer,
    target: PlayerCoreManager.CoreId,
    selectedId: PlayerCoreManager.CoreId,
    onDismiss: () -> Unit,
) {
    val manager = container.playerCores
    val scope = rememberCoroutineScope()
    var installed by remember(target) { mutableStateOf(manager.isInstalled(target)) }
    var url by remember(target) { mutableStateOf(target.defaultUrl) }
    var progress by remember(target) { mutableFloatStateOf(-1f) }
    var busy by remember(target) { mutableStateOf(false) }
    var message by remember(target) { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("${target.displayName} 内核") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(
                        selected = selectedId == target,
                        enabled = installed || target == PlayerCoreManager.CoreId.MEDIA3,
                        onClick = {
                            scope.launch {
                                container.settings.setPlayerCore(target.settingId)
                                onDismiss()
                            }
                        },
                    )
                    Text(
                        if (installed) "使用该内核" else "未安装（${manager.installedLabel(target) ?: "—"}）",
                    )
                }

                if (target != PlayerCoreManager.CoreId.MEDIA3) {
                    if (installed) {
                        Text(
                            "已安装：${manager.installedLabel(target) ?: ""}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it },
                        label = { Text("下载地址") },
                        singleLine = true,
                        enabled = !busy,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    if (progress in 0f..1f) {
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    message?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    Text(
                        "内核插件拥有与主程序相同的权限，仅可从信任来源下载。" +
                            if (target == PlayerCoreManager.CoreId.MPV) {
                                "MPV 内核随版本分批发布，若官方资产暂不可用可填入镜像地址。"
                            } else {
                                ""
                            },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
        confirmButton = {
            if (target != PlayerCoreManager.CoreId.MEDIA3) {
                if (installed) {
                    TextButton(onClick = {
                        busy = true
                        manager.uninstall(target)
                        installed = false
                        busy = false
                        if (selectedId == target) {
                            scope.launch {
                                container.settings.setPlayerCore("media3")
                            }
                        }
                        message = "已卸载，已切回 Media3"
                    }) { Text("卸载") }
                } else {
                    TextButton(enabled = !busy, onClick = {
                        busy = true
                        message = null
                        progress = 0f
                        scope.launch {
                            runCatching {
                                manager.install(target, url.trim()) { p -> progress = p }
                            }.onSuccess {
                                installed = true
                                progress = -1f
                                container.settings.setPlayerCore(target.settingId)
                                busy = false
                                onDismiss()
                            }.onFailure {
                                message = it.message ?: "下载/安装失败"
                                progress = -1f
                                busy = false
                            }
                        }
                    }) { Text("下载并切换") }
                }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("关闭") } },
    )
}
