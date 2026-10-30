import 'package:PiliMax/common/widgets/custom_icon.dart';
import 'package:PiliMax/models/common/dynamic/dynamics_type.dart';
import 'package:PiliMax/pages/main/controller.dart';
import 'package:PiliMax/pages/setting/widgets/select_dialog.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/pilimax/utils/user_whitelist.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get dynamicsSettings => [
  SplitModel(
    normalModel: const NormalModel.split(
      title: '检查未读动态',
      subtitle: '点击设置检查周期(min)',
      leading: Icon(Icons.notifications_none),
    ),
    switchModel: SwitchModel.split(
      setKey: SettingBoxKey.checkDynamic,
      onChanged: (value) => Get.find<MainController>().checkDynamic = value,
      onTap: _showDynDialog,
    ),
  ),
  SwitchModel(
    title: '显示动态警告/争议信息',
    leading: const Icon(Icons.warning_amber_rounded),
    setKey: SettingBoxKey.showDynDispute,
    onChanged: (val) => ItemModulesModel.showDynDispute = val,
  ),
  const SwitchModel(
    title: '发布/转发动态反诈',
    subtitle: '发布/转发动态后检查动态是否可见',
    leading: Icon(CustomIcons.shield_published),
    setKey: SettingBoxKey.enableCreateDynAntifraud,
  ),
  const SwitchModel(
    title: '动态/专栏详情页展示底部操作栏',
    leading: Icon(Icons.more_horiz),
    setKey: SettingBoxKey.showDynActionBar,
  ),
  NormalModel(
    title: '动态展示',
    leading: const Icon(Icons.dynamic_feed_rounded),
    getSubtitle: () => '当前优先展示「${Pref.defaultDynamicType.label}」',
    onTap: _showDefDynDialog,
  ),
  SwitchModel(
    title: '显示动态互动内容',
    subtitle: '开启后则在动态卡片底部显示互动内容（如关注的人点赞、热评等）',
    leading: const Icon(Icons.quickreply_outlined),
    setKey: SettingBoxKey.showDynInteraction,
    onChanged: (val) => ItemModulesModel.showDynInteraction = val,
  ),
  getListBanWordModel(
    title: '动态关键词过滤',
    key: SettingBoxKey.banWordForDyn,
    onChanged: (value) {
      DynamicsDataModel.banWordForDyn = value;
      DynamicsDataModel.enableFilter = value.isEnabled;
    },
  ),
  getListUidModel(
    title: '动态屏蔽用户',
    getUids: () => Pref.dynamicsBlockedMids,
    setUids: (uids) {
      Pref.dynamicsBlockedMids = uids;
      GlobalData().dynamicsBlockedMids = uids;
      DynamicsDataModel.dynamicsBlockedMids = uids;
    },
    onUpdate: () {
      // Changes are immediately reflected
    },
  ),
  getListUidWithNameModel(
    title: '动态白名单用户',
    leading: const Icon(Icons.person_add_alt_1_outlined),
    emptySubtitle: '点击添加白名单用户',
    countSubtitleBuilder: (count) => '已加入白名单 $count 个用户',
    getUidsMap: () => Pref.whitelistMids,
    setUidsMap: UserWhitelist.save,
    onUpdate: () {
      // Changes are immediately reflected
    },
  ),
  SwitchModel(
    title: '屏蔽带货动态',
    subtitle: '过滤包含商品推广的动态',
    leading: const Icon(Icons.shopping_bag_outlined),
    setKey: SettingBoxKey.antiGoodsDyn,
    onChanged: (value) {
      DynamicsDataModel.antiGoodsDyn = value;
    },
  ),
  SwitchModel(
    title: '屏蔽无权查看的动态',
    subtitle: '过滤当前账号无权查看的受限动态,如充电专属(文章,图文等)动态',
    leading: const Icon(Icons.visibility_off_outlined),
    setKey: SettingBoxKey.removeBlockedDyn,
    onChanged: (value) {
      DynamicsDataModel.removeBlockedDyn = value;
    },
  ),
  SwitchModel(
    title: '屏蔽充电专属视频动态',
    subtitle: '过滤充电专属视频动态',
    leading: const Icon(Icons.video_library_outlined),
    setKey: SettingBoxKey.removeOnlyFansVideoDyn,
    onChanged: (value) {
      DynamicsDataModel.removeOnlyFansVideoDyn = value;
    },
  ),
  SwitchModel(
    title: '屏蔽动态视频',
    subtitle: '过滤动态流中的动态视频（信息密度较低，仅非 UP 页生效）',
    leading: const Icon(Icons.smart_display_outlined),
    setKey: SettingBoxKey.removeDynVideoDyn,
    onChanged: (value) {
      DynamicsDataModel.removeDynVideoDyn = value;
    },
  ),
  WidgetModel(
    searchTitle: '动态流过滤说明',
    searchSubtitle: '屏蔽优先级、白名单和关键词规则说明',
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return ListTile(
          dense: true,
          subtitle: Text(
            '* 屏蔽用户后，该用户发布的动态将不会显示。\n'
            '* 动态流屏蔽用户优先于白名单生效。\n'
            '* 白名单用户与推荐流/评论区共享，白名单优先于带货屏蔽和常规过滤。\n'
            '* 关键词过滤支持正则表达式，多个关键词使用|分隔。\n'
            '* 设置立即生效，刷新动态页面即可看到过滤结果。',
            style: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
        );
      },
    ),
  ),
];

void _showDynDialog(BuildContext context) {
  String dynamicPeriod = Pref.dynamicPeriod.toString();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('检查周期'),
      content: TextFormField(
        autofocus: true,
        initialValue: dynamicPeriod,
        keyboardType: TextInputType.number,
        onChanged: (value) => dynamicPeriod = value,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: 'min'),
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(context).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            try {
              final val = int.parse(dynamicPeriod);
              Get.back();
              GStorage.setting.put(SettingBoxKey.dynamicPeriod, val);
              Get.find<MainController>().dynamicPeriod = val * 60 * 1000;
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<void> _showDefDynDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final res = await showDialog<DynamicsTabType>(
    context: context,
    builder: (context) => SelectDialog<DynamicsTabType>(
      title: '动态展示',
      value: Pref.defaultDynamicType,
      values: DynamicsTabType.values.take(4).map((e) => (e, e.label)).toList(),
    ),
  );
  if (res != null) {
    await GStorage.setting.put(SettingBoxKey.defaultDynamicType, res.index);
    setState();
  }
}
