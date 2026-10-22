import 'dart:io' show Platform;

import 'package:PiliMax/common/widgets/custom_icon.dart';
import 'package:PiliMax/common/widgets/stateful_builder.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/api_type.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide StatefulBuilder;

List<SettingsModel> get privacySettings => [
  if (Platform.isAndroid || Platform.isIOS)
    const SwitchModel(
      title: '自动打开剪贴板视频',
      subtitle: '进入应用或返回前台时，读取剪贴板中的哔哩哔哩视频链接',
      leading: Icon(Icons.content_paste_outlined),
      setKey: SettingBoxKey.autoOpenClipboardVideoLink,
    ),
  NormalModel(
    onTap: (context, setState) => Get.toNamed('/blackListPage'),
    title: '黑名单管理',
    subtitle: '已拉黑用户',
    leading: const Icon(Icons.block),
  ),
  const NormalModel(
    title: '账号 buvid 设置',
    subtitle: '分别设置匿名及登录账号使用的 buvid',
    leading: Icon(CustomIcons.identifier_circle),
    onTap: _showBuvidDialog,
  ),
  NormalModel(
    onTap: (context, setState) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('账号模式详情'),
          content: SelectionArea(
            child: SingleChildScrollView(
              child: _getAccountDetail(context),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: const Text('确认'),
            ),
          ],
        ),
      );
    },
    leading: const Icon(Icons.flag_outlined),
    title: '了解账号模式',
    subtitle: '查看各个账号模式作用的API列表',
  ),
];

Widget _getAccountDetail(BuildContext context) {
  final slivers = <Widget>[];
  final theme = TextTheme.of(context);
  for (final i in AccountType.values) {
    final url = ApiType.apiTypeSet[i];
    if (url == null) continue;

    slivers
      ..add(Center(child: Text(i.title, style: theme.titleMedium)))
      ..add(Text(url.join('\n')));
  }
  return Column(
    spacing: 8,
    mainAxisSize: .min,
    crossAxisAlignment: .start,
    children: slivers,
  );
}

void _showBuvidDialog(BuildContext context, VoidCallback setState) {
  final filter = [
    FilteringTextInputFormatter.allow(
      RegExp(r"[a-z\d\-_]+", caseSensitive: false),
    ),
  ];
  final controllers = [
    (
      AnonymousAccount(),
      TextEditingController(text: AnonymousAccount().buvid),
    ),
    ...Accounts.account.values.map(
      (account) => (account, TextEditingController(text: account.buvid)),
    ),
  ];
  showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return StatefulBuilder(
        onDispose: () {
          for (final (_, controller) in controllers) {
            controller.dispose();
          }
          controllers.clear();
        },
        builder: (context, _) => AlertDialog(
          title: const Text('账号 buvid 设置'),
          content: SingleChildScrollView(
            child: Column(
              spacing: 8,
              mainAxisSize: MainAxisSize.min,
              children: controllers
                  .map(
                    (entry) => TextField(
                      controller: entry.$2,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'mid: ${entry.$1.mid}',
                        labelStyle: theme.textTheme.titleMedium,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              entry.$2.text = LoginUtils.generateBuvid(),
                          iconSize: 24,
                          tooltip: '随机',
                          icon: const Icon(Icons.casino_outlined),
                        ),
                      ),
                      inputFormatters: filter,
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '取消',
                style: TextStyle(color: theme.colorScheme.outline),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                for (final (account, controller) in controllers) {
                  final value = controller.text;
                  if (value.isNotEmpty) account.buvid = value;
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    },
  );
}
