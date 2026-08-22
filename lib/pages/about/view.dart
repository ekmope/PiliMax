import 'dart:async';
import 'dart:io';

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/dialog/export_import.dart';
import 'package:PiliMax/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/pages/mine/controller.dart';
import 'package:PiliMax/pilimax/services/local_diagnostics.dart';
import 'package:PiliMax/services/logger.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/utils/android/android_helper.dart';
import 'package:PiliMax/utils/cache_manager.dart';
import 'package:PiliMax/pilimax/utils/cache_policy.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/filtering_text.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/update.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final currentVersion =
      '${BuildConfig.versionName}+${BuildConfig.versionCode}';
  RxString cacheSize = ''.obs;

  late int _pressCount = 0;

  @override
  void initState() {
    super.initState();
    getCacheSize();
  }

  @override
  void dispose() {
    cacheSize.close();
    super.dispose();
  }

  void getCacheSize() {
    CacheManager.loadApplicationCache().then((res) {
      if (mounted) {
        cacheSize.value = CacheManager.formatSize(res);
      }
    });
  }

  Future<void> _setAutoClearCache(bool value) async {
    await GStorage.setting.put(SettingBoxKey.autoClearCache, value);
    if (value) {
      unawaited(
        GStorage.localCache.put(
          LocalCacheKey.lastAutoClearCacheTime,
          DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showAutoClearCacheSettingsDialog() async {
    var selectedPeriod = Pref.autoClearCachePeriod;
    final currentMaxCacheMb = Pref.maxCacheSize / (1024 * 1024);
    final maxCacheController = TextEditingController(
      text: currentMaxCacheMb % 1 == 0
          ? currentMaxCacheMb.toInt().toString()
          : currentMaxCacheMb.toStringAsFixed(2),
    );
    num? pendingMaxCacheMb;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('自动清理缓存设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                // ignore: deprecated_member_use
                value: selectedPeriod,
                decoration: const InputDecoration(labelText: '自动清理周期'),
                items: CacheAutoClearPeriod.allowedDays
                    .map(
                      (days) => DropdownMenuItem<int>(
                        value: days,
                        child: Text('每 $days 天'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedPeriod = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxCacheController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: FilteringText.decimal,
                decoration: const InputDecoration(
                  labelText: '网络图片缓存上限',
                  suffixText: 'MB',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                '取消',
                style: TextStyle(color: ColorScheme.of(context).outline),
              ),
            ),
            TextButton(
              onPressed: () {
                final value = num.tryParse(maxCacheController.text.trim());
                if (value == null || !value.isFinite || value <= 0) {
                  SmartDialog.showToast('请输入大于 0 的有效缓存大小');
                  return;
                }
                pendingMaxCacheMb = value;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    maxCacheController.dispose();

    if (confirmed != true || pendingMaxCacheMb == null) return;
    await GStorage.setting.putAll({
      SettingBoxKey.autoClearCachePeriod: selectedPeriod,
      SettingBoxKey.maxCacheSize: pendingMaxCacheMb! * 1024 * 1024,
    });
    if (mounted) {
      setState(() {});
      SmartDialog.showToast('缓存设置已保存，最大缓存上限将在重启应用后完全生效');
    }
  }

  void _showDialog() => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      constraints: Style.dialogFixedConstraints,
      content: TextField(
        autofocus: true,
        onSubmitted: (value) {
          Get.back();
          if (value.isNotEmpty) {
            PageUtils.handleWebview(value, inApp: true);
          }
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const style = TextStyle(fontSize: 15);
    final outline = theme.colorScheme.outline;
    final subTitleStyle = TextStyle(fontSize: 13, color: outline);
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('关于')) : null,
      resizeToAvoidBottomInset: false,
      body: ListView(
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left : 0,
          right: showAppBar ? padding.right : 0,
          bottom: padding.bottom + 100,
        ),
        children: [
          GestureDetector(
            onTap: () {
              if (++_pressCount == 5) {
                _pressCount = 0;
                _showDialog();
              }
            },
            onSecondaryTap: PlatformUtils.isDesktop ? _showDialog : null,
            child: Image.asset(
              width: 150,
              height: 150,
              excludeFromSemantics: true,
              cacheWidth: 150.cacheSize(context),
              Assets.logo,
            ),
          ),
          ListTile(
            title: Text(
              Constants.appName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium!.copyWith(height: 2),
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '使用Flutter开发的B站第三方客户端',
                  style: TextStyle(color: outline),
                  semanticsLabel: '与你一起，发现不一样的世界',
                ),
                const Icon(
                  Icons.accessibility_new,
                  semanticLabel: "无障碍适配",
                  size: 18,
                ),
              ],
            ),
          ),
          ListTile(
            onTap: () => Update.checkUpdate(false),
            onLongPress: () => Utils.copyText(currentVersion),
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : () => Utils.copyText(currentVersion),
            title: const Text('当前版本'),
            leading: const Icon(Icons.commit_outlined),
            trailing: Text(
              currentVersion,
              style: subTitleStyle,
            ),
          ),
          ListTile(
            title: Text(
              '''
Build Time: ${DateFormatUtils.format(BuildConfig.buildTime, format: DateFormatUtils.longFormatDs)}
Commit Hash: ${BuildConfig.commitHash}''',
              style: const TextStyle(fontSize: 14),
            ),
            leading: const Icon(Icons.info_outline),
            onTap: () => PageUtils.launchURL(
              '${Constants.sourceCodeUrl}/commit/${BuildConfig.commitHash}',
            ),
            onLongPress: () => Utils.copyText(BuildConfig.commitHash),
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : () => Utils.copyText(BuildConfig.commitHash),
          ),
          Divider(
            thickness: 1,
            height: 30,
            color: theme.colorScheme.outlineVariant,
          ),
          ListTile(
            onTap: () => PageUtils.launchURL(Constants.sourceCodeUrl),
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: Text(Constants.sourceCodeUrl, style: subTitleStyle),
          ),
          if (Platform.isAndroid)
            ListTile(
              onTap: PiliAndroidHelper.openLinkVerifySettings,
              leading: const Icon(MdiIcons.linkBoxOutline),
              title: const Text('打开受支持的链接'),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            ),
          ListTile(
            onTap: () =>
                PageUtils.launchURL('${Constants.sourceCodeUrl}/issues'),
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('问题反馈'),
            trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
          ),
          ListTile(
            onTap: () => Get.toNamed('/logs'),
            onLongPress: LoggerUtils.clearLogs,
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : LoggerUtils.clearLogs,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('错误日志'),
            subtitle: Text('长按清除日志', style: subTitleStyle),
            trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
          ),
          if (BuildConfig.localDiagnostics)
            ListTile(
              onTap: () => Get.toNamed('/localDiagnostics'),
              onLongPress: LocalDiagnostics.clear,
              onSecondaryTap: PlatformUtils.isMobile
                  ? null
                  : LocalDiagnostics.clear,
              leading: const Icon(Icons.developer_mode_outlined),
              title: const Text('本地诊断日志'),
              subtitle: Text('长按清除日志', style: subTitleStyle),
              trailing: Icon(Icons.arrow_forward, size: 16, color: outline),
            ),
          ListTile(
            onTap: () {
              if (cacheSize.value.isNotEmpty) {
                showConfirmDialog(
                  context: context,
                  title: const Text('提示'),
                  content: const Text('该操作将清除图片及网络请求缓存数据，确认清除？'),
                  onConfirm: () async {
                    SmartDialog.showLoading(msg: '正在清除...');
                    var resultMessage = '缓存清理失败，请稍后重试';
                    try {
                      final result = await CacheManager.clearLibraryCache();
                      if (result.allSucceeded) {
                        resultMessage = '缓存清理完成';
                      } else if (result.partialFailure) {
                        resultMessage = '缓存已部分清理，${result.failedCount} 项清理失败';
                      } else if (result.allFailed) {
                        resultMessage = '缓存清理失败，请稍后重试';
                      }
                    } catch (_) {
                      resultMessage = '缓存清理失败，请稍后重试';
                    } finally {
                      SmartDialog.dismiss();
                    }
                    SmartDialog.showToast(resultMessage);
                    getCacheSize();
                  },
                );
              }
            },
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: Obx(
              () => Text(
                '图片及网络缓存 ${cacheSize.value}',
                style: subTitleStyle,
              ),
            ),
          ),
          ListTile(
            onTap: () => _setAutoClearCache(!Pref.autoClearCache),
            onLongPress: _showAutoClearCacheSettingsDialog,
            onSecondaryTap: PlatformUtils.isMobile
                ? null
                : _showAutoClearCacheSettingsDialog,
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('自动清理缓存'),
            subtitle: Text(
              '开启后自动清理缓存；长按可更改自动清理周期和最大缓存大小',
              style: subTitleStyle,
            ),
            trailing: Switch(
              value: Pref.autoClearCache,
              onChanged: _setAutoClearCache,
            ),
          ),
          ListTile(
            title: const Text('导入/导出登录信息'),
            leading: const Icon(Icons.import_export_outlined),
            onTap: () => showImportExportDialog<Map>(
              context,
              title: '登录信息',
              localFileName: () => 'account',
              onExport: () =>
                  Utils.jsonEncoder.convert(Accounts.account.toMap()),
              onImport: (json) async {
                late final Map<dynamic, LoginAccount> res;
                try {
                  res = json.map<dynamic, LoginAccount>(
                    (key, value) => MapEntry(
                      key,
                      LoginAccount.fromJson(value),
                    ),
                  );
                } catch (_) {
                  throw const FormatException('账号身份信息无效');
                }
                await Accounts.account.putAll(res);
                await Accounts.refresh();
                if (Accounts.account.isNotEmpty) {
                  await Accounts.markReauthenticated();
                }
                MineController.anonymity.value = !Accounts.heartbeat.isLogin;
                if (Accounts.main.isLogin) {
                  await LoginUtils.onLoginMain();
                }
              },
            ),
          ),
          ListTile(
            title: const Text('导入/导出设置'),
            dense: false,
            leading: const Icon(Icons.import_export_outlined),
            onTap: () => showImportExportDialog<Map<String, dynamic>>(
              context,
              title: '设置',
              localFileName: () => 'setting_${DeviceUtils.platformName}',
              onExport: GStorage.exportAllSettings,
              onImport: GStorage.importAllJsonSettings,
            ),
          ),
          ListTile(
            title: const Text('重置所有设置'),
            leading: const Icon(Icons.settings_backup_restore_outlined),
            onTap: () => showDialog(
              context: context,
              builder: (context) {
                return SimpleDialog(
                  clipBehavior: Clip.hardEdge,
                  title: const Text('是否重置所有设置？'),
                  children: [
                    DialogOption(
                      onPressed: () async {
                        Get.back();
                        await Future.wait([
                          GStorage.setting.clear(),
                          GStorage.video.clear(),
                        ]);
                        SmartDialog.showToast('重置成功');
                      },
                      child: const Text('重置可导出的设置', style: style),
                    ),
                    DialogOption(
                      onPressed: () async {
                        Get.back();
                        await GStorage.clear();
                        SmartDialog.showToast('重置成功');
                      },
                      child: const Text('重置所有数据（含登录信息）', style: style),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
