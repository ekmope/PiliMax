import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/rcmd/today_watch/today_watch_policy.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';

class TodayWatchController extends GetxController {
  TodayWatchController() {
    final modeIndex = GStorage.setting.get(
      SettingBoxKey.todayWatchMode,
      defaultValue: TodayWatchMode.relax.index,
    );
    mode.value =
        TodayWatchMode.values.getOrNull(modeIndex) ?? TodayWatchMode.relax;
  }

  final Rxn<TodayWatchPlan> plan = Rxn();
  final Rx<TodayWatchMode> mode = TodayWatchMode.relax.obs;
  final RxBool loading = false.obs;
  final RxnString error = RxnString();
  final RxBool collapsed = RxBool(
    GStorage.setting.get(
      SettingBoxKey.todayWatchCollapsed,
      defaultValue: false,
    ),
  );

  /// 观看历史采样上限（每页 20 条）
  static const _historyPages = 4;

  /// 一次生成的最短间隔，避免重复刷新
  static const _minRegenerateInterval = Duration(seconds: 3);
  DateTime? _lastGeneratedAt;

  bool get canGenerate =>
      !_autoGenerating &&
      !loading.value &&
      DateTime.now().difference(_lastGeneratedAt ?? DateTime(2000)) >
          _minRegenerateInterval;

  bool _autoGenerating = false;

  Future<void> generate({bool force = false}) async {
    if (loading.value) return;
    if (!force && !canGenerate) return;
    _lastGeneratedAt = DateTime.now();
    loading.value = true;
    error.value = null;

    try {
      final history = await _fetchHistory();
      final candidates = await _fetchCandidates();
      if (history.isEmpty) {
        error.value = '暂无观看历史，登录并观看一些视频后再试';
        plan.value = null;
      } else if (candidates.isEmpty) {
        error.value = '候选视频获取失败，请稍后刷新';
        plan.value = null;
      } else {
        plan.value = buildTodayWatchPlan(
          historyVideos: history,
          candidateVideos: candidates,
          mode: mode.value,
        );
      }
    } catch (e) {
      error.value = e.toString();
      plan.value = null;
    } finally {
      loading.value = false;
    }
  }

  /// 首次进入推荐页时静默生成，失败不打扰用户
  void autoGenerate() {
    if (_autoGenerating || plan.value != null || error.value != null) return;
    if (Pref.userInfoCache == null) return;
    _autoGenerating = true;
    generate(force: true).whenComplete(() => _autoGenerating = false);
  }

  Future<List<HistoryItemModel>> _fetchHistory() async {
    final result = <HistoryItemModel>[];
    int? max;
    int? viewAt;
    for (int i = 0; i < _historyPages; i++) {
      final res = await UserHttp.historyList(
        type: 'archive',
        max: max,
        viewAt: viewAt,
      );
      if (res case Success(:final response)) {
        final list = response.list ?? [];
        if (list.isEmpty) break;
        result.addAll(list);
        final last = list.last;
        max = last.viewAt;
        viewAt = last.viewAt;
        if (result.length >= 80) break;
      } else {
        break;
      }
    }
    return result;
  }

  Future<List<BaseRcmdVideoItemModel>> _fetchCandidates() async {
    final results = await Future.wait([
      VideoHttp.rcmdVideoList(freshIdx: 1, ps: 30),
      VideoHttp.rcmdVideoListApp(freshIdx: 1),
    ]);
    final candidates = <BaseRcmdVideoItemModel>[];
    for (final res in results) {
      if (res case Success(:final response)) {
        candidates.addAll(response);
      }
    }
    return candidates;
  }

  void setMode(TodayWatchMode value) {
    if (value == mode.value) return;
    mode.value = value;
    GStorage.setting.put(SettingBoxKey.todayWatchMode, value.index);
    if (!collapsed.value) {
      generate(force: true);
    }
  }

  void toggleCollapsed() {
    collapsed.value = !collapsed.value;
    GStorage.setting.put(SettingBoxKey.todayWatchCollapsed, collapsed.value);
  }

  void consume(String bvid) {
    final current = plan.value;
    if (current == null) return;
    final queue =
        current.videoQueue.where((v) => v.bvid != bvid).toList();
    if (queue.length == current.videoQueue.length) return;
    plan.value = TodayWatchPlan(
      mode: current.mode,
      upRanks: current.upRanks,
      videoQueue: queue,
      explanationByBvid: current.explanationByBvid,
      scoreByBvid: current.scoreByBvid,
      historySampleCount: current.historySampleCount,
      generatedAt: current.generatedAt,
    );
  }

  Future<void> onVideoTap(BaseRcmdVideoItemModel video) async {
    var bvid = video.bvid ?? '';
    var cid = video.cid;
    if (bvid.isEmpty && video.aid != null) {
      bvid = IdUtils.av2bv(video.aid!);
    }
    if (cid == null) {
      final res = await SearchHttp.ab2cWithDimension(
        aid: video.aid,
        bvid: bvid,
      );
      cid = res?.cid;
    }
    if (cid != null) {
      consume(bvid);
      PageUtils.toVideoPage(
        aid: video.aid,
        bvid: bvid,
        cid: cid,
        cover: video.cover,
        title: video.title,
      );
    }
  }
}
