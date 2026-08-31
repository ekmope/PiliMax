import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/models/common/setting_type.dart';
import 'package:PiliMax/pages/setting/models/extra_settings.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/pages/setting/models/play_settings.dart';
import 'package:PiliMax/pages/setting/models/privacy_settings.dart';
import 'package:PiliMax/pages/setting/models/recommend_settings.dart';
import 'package:PiliMax/pages/setting/models/style_settings.dart';
import 'package:PiliMax/pages/setting/models/video_settings.dart';
import 'package:PiliMax/pilimax/pages/setting/models/dynamics_settings.dart';
import 'package:PiliMax/pilimax/pages/setting/models/reply_settings.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

typedef SettingsFactory = List<SettingsModel> Function();

@immutable
class SettingSection {
  const SettingSection({
    required this.type,
    required this.subtitle,
    required this.icon,
    required this.settingsFactory,
    this.routeName,
    this.showInMain = true,
    this.searchable = true,
    this.dividerBeforeIndex,
    this.keywordFilterIndex,
    this.searchKeywordsByTitle = const {},
  });

  final SettingType type;
  final String subtitle;
  final IconData icon;
  final SettingsFactory settingsFactory;
  final String? routeName;
  final bool showInMain;
  final bool searchable;
  final int? dividerBeforeIndex;
  final int? keywordFilterIndex;
  final Map<String, List<String>> searchKeywordsByTitle;

  List<SettingsModel> createSettings() => settingsFactory();
}

List<SettingsModel> _privacySettings() => privacySettings;
List<SettingsModel> _recommendSettings() => recommendSettings;
List<SettingsModel> _dynamicsSettings() => dynamicsSettings;
List<SettingsModel> _videoSettings() => videoSettings;
List<SettingsModel> _playSettings() => playSettings;
List<SettingsModel> _styleSettings() => styleSettings;
List<SettingsModel> _extraSettings() => extraSettings;
List<SettingsModel> _replySettings() => replySettings;

final List<SettingSection> settingSections = List.unmodifiable([
  const SettingSection(
    type: SettingType.privacySetting,
    subtitle: '黑名单',
    icon: Icons.privacy_tip_outlined,
    routeName: '/privacySetting',
    settingsFactory: _privacySettings,
  ),
  const SettingSection(
    type: SettingType.recommendSetting,
    subtitle: '推荐来源（web/app）、刷新保留内容、过滤器',
    icon: Icons.explore_outlined,
    routeName: '/recommendSetting',
    settingsFactory: _recommendSettings,
    dividerBeforeIndex: 4,
  ),
  const SettingSection(
    type: SettingType.dynamicsSetting,
    subtitle: '关键词过滤、屏蔽用户、带货动态屏蔽',
    icon: Icons.auto_awesome_motion_outlined,
    routeName: '/dynamicsSetting',
    settingsFactory: _dynamicsSettings,
    keywordFilterIndex: 0,
  ),
  const SettingSection(
    type: SettingType.videoSetting,
    subtitle: '画质、音质、解码、缓冲、音频输出等',
    icon: Icons.video_settings_outlined,
    routeName: '/videoSetting',
    settingsFactory: _videoSettings,
  ),
  const SettingSection(
    type: SettingType.playSetting,
    subtitle: '双击/长按、全屏、后台播放、弹幕、字幕、底部进度条等',
    icon: Icons.touch_app_outlined,
    routeName: '/playSetting',
    settingsFactory: _playSettings,
  ),
  const SettingSection(
    type: SettingType.styleSetting,
    subtitle: '横屏适配（平板）、侧栏、列宽、首页、动态红点、主题、字号、图片、帧率等',
    icon: Icons.style_outlined,
    routeName: '/styleSetting',
    settingsFactory: _styleSettings,
  ),
  const SettingSection(
    type: SettingType.extraSetting,
    subtitle: '震动、搜索、收藏、ai、评论、代理、更新检查等',
    icon: Icons.extension_outlined,
    routeName: '/extraSetting',
    settingsFactory: _extraSettings,
    searchKeywordsByTitle: {
      'AI 视频总结': [
        '启用 AI 视频助手',
        'API 配置',
        '接口地址',
        'API Key',
        '模型选择',
        '模型名称',
        '提示词模板',
        '模板名称',
        '提示词内容',
      ],
      '合并弹幕': [
        '启用合并弹幕',
        '时间阈值',
        '合并不同类型的弹幕',
        '跳过字幕弹幕',
        '跳过高级弹幕',
        '跳过底部弹幕',
        '数量标记位置',
        '数量标记门槛',
        '字体放大门槛',
        '放大速度',
        '编辑距离合并阈值',
        '词频向量合并阈值',
        '代表性百分位',
        '识别谐音弹幕',
      ],
    },
  ),
  const SettingSection(
    type: SettingType.replySetting,
    subtitle: '关键词、用户屏蔽、等级过滤、屏蔽带货评论',
    icon: Icons.comment_outlined,
    routeName: '/replySetting',
    settingsFactory: _replySettings,
    showInMain: false,
    keywordFilterIndex: 0,
  ),
]);

final List<SettingSection> mainSettingSections = List.unmodifiable(
  settingSections.where((section) => section.showInMain),
);

final List<SettingSection> searchableSettingSections = List.unmodifiable(
  settingSections.where((section) => section.searchable),
);

final List<SettingSection> routableSettingSections = List.unmodifiable(
  settingSections.where((section) => section.routeName != null),
);

SettingSection? maybeSettingSectionFor(SettingType type) {
  for (final section in settingSections) {
    if (section.type == type) return section;
  }
  return null;
}

SettingSection settingSectionFor(SettingType type) =>
    maybeSettingSectionFor(type) ??
    (throw ArgumentError.value(type, 'type', 'No setting section registered'));

@immutable
class SettingSearchEntry {
  const SettingSearchEntry({
    required this.model,
    required this.owner,
    required this.title,
    this.subtitle,
    this.keywords = const [],
  });

  final SettingsModel model;
  final String owner;
  final String title;
  final String? subtitle;
  final List<String> keywords;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return model.effectiveTitle.toLowerCase().contains(normalized) ||
        model.effectiveSubtitle?.toLowerCase().contains(normalized) == true ||
        owner.toLowerCase().contains(normalized) ||
        keywords.any((keyword) => keyword.toLowerCase().contains(normalized));
  }
}

List<SettingSearchEntry> buildSettingSearchIndex({
  bool localDiagnosticsEnabled = BuildConfig.localDiagnostics,
  Iterable<SettingSection>? sections,
}) {
  final entries = <SettingSearchEntry>[];
  for (final section in sections ?? searchableSettingSections) {
    for (final model in section.createSettings()) {
      final title = model.title ?? model.effectiveTitle;
      final subtitle = model.effectiveSubtitle;
      entries.add(
        SettingSearchEntry(
          model: model,
          owner: section.type.title,
          title: title,
          subtitle: subtitle,
          keywords: section.searchKeywordsByTitle[title] ?? const [],
        ),
      );
    }
  }

  void addNavigationEntry({
    required String title,
    required String subtitle,
    required IconData icon,
    required String routeName,
    required List<String> keywords,
  }) {
    final model = NormalModel(
      title: title,
      subtitle: subtitle,
      leading: Icon(icon),
      onTap: (_, _) => Get.toNamed(routeName),
    );
    entries.add(
      SettingSearchEntry(
        model: model,
        owner: SettingType.about.title,
        title: title,
        subtitle: subtitle,
        keywords: keywords,
      ),
    );
  }

  addNavigationEntry(
    title: '错误日志',
    subtitle: '查看日志、异常报告历史和脱敏导出',
    icon: Icons.bug_report_outlined,
    routeName: '/logs',
    keywords: const ['异常报告历史', '导出日志', '脱敏日志', '清除日志'],
  );
  if (localDiagnosticsEnabled) {
    addNavigationEntry(
      title: '本地诊断日志',
      subtitle: '查看、复制、导出或清除本地诊断日志',
      icon: Icons.developer_mode_outlined,
      routeName: '/localDiagnostics',
      keywords: const ['复制诊断日志', '导出诊断日志', '清除诊断日志'],
    );
  }
  return entries;
}
