# PiliMax fork 映射清单

本清单记录「重写代码已从上游路径拆出」的文件。上游路径下的文件已恢复为上游原文，仅把指令里的包名从 `package:PiliPlus/` 替换为 `package:PiliMax/`（fork 必须保留 PiliMax 身份），其余内容与上游逐字节一致；重写实现整体位于 `lib/pilimax/forks/` 下。

## 筛选标准

- 新增代码行数 >= 100；
- 重写占比（新增行 / 当前文件总行）>= 50%；
- 上游近 3 个月改动该文件的提交数 <= 2；
- 排除入口 / 路由等装配文件（`lib/main.dart`、`lib/router/app_pages.dart`）；
- 恢复后的上游文件必须能在本树中通过类型检查（与原地修改的兄弟文件 API 不冲突）。

## 每次合并上游后检查漂移

运行：

```
dart run tool/pilimax/check_fork_drift.dart
```

脚本会把 `upstream/main` 中「上游已经改动了、但你 fork 时快照的原始文件没跟上」的条目列出来，并打印相关上游提交，提醒你把这些改动移植到 `lib/pilimax/forks/` 对应文件。检测到漂移时脚本以非零码退出。

## 映射表

| 上游路径 | Fork 路径 | 新增 | 删除 | 重写占比 | 近3月上游提交 | 近12月上游提交 |
|---|---|---:|---:|---:|---:|---:|
| `lib/common/widgets/floating_navigation_bar.dart` | `lib/pilimax/forks/common/widgets/floating_navigation_bar.dart` | 1452 | 591 | 68.8% | 1 | 3 |
| `lib/services/download/download_manager.dart` | `lib/pilimax/forks/services/download/download_manager.dart` | 666 | 49 | 87.1% | 0 | 6 |
| `lib/tcp/live.dart` | `lib/pilimax/forks/tcp/live.dart` | 525 | 158 | 64.9% | 1 | 8 |
| `lib/utils/storage.dart` | `lib/pilimax/forks/utils/storage.dart` | 437 | 68 | 73.8% | 0 | 15 |
| `lib/utils/accounts/account.dart` | `lib/pilimax/forks/utils/accounts/account.dart` | 385 | 51 | 67.7% | 0 | 7 |
| `lib/common/widgets/video_card/video_card_h.dart` | `lib/pilimax/forks/common/widgets/video_card/video_card_h.dart` | 353 | 175 | 58.8% | 1 | 14 |
| `lib/http/init.dart` | `lib/pilimax/forks/http/init.dart` | 337 | 108 | 50.4% | 0 | 16 |
| `lib/pages/member_video/widgets/video_card_h_member_video.dart` | `lib/pilimax/forks/pages/member_video/widgets/video_card_h_member_video.dart` | 324 | 172 | 55.4% | 1 | 12 |
| `lib/pages/later/widgets/video_card_h_later.dart` | `lib/pilimax/forks/pages/later/widgets/video_card_h_later.dart` | 286 | 165 | 52.3% | 1 | 14 |
| `lib/pages/search_panel/controller.dart` | `lib/pilimax/forks/pages/search_panel/controller.dart` | 212 | 10 | 67.1% | 0 | 7 |
| `lib/utils/wbi_sign.dart` | `lib/pilimax/forks/utils/wbi_sign.dart` | 198 | 59 | 64.5% | 0 | 8 |
| `lib/pages/member_coin_arc/widgets/item.dart` | `lib/pilimax/forks/pages/member_coin_arc/widgets/item.dart` | 183 | 111 | 56.1% | 2 | 10 |
| `lib/pages/member_home/widgets/video_card_v_member_home.dart` | `lib/pilimax/forks/pages/member_home/widgets/video_card_v_member_home.dart` | 183 | 98 | 53.8% | 2 | 9 |
| `lib/pages/later/controller.dart` | `lib/pilimax/forks/pages/later/controller.dart` | 183 | 42 | 50.6% | 0 | 10 |
| `lib/common/widgets/flutter/popup_menu.dart` | `lib/pilimax/forks/common/widgets/flutter/popup_menu.dart` | 180 | 0 | 59.0% | 1 | 2 |
| `lib/utils/accounts.dart` | `lib/pilimax/forks/utils/accounts.dart` | 162 | 16 | 65.1% | 1 | 14 |
| `lib/pages/fav/pgc/widget/item.dart` | `lib/pilimax/forks/pages/fav/pgc/widget/item.dart` | 149 | 86 | 50.5% | 1 | 11 |
| `lib/pages/video/related/controller.dart` | `lib/pilimax/forks/pages/video/related/controller.dart` | 131 | 7 | 86.2% | 0 | 0 |
| `lib/pages/search_panel/pgc/widgets/item.dart` | `lib/pilimax/forks/pages/search_panel/pgc/widgets/item.dart` | 126 | 80 | 52.9% | 0 | 4 |
| `lib/pages/pgc/widgets/pgc_card_v.dart` | `lib/pilimax/forks/pages/pgc/widgets/pgc_card_v.dart` | 121 | 56 | 51.9% | 1 | 5 |
| `lib/pages/search_panel/view.dart` | `lib/pilimax/forks/pages/search_panel/view.dart` | 121 | 10 | 62.7% | 0 | 11 |
| `lib/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart` | `lib/pilimax/forks/pages/pgc_index/widgets/pgc_card_v_pgc_index.dart` | 120 | 57 | 53.3% | 1 | 6 |
| `lib/pages/pgc/widgets/pgc_card_v_timeline.dart` | `lib/pilimax/forks/pages/pgc/widgets/pgc_card_v_timeline.dart` | 119 | 55 | 54.1% | 1 | 5 |
| `lib/services/audio_session.dart` | `lib/pilimax/forks/services/audio_session.dart` | 113 | 26 | 62.1% | 0 | 4 |
| `lib/pages/search_panel/all/widgets/pgc_card_v_search.dart` | `lib/pilimax/forks/pages/search_panel/all/widgets/pgc_card_v_search.dart` | 107 | 50 | 59.4% | 1 | 5 |

## 尝试拆分但因 API 分叉而保持原地修改

以下文件的重写占比同样很高，但恢复后的上游版本依赖了仍在原地修改、API 已分叉的兄弟文件，无法通过类型检查，因此保持原地修改：

- `lib/pages/dynamics/controller.dart`（依赖被改写的 `http/dynamics` 与动态模型 API）
- `lib/pages/setting/models/recommend_settings.dart`（使用 `defaultVal` / `getBanWordModel`，当前设置组件已不提供）
- `lib/services/download/download_service.dart`（调用 `DownloadVideoUrlResult.toJson`，模型已分叉）
- `lib/pages/music/video/view.dart`（依赖的卡片组件参数已分叉）

## 未拆分的高频改写（保留原地修改）

以下文件同样被大量重写，但上游改动频繁（近 3 个月 20+ 次），拆出去会产生持续的移植负担，因此按标准保留在原路径：

- `lib/pages/video/view.dart`、`lib/pages/video/controller.dart`、`lib/pages/video/widgets/header_control.dart`
- `lib/plugin/pl_player/controller.dart`、`lib/plugin/pl_player/view/view.dart`
- `lib/utils/storage_pref.dart`、`lib/utils/page_utils.dart`、`lib/pages/live_room/*`

## 合并冲突分流（2026-08-13）

上游推进到 Flutter 3.47.0 时与本分支产生 8 处冲突，按如下方式分流：

**已拆入 `lib/pilimax/forks/`（原路径恢复上游原文）：**

- `lib/pages/dynamics_mention/view.dart`（已同步移植上游 "opt ui" 的主题色改动）；为让恢复版完整可编译，同步恢复了它依赖的上游组件 `simple_scaffold.dart`、`view_insets_safe_area.dart`、`slotted_layout_helper.dart`（死代码，仅作合并锚点）
- `lib/common/widgets/flutter/vertical_tabs.dart`（本分支版本未定义 `TabBar`，无需移植上游 `hide TabBar` 改动）

**直接采用上游 3.47.0 版本（不 fork）：**

- `lib/scripts/selectable_region.patch`：本分支原有改动是相对旧 Flutter 的简化，上游 3.47 已自行维护该补丁，故放弃本地 fork、直接使用上游版本，`patch.ps1` 改指原路径。

**保持原地修改（不能拆）：**

- `lib/scripts/patch.ps1`：CI 构建入口脚本
- `pubspec.lock`：锁文件，需随 pubspec 原地解析

**保持删除（我方 fork-reduction 方向，无自有内容可拆；上游每次改动时用 `git rm` 解决 modify/delete）：**

- `lib/common/widgets/flutter/text_field/editable_text.dart`
- `lib/common/widgets/flutter/text_field/text_selection.dart`
- `lib/scripts/scrollable_gesture.patch`

以上分流已于 2026-08-13 完成与上游 `c9871e9a8`（Flutter 3.47.0）的实际合并：modify/delete 均以 `git rm` 保留删除；`pubspec.lock` 取上游 3.47 基线，由 GitHub 构建时的隐式 `pub get` 补齐本分支私有依赖。
