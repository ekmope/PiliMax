import 'package:PiliMax/common/widgets/custom_icon.dart';
import 'package:PiliMax/grpc/reply.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/pilimax/utils/user_whitelist.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

List<SettingsModel> get replySettings => [
  getListBanWordModel(
    title: '关键词过滤',
    key: SettingBoxKey.banWordForReply,
    onChanged: (value) {
      ReplyGrpc.replyRegExp = value;
      ReplyGrpc.enableFilter = value.pattern.isNotEmpty;
    },
  ),
  getListUidWithNameModel(
    title: '屏蔽用户',
    getUidsMap: () => Pref.replyBlockedMids,
    setUidsMap: (mids) {
      Pref.replyBlockedMids = mids;
      ReplyGrpc.replyBlockedMids = mids;
    },
    onUpdate: () {},
  ),
  getListUidWithNameModel(
    title: '白名单用户',
    leading: const Icon(Icons.person_add_alt_1_outlined),
    emptySubtitle: '点击添加白名单用户',
    countSubtitleBuilder: (count) => '已加入白名单 $count 个用户',
    getUidsMap: () => Pref.whitelistMids,
    setUidsMap: UserWhitelist.save,
    onUpdate: () {},
  ),
  SwitchModel(
    title: '屏蔽带货评论',
    subtitle: '过滤包含商品推广的评论',
    leading: const Icon(CustomIcons.shopping_bag_not_interested),
    setKey: SettingBoxKey.antiGoodsReply,
    onChanged: (value) => ReplyGrpc.antiGoodsReply = value,
  ),
  const NormalModel(
    title: '屏蔽评论@数量',
    getSubtitle: _replyAtCountSubtitle,
    leading: Icon(Icons.alternate_email),
    onTap: _showReplyAtCountDialog,
  ),
  SwitchModel(
    title: '屏蔽只包含@的评论',
    subtitle: '只过滤正文由@用户组成的评论，不影响包含文字、表情或图片的评论',
    leading: const Icon(Icons.alternate_email),
    setKey: SettingBoxKey.blockAtOnlyReply,
    onChanged: (value) => ReplyGrpc.blockAtOnlyReply = value,
  ),
  SwitchModel(
    title: '保留 UP 主自己的评论',
    subtitle: '保留 UP 主发布的评论，黑名单和带货屏蔽仍会生效',
    leading: const Icon(Icons.person_outline),
    setKey: SettingBoxKey.keepUpOwnerReply,
    onChanged: (value) => ReplyGrpc.keepUpOwnerReply = value,
  ),
  SwitchModel(
    title: '保留置顶评论',
    subtitle: '保留 UP 主置顶的评论，黑名单和带货屏蔽仍会生效',
    leading: const Icon(Icons.vertical_align_top_outlined),
    setKey: SettingBoxKey.keepUpTopReply,
    onChanged: (value) => ReplyGrpc.keepUpTopReply = value,
  ),
  SwitchModel(
    title: '保留 UP 主觉得很赞的评论',
    subtitle: '保留 UP 主点赞的评论，黑名单和带货屏蔽仍会生效',
    leading: const Icon(Icons.thumb_up_outlined),
    setKey: SettingBoxKey.keepUpLikeReply,
    onChanged: (value) => ReplyGrpc.keepUpLikeReply = value,
  ),
  SwitchModel(
    title: '保留 UP 主参与回复的评论',
    subtitle: '保留 UP 主回复过的评论，黑名单和带货屏蔽仍会生效',
    leading: const Icon(Icons.mark_chat_read_outlined),
    setKey: SettingBoxKey.keepUpReplyReply,
    onChanged: (value) => ReplyGrpc.keepUpReplyReply = value,
  ),
  const WidgetModel(
    searchTitle: '屏蔽低等级用户评论',
    searchSubtitle: '按用户等级过滤评论，Lv0 为关闭',
    child: _ReplyLevelSetting(),
  ),
  WidgetModel(
    searchTitle: '评论区过滤说明',
    searchSubtitle: '屏蔽优先级、白名单、关键词、等级与@规则说明',
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        return ListTile(
          dense: true,
          subtitle: Text(
            '* 屏蔽用户后，该用户发布的评论将不会显示。\n'
            '* 评论区屏蔽用户优先于白名单生效。\n'
            '* 白名单用户与动态流/推荐流共享，白名单优先于带货屏蔽、@过滤和其它常规过滤。\n'
            '* 关键词过滤支持正则表达式，多个关键词使用|分隔。\n'
            '* 等级过滤：屏蔽低于所设等级的用户发布的评论，0 为关闭。\n'
            '* @数量过滤按评论中被@用户数触发；只含@过滤只匹配正文内容均为@用户的评论。\n'
            '* 设置立即生效，刷新评论区即可看到过滤结果。',
            style: theme.textTheme.labelSmall!.copyWith(
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
        );
      },
    ),
  ),
];

String _replyAtCountSubtitle() {
  final count = Pref.blockReplyAtCount;
  return count == null ? '已关闭' : '屏蔽包含 $count 个及以上 @用户 的评论';
}

Future<void> _showReplyAtCountDialog(
  BuildContext context,
  VoidCallback setState,
) async {
  final controller = TextEditingController(
    text: Pref.blockReplyAtCount?.toString() ?? '',
  );
  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('屏蔽@的数量'),
      content: TextField(
        autofocus: true,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(suffixText: '个及以上'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(0),
          child: const Text('禁用'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: ColorScheme.of(dialogContext).outline),
          ),
        ),
        TextButton(
          onPressed: () {
            final count = int.tryParse(controller.text);
            if (count == null || count < 1) {
              SmartDialog.showToast('请输入大于0的@数量');
              return;
            }
            Navigator.of(dialogContext).pop(count);
          },
          child: const Text('确认'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return;

  final count = result > 0 ? result : null;
  ReplyGrpc.blockReplyAtCount = count;
  if (count == null) {
    await GStorage.setting.delete(SettingBoxKey.blockReplyAtCount);
  } else {
    await GStorage.setting.put(SettingBoxKey.blockReplyAtCount, count);
  }
  if (context.mounted) setState();
}

class _ReplyLevelSetting extends StatefulWidget {
  const _ReplyLevelSetting();

  @override
  State<_ReplyLevelSetting> createState() => _ReplyLevelSettingState();
}

class _ReplyLevelSettingState extends State<_ReplyLevelSetting> {
  late int _level = Pref.replyMinLevel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('屏蔽低等级用户评论'),
          subtitle: Text(
            _level == 0 ? '已关闭' : '屏蔽 Lv${_level - 1} 及以下的评论',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Lv0'),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 6,
                  divisions: 6,
                  value: _level.toDouble(),
                  label: _level == 0 ? '关闭' : 'Lv$_level',
                  onChanged: (value) {
                    final level = value.round();
                    setState(() => _level = level);
                    Pref.replyMinLevel = level;
                    ReplyGrpc.replyMinLevel = level;
                  },
                ),
              ),
              const Text('Lv6'),
            ],
          ),
        ),
      ],
    );
  }
}
