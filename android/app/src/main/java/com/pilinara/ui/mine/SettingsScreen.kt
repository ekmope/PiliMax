package com.pilinara.ui.mine

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
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
import androidx.compose.ui.unit.dp
import com.pilinara.AppContainer
import com.pilinara.player.CdnNode
import com.pilinara.player.Quality
import com.pilinara.vip.VipTrialConfig
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(container: AppContainer, onBack: () -> Unit) {
    val s = container.settings
    val scope = rememberCoroutineScope()

    val vipEnabled by s.vipEnabled.collectAsState(true)
    val vipType by s.vipType.collectAsState(2)
    val danmakuEnabled by s.danmakuEnabled.collectAsState(true)
    val danmakuOpacity by s.danmakuOpacity.collectAsState(0.82f)
    val danmakuScale by s.danmakuScale.collectAsState(1f)
    val defaultSpeed by s.defaultSpeed.collectAsState(1f)
    val audioOnly by s.audioOnly.collectAsState(false)
    val preferQn by s.preferQn.collectAsState(127)
    val cdnNode by s.cdnNode.collectAsState("auto")
    val dynamicColor by s.dynamicColor.collectAsState(true)
    val decodeMode by s.decodeMode.collectAsState("auto")
    val bufferMs by s.bufferMs.collectAsState(30_000)
    val hiResAudio by s.hiResAudio.collectAsState(false)
    val roamingServer by s.roamingServer.collectAsState("")

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            SectionTitle("大会员体验")
            SwitchRow(
                title = "大会员无限试用",
                subtitle = "本地改写会员状态并解除试看限制（仅自己可见）",
                checked = vipEnabled,
            ) { en ->
                scope.launch {
                    s.setVip(VipTrialConfig(en, vipType.toLong(), 3650L))
                }
            }
            LabeledDropdown(
                label = "会员类型",
                current = if (vipType == 2) "年度大会员" else "月度大会员",
                options = listOf("月度大会员" to 1, "年度大会员" to 2),
            ) { type ->
                scope.launch {
                    s.setVip(VipTrialConfig(vipEnabled, type.toLong(), 3650L))
                }
            }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("播放")
            PlayerCoreRow(container)
            LabeledDropdown(
                label = "解码方式",
                current = when (decodeMode) {
                    "hard" -> "强制硬解"
                    "soft" -> "强制软解"
                    else -> "自动（推荐）"
                },
                options = listOf(
                    "自动（推荐）" to "auto",
                    "强制硬解（省电）" to "hard",
                    "强制软解（兼容性）" to "soft",
                ),
            ) { v -> scope.launch { s.setDecodeMode(v) } }
            LabeledDropdown(
                label = "缓冲时长",
                current = "${bufferMs / 1000} 秒",
                options = listOf(
                    "15 秒（省流）" to 15_000,
                    "30 秒（默认）" to 30_000,
                    "50 秒" to 50_000,
                    "90 秒（弱网）" to 90_000,
                ),
            ) { v -> scope.launch { s.setBufferMs(v) } }
            LabeledDropdown(
                label = "默认清晰度",
                current = Quality.PRESETS.firstOrNull { it.qn == preferQn }?.label ?: "1080P 高清",
                options = Quality.PRESETS.map { it.label to it.qn },
            ) { qn -> scope.launch { s.setPreferQn(qn) } }
            LabeledDropdown(
                label = "CDN 节点",
                current = CdnNode.of(cdnNode).label,
                options = CdnNode.entries.map { it.label to it.id },
            ) { id -> scope.launch { s.setCdnNode(id) } }
            SwitchRow(
                title = "高解析度音轨",
                subtitle = "允许 Hi-Res FLAC / 杜比全景声音轨（设备无对应解码器时可能无声）",
                checked = hiResAudio,
            ) { en -> scope.launch { s.setHiResAudio(en) } }
            SliderRow(
                label = "默认倍速",
                value = defaultSpeed,
                range = 0.5f..3f,
                valueText = "${defaultSpeed}x",
            ) { v -> scope.launch { s.setDefaultSpeed((v * 100).toInt() / 100f) } }
            SwitchRow(
                title = "默认只听模式",
                subtitle = "进入播放即关闭视频轨，仅后台音频（省电）",
                checked = audioOnly,
            ) { en -> scope.launch { s.setAudioOnly(en) } }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("解析服务")
            var roamingText by remember(roamingServer) { mutableStateOf(roamingServer) }
            OutlinedTextField(
                value = roamingText,
                onValueChange = { roamingText = it },
                label = { Text("自定义解析服务器（留空关闭）") },
                placeholder = { Text("https://example.com 或 https://example.com/?url=") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                Modifier.fillMaxWidth().padding(top = 4.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = {
                    scope.launch { s.setRoamingServer(roamingText.trim()) }
                }) { Text("保存") }
            }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("弹幕")
            SwitchRow(
                title = "启用弹幕",
                subtitle = "自动加载 seg.so 分段弹幕，重复弹幕由本地核心合并",
                checked = danmakuEnabled,
            ) { en -> scope.launch { s.setDanmakuEnabled(en) } }
            SliderRow(
                label = "弹幕不透明度",
                value = danmakuOpacity,
                range = 0.2f..1f,
                valueText = "${(danmakuOpacity * 100).toInt()}%",
            ) { v -> scope.launch { s.setDanmakuOpacity(v) } }
            SliderRow(
                label = "弹幕字号缩放",
                value = danmakuScale,
                range = 0.6f..2f,
                valueText = "${danmakuScale}x",
            ) { v -> scope.launch { s.setDanmakuScale(v) } }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("外观")
            SwitchRow(
                title = "动态取色（Material You）",
                subtitle = "关闭后使用 PiliNara 品牌粉配色",
                checked = dynamicColor,
            ) { en -> scope.launch { s.setDynamicColor(en) } }

            Text(
                "PiliNara · Rust 核心 + Compose · 为 Android 17 / 第五代骁龙 8 至尊版构建",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(vertical = 20.dp),
            )
        }
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 10.dp, bottom = 6.dp),
    )
}

@Composable
private fun SwitchRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun SliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    valueText: String,
    onChange: (Float) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Row {
            Text(label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Text(valueText, style = MaterialTheme.typography.bodyMedium)
        }
        Slider(value = value, onValueChange = onChange, valueRange = range)
    }
}

@Composable
private fun <T> LabeledDropdown(
    label: String,
    current: String,
    options: List<Pair<String, T>>,
    onSelect: (T) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Box {
            androidx.compose.material3.TextButton(onClick = { expanded = true }) { Text(current) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (name, value) ->
                    DropdownMenuItem(text = { Text(name) }, onClick = {
                        expanded = false
                        onSelect(value)
                    })
                }
            }
        }
    }
}
