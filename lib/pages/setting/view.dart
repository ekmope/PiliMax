import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliMax/common/widgets/view_safe_area.dart';
import 'package:PiliMax/http/login.dart';
import 'package:PiliMax/models/common/setting_type.dart';
import 'package:PiliMax/pages/about/view.dart';
import 'package:PiliMax/pages/login/controller.dart';
import 'package:PiliMax/pages/setting/common_setting.dart';
import 'package:PiliMax/pages/setting/models/setting_section.dart';
import 'package:PiliMax/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliMax/pages/webdav/view.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  SettingType _type = mainSettingSections.first.type;
  final RxBool _noAccount = Accounts.account.isEmpty.obs;
  late bool _isPortrait;
  late ThemeData theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    theme = Theme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
  }

  @override
  Widget build(BuildContext context) {
    return SimpleScaffold(
      appBar: AppBar(
        title: _isPortrait ? const Text('设置') : Text(_type.title),
      ),
      body: ViewSafeArea(
        child: _isPortrait
            ? _buildList(theme)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildList(theme),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                  Expanded(
                    flex: 6,
                    child: _buildDestination(_type, showAppBar: false),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    _noAccount.close();
    super.dispose();
  }

  void _toPage(SettingType type) {
    if (_isPortrait) {
      Get.to(() => _buildDestination(type));
    } else {
      _type = type;
      setState(() {});
    }
  }

  Widget _buildDestination(SettingType type, {bool showAppBar = true}) {
    final section = maybeSettingSectionFor(type);
    if (section != null) {
      return CommonSetting(section: section, showAppBar: showAppBar);
    }
    return switch (type) {
      .webdavSetting => WebDavSettingPage(showAppBar: showAppBar),
      .about => AboutPage(showAppBar: showAppBar),
      _ => throw StateError('Unsupported setting destination: $type'),
    };
  }

  Color? _getTileColor(ThemeData theme, SettingType type) {
    if (_isPortrait) {
      return null;
    } else {
      return type == _type ? theme.colorScheme.onInverseSurface : null;
    }
  }

  Widget _buildList(ThemeData theme) {
    final padding = MediaQuery.viewPaddingOf(context);
    TextStyle titleStyle = theme.textTheme.titleMedium!;
    TextStyle subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    return ListView(
      padding: EdgeInsets.only(bottom: padding.bottom + 100),
      children: [
        _buildSearchItem(theme),
        ...mainSettingSections.map(
          (section) => ListTile(
            tileColor: _getTileColor(theme, section.type),
            onTap: () => _toPage(section.type),
            leading: Icon(section.icon),
            title: Text(section.type.title, style: titleStyle),
            subtitle: Text(section.subtitle, style: subTitleStyle),
          ),
        ),
        ListTile(
          tileColor: _getTileColor(theme, SettingType.webdavSetting),
          onTap: () => _toPage(SettingType.webdavSetting),
          leading: const Icon(MdiIcons.databaseCogOutline),
          title: Text(SettingType.webdavSetting.title, style: titleStyle),
        ),
        ListTile(
          onTap: () => LoginPageController.switchAccountDialog(context),
          leading: const Icon(Icons.switch_account_outlined),
          title: Text('切换账号', style: titleStyle),
        ),
        Obx(
          () => _noAccount.value
              ? const SizedBox.shrink()
              : ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  onTap: () => _logoutDialog(context),
                  title: Text('退出登录', style: titleStyle),
                ),
        ),
        ListTile(
          tileColor: _getTileColor(theme, SettingType.about),
          onTap: () => _toPage(SettingType.about),
          leading: const Icon(Icons.info_outline),
          title: Text(SettingType.about.title, style: titleStyle),
        ),
      ],
    );
  }

  Future<void> _logoutDialog(BuildContext context) async {
    final result = await showDialog<Set<LoginAccount>>(
      context: context,
      builder: (context) => MultiSelectDialog<LoginAccount>(
        title: '选择要登出的账号uid',
        initValues: const Iterable.empty(),
        values: {
          for (final i in Accounts.account.values) i: i.mid.toString(),
        },
      ),
    );
    if (!context.mounted || result == null || result.isEmpty) return;
    Future<void> removeAccounts(Set<LoginAccount> accounts) async {
      await Accounts.deleteAll(accounts);
      _noAccount.value = Accounts.account.isEmpty;
    }

    Future<({LoginAccount account, bool success})> logoutAccount(
      LoginAccount account,
    ) async {
      try {
        final res = await LoginHttp.logout(account);
        return (account: account, success: res['status'] == true);
      } catch (error, stackTrace) {
        Utils.reportError(error, stackTrace);
        return (account: account, success: false);
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('提示'),
          content: Text(
            "确认要退出以下账号登录吗\n\n${result.map((i) => i.mid.toString()).join('\n')}",
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '点错了',
                style: TextStyle(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                await removeAccounts(result);
              },
              child: Text(
                '仅登出',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () async {
                SmartDialog.showLoading();
                try {
                  final responses = await Future.wait(
                    result.map(logoutAccount),
                  );
                  final successfulAccounts = {
                    for (final response in responses)
                      if (response.success) response.account,
                  };
                  if (successfulAccounts.isNotEmpty) {
                    await removeAccounts(successfulAccounts);
                  }
                  final failedMids = responses
                      .where((response) => !response.success)
                      .map((response) => response.account.mid)
                      .join('、');
                  SmartDialog.dismiss();
                  if (successfulAccounts.length == result.length) {
                    Get.back();
                  } else if (successfulAccounts.isEmpty) {
                    SmartDialog.showToast('账号 $failedMids 退出登录失败');
                  } else {
                    Get.back();
                    SmartDialog.showToast('账号 $failedMids 退出登录失败');
                  }
                } catch (error, stackTrace) {
                  Utils.reportError(error, stackTrace);
                  SmartDialog.dismiss();
                  SmartDialog.showToast('退出登录失败：$error');
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchItem(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(
      left: 16,
      right: 16,
      bottom: 8,
    ),
    child: Material(
      color: theme.colorScheme.onInverseSurface,
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      child: InkWell(
        onTap: () => Get.toNamed('/settingsSearch'),
        borderRadius: const BorderRadius.all(Radius.circular(50)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  size: 18,
                  applyTextScaling: true,
                  Icons.search,
                ),
                Text(
                  ' 搜索',
                  style: TextStyle(height: 1),
                  strutStyle: StrutStyle(height: 1, leading: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
