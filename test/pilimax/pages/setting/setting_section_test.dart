import 'dart:io';

import 'package:PiliMax/models/common/reply/reply_sort_type.dart';
import 'package:PiliMax/models/common/setting_type.dart';
import 'package:PiliMax/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliMax/pages/setting/common_setting.dart';
import 'package:PiliMax/pages/setting/models/model.dart';
import 'package:PiliMax/pages/setting/models/setting_section.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late Box<dynamic> localCacheBox;
  late Box<dynamic> settingBox;
  late Box<dynamic> videoBox;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pilimax-setting-section-test-',
    );
    Hive.init(hiveDirectory.path);
    localCacheBox = await Hive.openBox<dynamic>('localCache');
    settingBox = await Hive.openBox<dynamic>('setting');
    videoBox = await Hive.openBox<dynamic>('video');
    GStorage.localCache = localCacheBox;
    GStorage.setting = settingBox;
    GStorage.video = videoBox;
  });

  setUp(() => settingBox.clear());

  tearDownAll(() async {
    await Future.wait([
      localCacheBox.close(),
      settingBox.close(),
      videoBox.close(),
    ]);
    if (hiveDirectory.existsSync()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('registry keeps seven primary sections and unique legacy routes', () {
    expect(
      mainSettingSections.map((section) => section.type),
      [
        SettingType.privacySetting,
        SettingType.recommendSetting,
        SettingType.dynamicsSetting,
        SettingType.videoSetting,
        SettingType.playSetting,
        SettingType.styleSetting,
        SettingType.extraSetting,
      ],
    );

    final types = settingSections.map((section) => section.type).toList();
    final routes = routableSettingSections
        .map((section) => section.routeName)
        .toList();
    expect(types.toSet(), hasLength(types.length));
    expect(routes, hasLength(8));
    expect(routes.whereType<String>().toSet(), hasLength(routes.length));

    final reply = settingSectionFor(SettingType.replySetting);
    expect(reply.showInMain, isFalse);
    expect(reply.searchable, isTrue);
    expect(reply.routeName, '/replySetting');
  });

  test('section factories create fresh model lists', () {
    for (final section in settingSections) {
      expect(
        identical(section.createSettings(), section.createSettings()),
        isFalse,
        reason: section.type.name,
      );
    }
  });

  test('dynamic and reply filters expose searchable models', () {
    final sections = <SettingSection>[];
    for (final type in [
      SettingType.dynamicsSetting,
      SettingType.replySetting,
    ]) {
      final section = settingSectionFor(type);
      sections.add(section);
      expect(searchableSettingSections, contains(section));
      final settings = section.createSettings();
      final keywordModel = settings[section.keywordFilterIndex!];
      expect(keywordModel, isA<NormalModel>());
      expect(keywordModel.effectiveTitle, '关键词过滤');
    }

    final searchEntries = buildSettingSearchIndex(
      localDiagnosticsEnabled: false,
      sections: sections,
    );
    for (final section in sections) {
      expect(
        searchEntries
            .where((entry) => entry.owner == section.type.title)
            .map((entry) => entry.title),
        contains('关键词过滤'),
      );
    }

    final replySettings = settingSectionFor(
      SettingType.replySetting,
    ).createSettings();
    expect(
      replySettings.whereType<WidgetModel>().map((model) => model.searchTitle),
      contains('屏蔽低等级用户评论'),
    );
  });

  test('search aliases cover nested AI and danmaku settings', () {
    final aliases = settingSectionFor(
      SettingType.extraSetting,
    ).searchKeywordsByTitle;
    expect(aliases['AI 视频总结'], contains('提示词内容'));
    expect(aliases['合并弹幕'], contains('词频向量合并阈值'));

    final section = SettingSection(
      type: SettingType.extraSetting,
      subtitle: '测试',
      icon: Icons.settings,
      settingsFactory: () => const [
        NormalModel(title: 'AI 视频总结', subtitle: '配置入口'),
        NormalModel(title: '合并弹幕', subtitle: '配置入口'),
      ],
      searchKeywordsByTitle: aliases,
    );
    final entries = buildSettingSearchIndex(
      localDiagnosticsEnabled: false,
      sections: [section],
    );
    expect(
      entries.singleWhere((entry) => entry.title == 'AI 视频总结').matches('提示词内容'),
      isTrue,
    );
    expect(
      entries.singleWhere((entry) => entry.title == '合并弹幕').matches('词频向量合并阈值'),
      isTrue,
    );
  });

  test('search reads dynamic subtitles for every query', () {
    var subtitle = '旧值';
    final model = NormalModel(
      title: '动态设置',
      getSubtitle: () => subtitle,
    );
    final entry = SettingSearchEntry(
      model: model,
      owner: '测试',
      title: model.effectiveTitle,
      subtitle: model.effectiveSubtitle,
    );

    expect(entry.matches('旧值'), isTrue);
    subtitle = '新值';
    expect(entry.matches('新值'), isTrue);
    expect(entry.matches('旧值'), isFalse);
  });

  test('local diagnostics search destination follows build capability', () {
    final withoutDiagnostics = buildSettingSearchIndex(
      localDiagnosticsEnabled: false,
      sections: const <SettingSection>[],
    );
    final withDiagnostics = buildSettingSearchIndex(
      localDiagnosticsEnabled: true,
      sections: const <SettingSection>[],
    );

    expect(
      withoutDiagnostics.map((entry) => entry.title),
      ['错误日志'],
    );
    expect(
      withDiagnostics.map((entry) => entry.title),
      ['错误日志', '本地诊断日志'],
    );
  });

  testWidgets('common setting keeps divider metadata and lazy list order', (
    tester,
  ) async {
    final section = SettingSection(
      type: SettingType.privacySetting,
      subtitle: '测试',
      icon: Icons.settings,
      settingsFactory: () => const [
        NormalModel(title: '第一项'),
        NormalModel(title: '第二项'),
      ],
      dividerBeforeIndex: 1,
    );

    await tester.pumpWidget(
      MaterialApp(home: CommonSetting(section: section)),
    );

    expect(find.byType(SimpleScaffold), findsOneWidget);
    final firstY = tester.getCenter(find.text('第一项')).dy;
    final dividerY = tester.getCenter(find.byType(Divider)).dy;
    final secondY = tester.getCenter(find.text('第二项')).dy;
    expect(firstY, lessThan(dividerY));
    expect(dividerY, lessThan(secondY));
  });

  testWidgets('keyword filter auto-open runs once per activation', (
    tester,
  ) async {
    var openCount = 0;
    final section = SettingSection(
      type: SettingType.dynamicsSetting,
      subtitle: '测试',
      icon: Icons.settings,
      settingsFactory: () => [
        NormalModel(
          title: '关键词过滤',
          onTap: (_, _) => openCount++,
        ),
      ],
      keywordFilterIndex: 0,
    );

    Widget app(bool autoOpen) => MaterialApp(
      home: CommonSetting(
        section: section,
        autoOpenKeywordFilter: autoOpen,
      ),
    );

    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(openCount, 1);

    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(openCount, 1);

    await tester.pumpWidget(app(false));
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(openCount, 2);
  });

  test(
    'nested reply sort uses new key, legacy key, then safe default',
    () async {
      expect(Pref.replyReplySortType, ReplySortType.time);

      await settingBox.put(
        SettingBoxKey.reply2SortType,
        ReplySortType.hot.index,
      );
      expect(Pref.replyReplySortType, ReplySortType.hot);

      await settingBox.put(
        SettingBoxKey.replyReplySortType,
        ReplySortType.time.index,
      );
      expect(Pref.replyReplySortType, ReplySortType.time);

      await settingBox.put(SettingBoxKey.replyReplySortType, 99);
      expect(Pref.replyReplySortType, ReplySortType.hot);

      await settingBox.put(SettingBoxKey.reply2SortType, 'invalid');
      expect(Pref.replyReplySortType, ReplySortType.time);
    },
  );

  test('reply level clamps malformed imported values', () async {
    await settingBox.put(SettingBoxKey.replyMinLevel, -1);
    expect(Pref.replyMinLevel, 0);

    await settingBox.put(SettingBoxKey.replyMinLevel, 7);
    expect(Pref.replyMinLevel, 6);

    await settingBox.put(SettingBoxKey.replyMinLevel, 'invalid');
    expect(Pref.replyMinLevel, 0);

    Pref.replyMinLevel = 99;
    expect(Pref.replyMinLevel, 6);
  });

  test('new font weight wins and legacy values migrate safely', () async {
    final normalIndex = FontWeight.values.indexOf(FontWeight.normal);
    final boldIndex = FontWeight.values.indexOf(FontWeight.bold);

    await settingBox.put(SettingBoxKey.appFontWeight, -1);
    await settingBox.put(SettingBoxKey.appFontWeightV2, boldIndex);
    expect(Pref.appFontWeight, FontWeight.bold);

    await settingBox.clear();
    await settingBox.put(SettingBoxKey.appFontWeight, 4);
    expect(Pref.appFontWeight, FontWeight.values[4]);

    await settingBox.clear();
    await settingBox.put(SettingBoxKey.appFontWeightV2, 99);
    await settingBox.put(SettingBoxKey.appFontWeight, normalIndex);
    expect(Pref.appFontWeight, FontWeight.normal);

    await settingBox.clear();
    await settingBox.put(SettingBoxKey.appFontWeightV2, 'invalid');
    await settingBox.put(SettingBoxKey.appFontWeight, 'invalid');
    expect(Pref.appFontWeight, FontWeight.normal);
  });

  test('effective app font prefers imported custom fonts', () async {
    await settingBox.put(SettingBoxKey.appFont, 'SystemFontFamily');
    expect(Pref.effectiveAppFontFamily, 'SystemFontFamily');

    await settingBox.put(
      SettingBoxKey.customFontFamily,
      'ImportedFontFamily',
    );
    expect(Pref.effectiveAppFontFamily, 'ImportedFontFamily');
  });

  test('normal font weight preserves the theme text hierarchy', () async {
    const colorScheme = ColorScheme.light();
    await settingBox.put(
      SettingBoxKey.appFontWeightV2,
      FontWeight.values.indexOf(FontWeight.normal),
    );
    final baseTheme = ThemeUtils.getThemeData(
      colorScheme: colorScheme,
      isDynamic: false,
    );
    expect(
      baseTheme.textTheme.titleSmall?.fontWeight,
      isNot(baseTheme.textTheme.bodyMedium?.fontWeight),
    );

    await settingBox.put(SettingBoxKey.appFont, 'TestFontFamily');
    final fontTheme = ThemeUtils.getThemeData(
      colorScheme: colorScheme,
      isDynamic: false,
    );

    expect(fontTheme.textTheme.bodyMedium?.fontFamily, 'TestFontFamily');
    expect(
      fontTheme.textTheme.titleSmall?.fontWeight,
      baseTheme.textTheme.titleSmall?.fontWeight,
    );
    expect(
      fontTheme.textTheme.labelLarge?.fontWeight,
      baseTheme.textTheme.labelLarge?.fontWeight,
    );
    expect(
      fontTheme.textTheme.bodyMedium?.fontWeight,
      baseTheme.textTheme.bodyMedium?.fontWeight,
    );

    await settingBox.put(
      SettingBoxKey.appFontWeightV2,
      FontWeight.values.indexOf(FontWeight.bold),
    );
    final boldTheme = ThemeUtils.getThemeData(
      colorScheme: colorScheme,
      isDynamic: false,
    );
    expect(boldTheme.textTheme.titleSmall?.fontWeight, FontWeight.bold);
    expect(boldTheme.textTheme.bodyMedium?.fontWeight, FontWeight.bold);
  });
}
