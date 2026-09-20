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

/** 底栏可选页面（顺序即底栏显示顺序；至少保留两个）。 */
private val BOTTOM_TAB_OPTIONS = listOf(
    "首页" to "home",
    "动态" to "dynamic",
    "历史" to "history",
    "收藏" to "favorites",
    "搜索" to "search",
    "源" to "sources",
    "我的" to "mine",
)

/** 网络与带宽一键策略：联动清晰度/缓冲/Hi-Res/弱网四项。 */
private data class NetStrategy(
    val id: String,
    val label: String,
    val preferQn: Int,
    val bufferMs: Int,
    val hiRes: Boolean,
    val weakNet: Boolean,
)

private val NET_STRATEGIES = listOf(
    NetStrategy("save", "省流", 32, 15_000, false, false),
    NetStrategy("balanced", "均衡", 80, 30_000, false, false),
    NetStrategy("hq", "高画质", 127, 50_000, true, false),
    NetStrategy("weak", "弱网", 64, 90_000, false, true),
)

/** 空降跳过可选分类（BilibiliSponsorBlock category id）。 */
private val SPONSOR_CATEGORY_OPTIONS = listOf(
    "赞助广告" to "sponsor",
    "付费推广" to "paid_promotion",
    "自我介绍" to "self_promotion",
    "互动提醒" to "interaction",
    "精彩看点" to "poi_highlight",
    "片头" to "intro",
    "片尾" to "outro",
    "下集预告" to "preview",
    "填充片段" to "filler",
    "无关音乐" to "music_offtopic",
)

@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
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
    val filterVertical by s.filterVertical.collectAsState(true)
    val sponsorSkip by s.sponsorSkip.collectAsState(true)
    val sponsorCategories by s.sponsorCategories
        .collectAsState(com.pilinara.data.SettingsStore.DEFAULT_SPONSOR_CATEGORIES)
    val weakNet by s.weakNet.collectAsState(false)
    val autoPlayOnOpen by s.autoPlayOnOpen.collectAsState(true)
    val bottomTabs by s.bottomTabs.collectAsState("home,search,sources,mine")
    val bangumiSync by s.bangumiSync.collectAsState(false)
    val danmakuMergeWindow by s.danmakuMergeWindow.collectAsState(10_000L)
    val danmakuSpeed by s.danmakuSpeed.collectAsState(1f)
    val danmakuArea by s.danmakuArea.collectAsState(1f)
    val danmakuShowFixed by s.danmakuShowFixed.collectAsState(true)
    val danmakuShowColor by s.danmakuShowColor.collectAsState(true)

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
            SwitchRow(
                title = "打开视频时自动播放",
                subtitle = "关闭后进入详情页只显示封面，点一下才开始播放（省流量）",
                checked = autoPlayOnOpen,
            ) { en -> scope.launch { s.setAutoPlayOnOpen(en) } }
            Text(
                "视频详情页打开时会自动隐藏底部导航栏",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
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
            SwitchRow(
                title = "过滤竖屏视频",
                subtitle = "信息流隐藏竖屏短视频（热门/推荐生效）",
                checked = filterVertical,
            ) { en -> scope.launch { s.setFilterVertical(en) } }
            SwitchRow(
                title = "空降跳过",
                subtitle = "自动跳过社区标注的广告/恰饭片段（BilibiliSponsorBlock 数据）",
                checked = sponsorSkip,
            ) { en -> scope.launch { s.setSponsorSkip(en) } }
            if (sponsorSkip) {
                Text(
                    "跳过的片段类型（可多选）",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                androidx.compose.foundation.layout.FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SPONSOR_CATEGORY_OPTIONS.forEach { (label, id) ->
                        val enabled = id in sponsorCategories.split(',')
                        androidx.compose.material3.FilterChip(
                            selected = enabled,
                            onClick = {
                                val set = sponsorCategories.split(',')
                                    .map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet()
                                if (enabled) set.remove(id) else set.add(id)
                                scope.launch { s.setSponsorCategories(set.joinToString(",")) }
                            },
                            label = { Text(label) },
                        )
                    }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("网络与带宽")
            Text(
                "一键策略（参考 BiliVideo-Lab 带宽优化）",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            val currentStrategy = when {
                weakNet -> "weak"
                preferQn <= 32 && bufferMs <= 15_000 && !hiResAudio -> "save"
                preferQn >= 120 && hiResAudio -> "hq"
                preferQn == 80 && bufferMs == 30_000 -> "balanced"
                else -> "custom"
            }
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                NET_STRATEGIES.forEach { st ->
                    androidx.compose.material3.FilterChip(
                        selected = currentStrategy == st.id,
                        onClick = {
                            scope.launch {
                                s.setPreferQn(st.preferQn)
                                s.setBufferMs(st.bufferMs)
                                s.setHiResAudio(st.hiRes)
                                s.setWeakNet(st.weakNet)
                            }
                        },
                        label = { Text(st.label) },
                    )
                }
            }
            Text(
                when (currentStrategy) {
                    "save" -> "当前：省流 —— 480P 上限、15s 缓冲、关闭 Hi-Res"
                    "balanced" -> "当前：均衡 —— 1080P、30s 缓冲"
                    "hq" -> "当前：高画质 —— 8K/HDR 上限、50s 缓冲、Hi-Res 音轨"
                    "weak" -> "当前：弱网 —— 720P 上限、90s 缓冲、关闭 Hi-Res"
                    else -> "当前：自定义（下方可逐项微调）"
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
            LabeledDropdown(
                label = "默认清晰度",
                current = Quality.PRESETS.firstOrNull { it.qn == preferQn }?.label ?: "1080P 高清",
                options = Quality.PRESETS.map { it.label to it.qn },
            ) { qn -> scope.launch { s.setPreferQn(qn) } }
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
                label = "CDN 节点",
                current = CdnNode.of(cdnNode).label,
                options = CdnNode.entries.map { it.label to it.id },
            ) { id -> scope.launch { s.setCdnNode(id) } }
            SwitchRow(
                title = "高解析度音轨",
                subtitle = "允许 Hi-Res FLAC / 杜比全景声音轨（设备无对应解码器时可能无声）",
                checked = hiResAudio,
            ) { en -> scope.launch { s.setHiResAudio(en) } }
            SwitchRow(
                title = "弱网 / 省流模式",
                subtitle = "清晰度上限 720P、缓冲翻倍、关闭 Hi-Res 音轨",
                checked = weakNet,
            ) { en -> scope.launch { s.setWeakNet(en) } }

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
            SliderRow(
                label = "弹幕滚动速度",
                value = danmakuSpeed,
                range = 0.5f..2f,
                valueText = "${danmakuSpeed}x",
            ) { v -> scope.launch { s.setDanmakuSpeed(v) } }
            SliderRow(
                label = "弹幕显示区域",
                value = danmakuArea,
                range = 0.25f..1f,
                valueText = "${(danmakuArea * 100).toInt()}%",
            ) { v -> scope.launch { s.setDanmakuArea(v) } }
            LabeledDropdown(
                label = "重复弹幕合并窗口",
                current = when (danmakuMergeWindow) {
                    0L -> "关闭合并"
                    5_000L -> "5 秒"
                    10_000L -> "10 秒（默认）"
                    30_000L -> "30 秒"
                    else -> "${danmakuMergeWindow / 1000} 秒"
                },
                options = listOf(
                    "关闭合并" to 0L,
                    "5 秒" to 5_000L,
                    "10 秒（默认）" to 10_000L,
                    "30 秒" to 30_000L,
                ),
            ) { v -> scope.launch { s.setDanmakuMergeWindow(v) } }
            SwitchRow(
                title = "显示顶部/底部弹幕",
                subtitle = "关闭后只保留滚动弹幕，画面更干净",
                checked = danmakuShowFixed,
            ) { en -> scope.launch { s.setDanmakuShowFixed(en) } }
            SwitchRow(
                title = "显示彩色弹幕",
                subtitle = "关闭后统一白色，降低视觉干扰",
                checked = danmakuShowColor,
            ) { en -> scope.launch { s.setDanmakuShowColor(en) } }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("界面")
            Text(
                "底部导航栏启用的页面（至少保留两个）",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                BOTTOM_TAB_OPTIONS.forEach { (label, id) ->
                    val enabled = id in bottomTabs.split(',')
                    androidx.compose.material3.FilterChip(
                        selected = enabled,
                        onClick = {
                            val set = bottomTabs.split(',')
                                .map { it.trim() }.filter { it.isNotEmpty() }.toMutableSet()
                            if (enabled) {
                                if (set.size > 2) set.remove(id)
                            } else {
                                set.add(id)
                            }
                            // 保持首页在首位的固定顺序。
                            val ordered = BOTTOM_TAB_OPTIONS.map { it.second }
                                .filter { it in set }
                            scope.launch { s.setBottomTabs(ordered.joinToString(",")) }
                        },
                        label = { Text(label) },
                    )
                }
            }

            HorizontalDivider(Modifier.padding(vertical = 10.dp))
            SectionTitle("追番")
            SwitchRow(
                title = "追番同步到 B 站",
                subtitle = "在订阅源里追番时，若 B 站存在该番则同步加入 B 站追番（需登录 B 站）",
                checked = bangumiSync,
            ) { en -> scope.launch { s.setBangumiSync(en) } }

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
