import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/pilimax/utils/user_whitelist.dart';
import 'package:material_ui/material_ui.dart';

List<SettingsModel> get dynamicsSettings => [
  getListBanWordModel(
    title: '关键词过滤',
    key: SettingBoxKey.banWordForDyn,
    onChanged: (value) {
      DynamicsDataModel.banWordForDyn = value;
      DynamicsDataModel.enableFilter = value.pattern.isNotEmpty;
    },
  ),
  getListUidModel(
    title: '屏蔽用户',
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
    title: '白名单用户',
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
