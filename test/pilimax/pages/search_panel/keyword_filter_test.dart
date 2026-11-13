import 'dart:io';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/search/search_type.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/models/search/search_esports.dart';
import 'package:PiliMax/models_new/match/match_info/contest.dart';
import 'package:PiliMax/models_new/match/match_info/season.dart';
import 'package:PiliMax/models_new/match/match_info/team.dart';
import 'package:PiliMax/pages/search_panel/all/controller.dart';
import 'package:PiliMax/pages/search_panel/all/view.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/activity.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/esports.dart';
import 'package:PiliMax/pages/search_panel/all/widgets/user.dart';
import 'package:PiliMax/pages/search_panel/video/controller.dart';
import 'package:PiliMax/pages/search_panel/video/view.dart';
import 'package:PiliMax/pilimax/forks/common/widgets/video_card/video_card_h.dart';
import 'package:PiliMax/pilimax/forks/pages/search_panel/pgc/widgets/item.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/pilimax/pages/setting/widgets/list_editor_dialog.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/recommend_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _SearchController extends SearchAllController {
  _SearchController({super.searchType = SearchType.all})
    : super(keyword: 'filter-test', tag: 'test');

  final responses = <LoadingState<SearchVideoData>>[];
  int requests = 0;

  @override
  Future<LoadingState<SearchVideoData>> customGetData() async {
    requests++;
    return responses.removeAt(0);
  }

  // Rendering the last card normally triggers prefetch. Keep test pagination
  // explicit so each fixture controls when a response is consumed.
  @override
  Future<void> onLoadMore() async {}

  void seed(SearchVideoData data) => responses.add(Success(data));
}

SearchVideoItemModel _video(String title, [int aid = 1, String? tag]) =>
    SearchVideoItemModel.fromJson({
      'aid': aid,
      'title': title,
      'tag': tag,
      'mid': 100,
      'author': '作者',
      'duration': '01:00',
      'pubdate': 1700000000,
    });

SearchVideoData _mixedData() =>
    SearchVideoData(list: [_video('保留视频', 1), _video('排除视频', 2)])
      ..searchActivity = [
        SearchActivity(title: '保留活动', url: 'https://live.bilibili.com/1'),
        SearchActivity(title: '排除活动', url: 'https://live.bilibili.com/2'),
      ]
      ..searchUser = [
        SearchUser(mid: 101, uname: '保留用户', level: 1),
        SearchUser(mid: 102, uname: '排除用户', level: 1),
      ]
      ..searchMedia = [
        SearchPgcItemModel.fromJson({
          'title': '保留番剧',
          'season_type_name': '番剧',
        }),
        SearchPgcItemModel.fromJson({
          'title': '排除番剧',
          'season_type_name': '番剧',
        }),
      ]
      ..searchEsports = SearchEsports(
        configInfo: EsportsConfigInfo(esportTitle: '电竞赛事'),
        contest: [
          MatchContest(
            id: 1,
            title: '保留赛事',
            season: MatchSeason(title: '保留赛事'),
            homeTeam: MatchTeam(title: '主队'),
            awayTeam: MatchTeam(title: '客队'),
            liveRoom: 1,
          ),
        ],
      );

Future<void> _pumpPanel(
  WidgetTester tester,
  _SearchController controller,
) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final isAll = controller.searchType == SearchType.all;
  if (isAll) {
    Get.put<SearchAllController>(controller, tag: 'alltest');
  } else {
    Get.put<SearchVideoController>(controller, tag: 'videotest');
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: isAll
            ? const SearchAllPanel(
                keyword: 'filter-test',
                searchType: SearchType.all,
                tag: 'test',
              )
            : const SearchVideoPanel(
                keyword: 'filter-test',
                searchType: SearchType.video,
                tag: 'test',
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<SearchVideoItemModel> _visibleVideos(WidgetTester tester) => tester
    .widgetList<VideoCardH>(find.byType(VideoCardH))
    .map((card) => card.videoItem as SearchVideoItemModel)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late bool previousTestMode;
  late bool previousApplyFilter;
  late Map<int, String> previousRemarks;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pilimax-search-tag-test-',
    );
    Hive.init(hiveDirectory.path);
    GStorage.setting = await Hive.openBox<dynamic>('setting');
    GStorage.localCache = await Hive.openBox<dynamic>('localCache');
    GStorage.video = await Hive.openBox<dynamic>('video');
  });

  setUp(() {
    previousTestMode = Get.testMode;
    previousRemarks = GlobalData().remarkMids;
    previousApplyFilter = RecommendFilter.applyFilterToSearch;
    GlobalData().remarkMids = {};
    RecommendFilter.applyFilterToSearch = false;
    Get.testMode = true;
  });

  tearDown(() {
    GlobalData().remarkMids = previousRemarks;
    RecommendFilter.applyFilterToSearch = previousApplyFilter;
    Get
      ..reset()
      ..testMode = previousTestMode;
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('视频模型读取单数 tag，允许缺失和空值', () {
    expect(_video('标题', 1, '世界历史,C++').tag, '世界历史,C++');
    expect(_video('标题').tag, isNull);
    expect(_video('标题', 1, '').tag, isEmpty);
    expect(SearchVideoItemModel.fromJson({'title': '标题'}).tag, isNull);
  });

  test('标签按字面子串匹配，忽略大小写，不跨标签或匹配标题', () {
    final controller = _SearchController();
    addTearDown(controller.onClose);
    final items = [
      (title: '普通标题', tags: ['世界历史', 'C++入门', '[VLOG]']),
      (title: '历史 C++ [vlog]', tags: ['生活']),
      (title: '普通标题', tags: ['C语言', '历史知识分享']),
    ];
    List<({String title, List<String> tags})> filtered() =>
        controller.filterKeywords(
          items,
          (item) => item.title,
          getTags: (item) => item.tags,
        );
    controller.includeKeywords.add('#历史');
    expect(filtered(), [items[0], items[2]]);
    controller.includeKeywords.assignAll(['#c++']);
    expect(filtered(), [items[0]]);
    controller.includeKeywords.assignAll(['#[vlog]']);
    expect(filtered(), [items[0]]);
    controller.includeKeywords.assignAll(['#历史,C++']);
    expect(filtered(), isEmpty);
    controller.includeKeywords.assignAll(['#历史.*']);
    expect(filtered(), isEmpty);
  });

  test('标题和标签包含项为 OR，任一排除项命中均隐藏', () {
    final controller = _SearchController();
    addTearDown(controller.onClose);
    final items = [
      (title: '教程 1', tags: <String>[]),
      (title: '应用展示', tags: ['Flutter实战']),
      (title: '教程 2', tags: ['广告推广']),
      (title: '付费课程', tags: ['Flutter']),
      (title: '其他内容', tags: ['生活']),
    ];
    controller.includeKeywords.addAll([r'^教程 \d$', '#flutter']);
    controller.excludeKeywords.addAll(['付费', '#广告']);
    expect(
      controller.filterKeywords(
        items,
        (item) => item.title,
        getTags: (item) => item.tags,
      ),
      [items[0], items[1]],
    );
    expect(items, hasLength(5));
  });

  test('无标签视频不命中标签规则，非视频忽略标签，空标题仍参与标签过滤', () {
    final controller = _SearchController();
    addTearDown(controller.onClose);
    final items = <({String? title, List<String>? tags})>[
      (title: '视频', tags: []),
      (title: null, tags: ['世界历史']),
      (title: null, tags: []),
      (title: '用户', tags: null),
    ];
    List<({String? title, List<String>? tags})> filtered() =>
        controller.filterKeywords(
          items,
          (item) => item.title,
          getTags: (item) => item.tags,
        );
    controller.includeKeywords.add('#历史');
    expect(filtered(), [items[1], items[3]]);
    controller.includeKeywords.add('不匹配');
    expect(filtered(), [items[1]]);
    controller.includeKeywords.clear();
    controller.excludeKeywords.add('#历史');
    expect(filtered(), [items[0], items[2], items[3]]);
  });

  test('转义井号仍匹配标题，不读取标签', () {
    final controller = _SearchController();
    addTearDown(controller.onClose);
    controller.includeKeywords.add(r'\#历史');
    expect(
      controller.filterKeywords(
        ['#历史故事', '历史故事'],
        (title) => title,
        getTags: (_) => throw StateError('标题规则不应读取标签'),
      ),
      ['#历史故事'],
    );
  });

  for (final type in [SearchType.all, SearchType.video]) {
    testWidgets('$type 标签过滤接入实际页面并保留 Hero，清除恢复结果', (tester) async {
      final shown = _video('标签命中', 1, ' 世界历史 , C++入门 ');
      final titleOnly = _video('历史', 2, '生活');
      final missing = _video('无标签', 3);
      final excluded = _video('标签排除', 4, '历史知识分享,广告');
      final data = SearchVideoData(list: [shown, titleOnly, missing, excluded]);
      final controller = _SearchController(searchType: type)..seed(data);
      controller.includeKeywords.add('#历史');
      controller.excludeKeywords.add('#广告');
      await _pumpPanel(tester, controller);
      expect(_visibleVideos(tester), [shown]);
      expect(controller.loadingState.value.data, same(data.list));
      expect(find.text('继续加载'), findsOneWidget);
      final card = tester.widget<VideoCardH>(find.byType(VideoCardH));
      expect(card.heroTag, isNotNull);
      expect(card.key, ValueKey<String>(card.heroTag!));

      controller.includeKeywords.assignAll(['#c++']);
      await tester.pumpAndSettle();
      expect(_visibleVideos(tester), [shown]);
      expect(
        tester.widget<VideoCardH>(find.byType(VideoCardH)).heroTag,
        card.heroTag,
      );

      controller.includeKeywords.assignAll(['#历史 , C++']);
      await tester.pumpAndSettle();
      expect(_visibleVideos(tester), isEmpty);
      expect(find.text('当前页结果已被关键词过滤'), findsOneWidget);

      controller.includeKeywords.clear();
      controller.excludeKeywords.clear();
      await tester.pumpAndSettle();
      expect(_visibleVideos(tester), data.list);
      expect(controller.requests, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('综合搜索标签条件保留非视频分区，普通词仍筛选这些分区', (tester) async {
    final data = _mixedData();
    final controller = _SearchController()..seed(data);
    controller.includeKeywords.add('#历史');
    controller.excludeKeywords.add('#保留');
    await _pumpPanel(tester, controller);
    expect(_visibleVideos(tester), isEmpty);
    expect(find.byType(SearchActivityItem), findsNWidgets(2));
    expect(find.byType(SearchAllUserItem), findsNWidgets(2));
    expect(find.byType(SearchPgcItem), findsNWidgets(2));
    expect(find.byType(SearchEsportsItem), findsOneWidget);

    controller.includeKeywords.add('保留');
    controller.excludeKeywords.add('排除');
    await tester.pumpAndSettle();
    expect(_visibleVideos(tester), [data.list!.first]);
    expect(find.byType(SearchActivityItem), findsOneWidget);
    expect(find.byType(SearchAllUserItem), findsOneWidget);
    expect(find.byType(SearchPgcItem), findsOneWidget);
    expect(find.byType(SearchEsportsItem), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('视频列表混入的直播和课堂忽略标签条件', (tester) async {
    final live = _video('直播', 1)..isLive = true;
    final course = _video('课堂', 2)..isPugv = true;
    final video = _video('普通视频', 3);
    final controller = _SearchController(searchType: SearchType.video)
      ..seed(SearchVideoData(list: [live, course, video]));
    controller.includeKeywords.add('#历史');
    await _pumpPanel(tester, controller);
    expect(_visibleVideos(tester), [live, course]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标签筛选后追加分页仍过滤新结果，清除恢复全部已加载视频', (tester) async {
    final first = _video('首屏视频', 1, '生活');
    final shown = _video('后续视频', 2, '世界历史');
    final hidden = _video('后续无标签', 3);
    final controller = _SearchController()
      ..seed(SearchVideoData(list: [first]));
    controller.includeKeywords.add('#历史');
    await _pumpPanel(tester, controller);
    expect(_visibleVideos(tester), isEmpty);
    controller.seed(SearchVideoData(list: [shown, hidden]));
    await controller.queryData(false);
    await tester.pumpAndSettle();
    expect(_visibleVideos(tester), [shown]);
    expect(controller.page, 3);

    controller.includeKeywords.clear();
    await tester.pumpAndSettle();
    expect(_visibleVideos(tester), [first, shown, hidden]);
    expect(controller.requests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑器拒绝空标签，标签特殊字符按字面接受，标题仍校验正则', (tester) async {
    final controller = _SearchController();
    addTearDown(controller.onClose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                controller.buildKeywordFilterSection(
                  context,
                  Theme.of(context),
                  setState,
                ),
          ),
        ),
      ),
    );
    expect(find.textContaining(r'\#历史'), findsOneWidget);
    await tester.tap(find.text('添加包含词'));
    await tester.pumpAndSettle();
    final editor = tester.widget<ListEditorDialog>(
      find.byType(ListEditorDialog),
    );
    expect(editor.hintText, contains('#'));
    expect(editor.validator!('#'), '请输入 # 后的标签文字');
    expect(editor.validator!('#   '), '请输入 # 后的标签文字');
    expect(editor.validator!('#C++'), isNull);
    expect(editor.validator!('#['), isNull);
    expect(editor.validator!('['), '无效的正则表达式');
    expect(editor.validator!(r'\#历史'), isNull);
  });

  testWidgets('非视频搜索拒绝标签语法并提示转义标题井号', (tester) async {
    final controller = _SearchController(searchType: SearchType.article);
    addTearDown(controller.onClose);
    expect(controller.supportsVideoTagFilter, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) =>
                controller.buildKeywordFilterSection(
                  context,
                  Theme.of(context),
                  setState,
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('添加包含词'));
    await tester.pumpAndSettle();
    final editor = tester.widget<ListEditorDialog>(
      find.byType(ListEditorDialog),
    );
    expect(editor.hintText, isNot(contains('#')));
    expect(editor.validator!('#历史'), contains('仅适用于综合和视频搜索'));
    expect(editor.validator!('#历史'), contains(r'\#'));
    expect(editor.validator!(r'\#历史'), isNull);
  });
}
