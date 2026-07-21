import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show Directory, File;

import 'package:PiliMax/grpc/dm.dart';
import 'package:PiliMax/http/download.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/sponsor_block.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/models_new/download/bili_download_media_file_info.dart';
import 'package:PiliMax/models_new/download/playback_meta.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliMax/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliMax/pages/danmaku/controller.dart';
import 'package:PiliMax/services/download/download_manager.dart';
import 'package:PiliMax/utils/cache_manager.dart';
import 'package:PiliMax/utils/extension/file_ext.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

// ref https://github.com/10miaomiao/bilimiao2/blob/master/bilimiao-download/src/main/java/cn/a10miaomiao/bilimiao/download/DownloadService.kt

class DownloadService extends GetxService {
  static const _entryFile = 'entry.json';
  static const _indexFile = 'index.json';

  final _lock = Lock();

  final flagNotifier = SetNotifier();
  final completedEntryNotifier = <ValueChanged<BiliDownloadEntryInfo>>{};
  final waitDownloadQueue = RxList<BiliDownloadEntryInfo>();
  final downloadList = <BiliDownloadEntryInfo>[];
  final _activeTasks = <int, _ActiveDownloadTask>{};
  final _connectivity = Connectivity();

  int? _curCid;
  int? get curCid => _curCid;
  final curDownload = Rxn<BiliDownloadEntryInfo>();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult>? _connectivityResults;
  bool _schedulerPaused = false;

  int get _downloadTaskLimit => Pref.downloadTaskCount;

  List<BiliDownloadEntryInfo> get activeDownloads =>
      _activeTasks.values.map((task) => task.entry).toList(growable: false);

  int get activeCount => _activeTasks.length;

  bool isActive(BiliDownloadEntryInfo entry) =>
      _activeTasks.containsKey(entry.cid);

  bool isActiveCid(int cid) => _activeTasks.containsKey(cid);

  BiliDownloadEntryInfo? activeEntry(int cid) => _activeTasks[cid]?.entry;

  bool isEntryDownloading(BiliDownloadEntryInfo entry) =>
      _activeTasks[entry.cid]?.entry.status.isDownloading == true;

  late Future<void> waitForInitialization;

  @override
  void onInit() {
    super.onInit();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    initDownloadList();
  }

  @override
  void onClose() {
    _connectivitySubscription?.cancel();
    super.onClose();
  }

  void initDownloadList() {
    waitForInitialization = _readDownloadList();
  }

  void _syncCurDownload() {
    final entry = _activeTasks.isEmpty ? null : _activeTasks.values.first.entry;
    _curCid = entry?.cid;
    if (curDownload.value?.cid == entry?.cid) {
      curDownload.refresh();
    } else {
      curDownload.value = entry;
    }
  }

  void _refreshDownloadState({bool refreshFlag = false}) {
    _syncCurDownload();
    waitDownloadQueue.refresh();
    if (refreshFlag) {
      flagNotifier.refresh();
    }
  }

  void _updateEntryStatus(BiliDownloadEntryInfo entry, DownloadStatus status) {
    entry.status = status;
    _refreshDownloadState();
  }

  bool _isCurrentTask(_ActiveDownloadTask task) =>
      identical(_activeTasks[task.entry.cid], task);

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _connectivityResults = results;
    if (_isNetworkAllowed(results)) {
      unawaited(_lock.synchronized(_scheduleDownloadsLocked));
    }
  }

  bool _isNetworkAllowed(List<ConnectivityResult> results) {
    if (!Pref.disableMobileDownload) {
      return true;
    }
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return true;
    }
    return !results.contains(ConnectivityResult.mobile) &&
        !results.contains(ConnectivityResult.none);
  }

  Future<bool> _canStartNewDownload({required bool isManual}) async {
    if (!Pref.disableMobileDownload) {
      return true;
    }
    final results =
        _connectivityResults ?? await _connectivity.checkConnectivity();
    _connectivityResults = results;
    final allowed = _isNetworkAllowed(results);
    if (!allowed && isManual) {
      SmartDialog.showToast('已禁止移动流量下载');
    }
    return allowed;
  }

  BiliDownloadEntryInfo? _nextWaitingEntry() {
    for (final entry in waitDownloadQueue) {
      if (!_activeTasks.containsKey(entry.cid) &&
          entry.status == DownloadStatus.wait) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _scheduleDownloadsLocked() async {
    if (_schedulerPaused) {
      _refreshDownloadState();
      return;
    }

    while (_activeTasks.length < _downloadTaskLimit) {
      final entry = _nextWaitingEntry();
      if (entry == null) {
        break;
      }
      final started = await _startEntryLocked(entry, isManual: false);
      if (!started) {
        break;
      }
    }

    _refreshDownloadState();
  }

  Future<bool> _startEntryLocked(
    BiliDownloadEntryInfo entry, {
    required bool isManual,
  }) async {
    if (_activeTasks.containsKey(entry.cid)) {
      return true;
    }
    if (!await _canStartNewDownload(isManual: isManual)) {
      return false;
    }

    entry.status = DownloadStatus.wait;
    final task = _ActiveDownloadTask(entry: entry, isManual: isManual);
    _activeTasks[entry.cid] = task;
    _refreshDownloadState();
    unawaited(_startDownload(task));
    return true;
  }

  Future<void> _releaseTaskLocked(
    _ActiveDownloadTask task, {
    required bool scheduleNext,
  }) async {
    if (!_isCurrentTask(task)) {
      return;
    }
    _activeTasks.remove(task.entry.cid);
    _refreshDownloadState();
    if (scheduleNext) {
      await _scheduleDownloadsLocked();
    }
  }

  Future<void> _failTask(
    _ActiveDownloadTask task,
    DownloadStatus status,
  ) async {
    await _lock.synchronized(() async {
      if (!_isCurrentTask(task)) {
        return;
      }
      task.entry.status = status;
      await _updateBiliDownloadEntryJson(task.entry);
      await _releaseTaskLocked(task, scheduleNext: true);
    });
  }

  bool get _isDownloadTaskLimitReached =>
      _activeTasks.length >= _downloadTaskLimit;

  bool _isFailedStatus(DownloadStatus status) => switch (status) {
    DownloadStatus.failDownload ||
    DownloadStatus.failDownloadAudio ||
    DownloadStatus.failDanmaku ||
    DownloadStatus.failPlayUrl => true,
    _ => false,
  };

  bool _shouldQueueBeforeStart(BiliDownloadEntryInfo entry) =>
      entry.status == DownloadStatus.pause || _isFailedStatus(entry.status);

  void _ensureInWaitQueue(BiliDownloadEntryInfo entry) {
    if (!waitDownloadQueue.contains(entry)) {
      waitDownloadQueue.add(entry);
    }
  }

  Future<void> _markEntryWaitingLocked(BiliDownloadEntryInfo entry) async {
    _ensureInWaitQueue(entry);
    if (entry.status != DownloadStatus.wait) {
      entry.status = DownloadStatus.wait;
      await _updateBiliDownloadEntryJson(entry);
    }
    _refreshDownloadState();
  }

  Future<void> _pauseTaskLocked(
    _ActiveDownloadTask task, {
    required bool isDelete,
    DownloadStatus status = DownloadStatus.pause,
  }) async {
    if (!isDelete) {
      task.interruptedStatus = status;
    }
    _activeTasks.remove(task.entry.cid);
    await task.cancel(isDelete: isDelete);
    if (!isDelete) {
      task.entry.status = status;
      await _updateBiliDownloadEntryJson(task.entry);
    }
    _refreshDownloadState();
  }

  _ActiveDownloadTask? _findYieldableActiveTask() {
    for (final task in _activeTasks.values) {
      if (!task.isManual) {
        return task;
      }
    }
    if (_activeTasks.isEmpty) {
      return null;
    }
    return _activeTasks.values.first;
  }

  Future<bool> _restoreInterruptedTaskStatus(
    _ActiveDownloadTask task,
  ) async {
    final activeTask = _activeTasks[task.entry.cid];
    if (identical(activeTask, task)) {
      return false;
    }
    if (activeTask != null) {
      return true;
    }
    final status = task.interruptedStatus;
    if (status != null && task.entry.status != status) {
      task.entry.status = status;
      await _updateBiliDownloadEntryJson(task.entry);
      _refreshDownloadState();
    }
    return true;
  }

  Future<void> _readDownloadList() async {
    downloadList.clear();
    final downloadDir = Directory(await _getDownloadPath());
    await for (final dir in downloadDir.list()) {
      if (dir is Directory) {
        downloadList.addAll(await _readDownloadDirectory(dir));
      }
    }
    downloadList.sort((a, b) => b.timeUpdateStamp.compareTo(a.timeUpdateStamp));
  }

  @pragma('vm:notify-debugger-on-exception')
  Future<List<BiliDownloadEntryInfo>> _readDownloadDirectory(
    Directory pageDir,
  ) async {
    final result = <BiliDownloadEntryInfo>[];

    if (!pageDir.existsSync()) {
      return result;
    }

    await for (final entryDir in pageDir.list()) {
      if (entryDir is Directory) {
        final entryFile = File(path.join(entryDir.path, _entryFile));
        if (entryFile.existsSync()) {
          try {
            final entryJson = await entryFile.readAsString();
            final entry = BiliDownloadEntryInfo.fromJson(jsonDecode(entryJson))
              ..pageDirPath = pageDir.path
              ..entryDirPath = entryDir.path;
            if (entry.isCompleted) {
              result.add(entry);
            } else {
              waitDownloadQueue.add(entry..status = DownloadStatus.wait);
            }
          } catch (_) {}
        }
      }
    }

    return result;
  }

  void downloadVideo(
    Part page,
    VideoDetailData? videoDetail,
    ugc.EpisodeItem? videoArc,
    VideoQuality videoQuality, {
    String? autoFolderTitle,
    String? autoFolderSourceKey,
  }) {
    final cid = page.cid!;
    if (downloadList.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }
    if (waitDownloadQueue.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }
    final pageData = PageInfo(
      cid: cid,
      page: page.page!,
      from: page.from,
      part: page.part,
      vid: page.vid,
      hasAlias: false,
      tid: 0,
      width: 0,
      height: 0,
      rotate: 0,
      downloadTitle: '视频已缓存完成',
      downloadSubtitle: videoDetail?.title ?? videoArc!.title,
    );
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = BiliDownloadEntryInfo(
      mediaType: 2,
      hasDashAudio: false,
      isCompleted: false,
      totalBytes: 0,
      downloadedBytes: 0,
      title: videoDetail?.title ?? videoArc!.title!,
      typeTag: videoQuality.code.toString(),
      cover: (videoDetail?.pic ?? videoArc!.cover!).http2https,
      preferedVideoQuality: videoQuality.code,
      qualityPithyDescription: videoQuality.desc,
      guessedTotalBytes: 0,
      totalTimeMilli: (page.duration ?? 0) * 1000,
      danmakuCount:
          videoDetail?.stat?.danmaku ?? videoArc?.arc?.stat?.danmaku ?? 0,
      timeUpdateStamp: currentTime,
      timeCreateStamp: currentTime,
      canPlayInAdvance: true,
      interruptTransformTempFile: false,
      avid: videoDetail?.aid ?? videoArc!.aid!,
      spid: 0,
      seasonId: null,
      ep: null,
      source: null,
      bvid: videoDetail?.bvid ?? videoArc!.bvid!,
      ownerId: videoDetail?.owner?.mid ?? videoArc?.arc?.author?.mid,
      ownerName: videoDetail?.owner?.name ?? videoArc?.arc?.author?.name,
      pageData: pageData,
      autoFolderTitle: autoFolderTitle,
      autoFolderSourceKey: autoFolderSourceKey,
    );
    _createDownload(entry);
  }

  void downloadBangumi(
    int index,
    PgcInfoModel pgcItem,
    pgc.EpisodeItem episode,
    VideoQuality quality,
  ) {
    final cid = episode.cid!;
    if (downloadList.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }
    if (waitDownloadQueue.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final source = SourceInfo(avId: episode.aid!, cid: cid);
    final ep = EpInfo(
      avId: source.avId,
      page: index,
      danmaku: source.cid,
      cover: episode.cover!,
      episodeId: episode.id!,
      index: episode.title!,
      indexTitle: episode.longTitle ?? '',
      showTitle: episode.showTitle,
      from: episode.from ?? 'bangumi',
      seasonType: pgcItem.type ?? (episode.from == 'pugv' ? -1 : 0),
      width: 0,
      height: 0,
      rotate: 0,
      link: episode.link ?? '',
      bvid: episode.bvid ?? IdUtils.av2bv(source.avId),
      sortIndex: index,
    );
    final entry = BiliDownloadEntryInfo(
      mediaType: 2,
      hasDashAudio: false,
      isCompleted: false,
      totalBytes: 0,
      downloadedBytes: 0,
      title: pgcItem.seasonTitle ?? pgcItem.title ?? '',
      typeTag: quality.code.toString(),
      cover: episode.cover!,
      preferedVideoQuality: quality.code,
      qualityPithyDescription: quality.desc,
      guessedTotalBytes: 0,
      totalTimeMilli:
          (episode.duration ?? 0) *
          (episode.from == 'pugv' ? 1000 : 1), // pgc millisec,, pugv sec
      danmakuCount: pgcItem.stat?.danmaku ?? 0,
      timeUpdateStamp: currentTime,
      timeCreateStamp: currentTime,
      canPlayInAdvance: true,
      interruptTransformTempFile: false,
      spid: 0,
      seasonId: pgcItem.seasonId!.toString(),
      bvid: episode.bvid ?? IdUtils.av2bv(source.avId),
      avid: source.avId,
      ep: ep,
      source: source,
      ownerId: pgcItem.upInfo?.mid,
      ownerName: pgcItem.upInfo?.uname,
      pageData: null,
    );
    _createDownload(entry);
  }

  Future<void> downloadByIdentifiers({
    required int cid,
    required String bvid,
    required int totalTimeMilli,
    int? aid,
    String? title,
    String? cover,
    int? ownerId,
    String? ownerName,
    VideoQuality? quality,
  }) async {
    if (downloadList.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }
    if (waitDownloadQueue.indexWhere((e) => e.cid == cid) != -1) {
      return;
    }

    final avid = aid ?? IdUtils.bv2av(bvid);
    final preferQ = quality ?? VideoQuality.fromCode(Pref.defaultVideoQa);
    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = BiliDownloadEntryInfo(
      mediaType: 2,
      hasDashAudio: true,
      isCompleted: false,
      totalBytes: 0,
      downloadedBytes: 0,
      title: title ?? bvid,
      typeTag: preferQ.code.toString(),
      cover: cover ?? '',
      preferedVideoQuality: preferQ.code,
      qualityPithyDescription: preferQ.desc,
      guessedTotalBytes: 0,
      totalTimeMilli: totalTimeMilli,
      danmakuCount: 0,
      timeUpdateStamp: currentTime,
      timeCreateStamp: currentTime,
      canPlayInAdvance: true,
      interruptTransformTempFile: false,
      avid: avid,
      spid: 0,
      seasonId: null,
      ep: null,
      source: null,
      bvid: bvid,
      ownerId: ownerId,
      ownerName: ownerName,
      pageData: PageInfo(
        cid: cid,
        page: 1,
        from: null,
        part: null,
        vid: null,
        hasAlias: false,
        tid: 0,
        width: 0,
        height: 0,
        rotate: 0,
        downloadTitle: '视频已缓存完成',
        downloadSubtitle: title ?? bvid,
      ),
    );
    await _createDownload(entry);
  }

  Future<void> _createDownload(BiliDownloadEntryInfo entry) async {
    final entryDir = await _getDownloadEntryDir(entry);
    final entryJsonFile = File(path.join(entryDir.path, _entryFile));
    await entryJsonFile.writeAsString(jsonEncode(entry.toJson()));
    entry
      ..pageDirPath = entryDir.parent.path
      ..entryDirPath = entryDir.path
      ..status = DownloadStatus.wait;
    waitDownloadQueue.add(entry);
    _schedulerPaused = false;
    await _lock.synchronized(_scheduleDownloadsLocked);
  }

  Future<Directory> _getDownloadEntryDir(BiliDownloadEntryInfo entry) async {
    late final String dirName;
    late final String pageDirName;
    if (entry.ep case final ep?) {
      dirName = 's_${entry.seasonId}';
      pageDirName = ep.episodeId.toString();
    } else if (entry.pageData case final page?) {
      dirName = entry.avid.toString();
      pageDirName = 'c_${page.cid}';
    }
    final pageDir = Directory(
      path.join(await _getDownloadPath(), dirName, pageDirName),
    );
    if (!pageDir.existsSync()) {
      await pageDir.create(recursive: true);
    }
    return pageDir;
  }

  static Future<String> _getDownloadPath() async {
    final dir = Directory(downloadPath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> startDownload(BiliDownloadEntryInfo entry) {
    return _lock.synchronized(() async {
      _schedulerPaused = false;
      if (_activeTasks.containsKey(entry.cid)) {
        return;
      }

      if (_isDownloadTaskLimitReached) {
        final task = _findYieldableActiveTask();
        if (task == null) {
          SmartDialog.showToast('当前缓存任务已满');
          return;
        }
        await _pauseTaskLocked(
          task,
          isDelete: false,
          status: DownloadStatus.wait,
        );
      }

      _ensureInWaitQueue(entry);
      final started = await _startEntryLocked(entry, isManual: true);
      if (started) {
        await _scheduleDownloadsLocked();
      }
    });
  }

  Future<void> toggleDownload(BiliDownloadEntryInfo entry) {
    return _lock.synchronized(() async {
      final task = _activeTasks[entry.cid];
      if (task != null) {
        await _pauseTaskLocked(task, isDelete: false);
        await _scheduleDownloadsLocked();
        return;
      }

      if (_shouldQueueBeforeStart(entry) && _isDownloadTaskLimitReached) {
        await _markEntryWaitingLocked(entry);
        return;
      }

      _schedulerPaused = false;
      if (_isDownloadTaskLimitReached) {
        final task = _findYieldableActiveTask();
        if (task == null) {
          return;
        }
        await _pauseTaskLocked(
          task,
          isDelete: false,
          status: DownloadStatus.wait,
        );
      }

      _ensureInWaitQueue(entry);
      final started = await _startEntryLocked(entry, isManual: true);
      if (started) {
        await _scheduleDownloadsLocked();
      }
    });
  }

  Future<void> startAllDownloads() {
    return _lock.synchronized(() async {
      _schedulerPaused = false;
      var hasWaitingEntry = false;
      for (final entry in waitDownloadQueue) {
        if (_activeTasks.containsKey(entry.cid) || entry.isCompleted) {
          continue;
        }
        if (entry.status == DownloadStatus.wait) {
          hasWaitingEntry = true;
          continue;
        }
        if (_shouldQueueBeforeStart(entry)) {
          entry.status = DownloadStatus.wait;
          await _updateBiliDownloadEntryJson(entry);
          hasWaitingEntry = true;
        }
      }
      if (hasWaitingEntry) {
        await _scheduleDownloadsLocked();
      } else {
        _refreshDownloadState();
      }
    });
  }

  Future<void> pauseAllDownloads() {
    return _lock.synchronized(() async {
      _schedulerPaused = true;
      final tasks = _activeTasks.values.toList();
      for (final task in tasks) {
        await _pauseTaskLocked(task, isDelete: false);
      }
      for (final entry in waitDownloadQueue) {
        if (entry.isCompleted ||
            _activeTasks.containsKey(entry.cid) ||
            entry.status != DownloadStatus.wait) {
          continue;
        }
        entry.status = DownloadStatus.pause;
        await _updateBiliDownloadEntryJson(entry);
      }
      _refreshDownloadState();
    });
  }

  Future<bool> downloadDanmaku({
    required BiliDownloadEntryInfo entry,
    bool isUpdate = false,
    bool Function()? shouldUpdateStatus,
  }) async {
    final cid = entry.pageData?.cid ?? entry.source?.cid;
    if (cid == null) {
      return false;
    }
    final danmakuFile = File(
      path.join(entry.entryDirPath, PathUtils.danmakuName),
    );
    if (isUpdate || !danmakuFile.existsSync()) {
      try {
        if (!isUpdate && (shouldUpdateStatus?.call() ?? true)) {
          _updateEntryStatus(entry, DownloadStatus.getDanmaku);
        }
        final seg = (entry.totalTimeMilli / PlDanmakuController.segmentLength)
            .ceil();

        final res = await Future.wait([
          for (var i = 1; i <= seg; i++)
            DmGrpc.dmSegMobile(cid: cid, segmentIndex: i),
        ]);

        final danmaku = res.removeAt(0).data;
        for (final i in res) {
          if (i case Success(:final response)) {
            danmaku.elems.addAll(response.elems);
          }
        }
        res.clear();
        await danmakuFile.writeAsBytes(danmaku.writeToBuffer());

        return true;
      } catch (e) {
        if (!isUpdate && (shouldUpdateStatus?.call() ?? true)) {
          _updateEntryStatus(entry, DownloadStatus.failDanmaku);
        }
        if (kDebugMode) SmartDialog.showToast(e.toString());
        return false;
      }
    }
    return true;
  }

  Future<void> _downloadSubtitles({
    required BiliDownloadEntryInfo entry,
  }) async {
    try {
      final cid = entry.pageData?.cid ?? entry.source?.cid;
      if (cid == null) return;

      final res = await VideoHttp.playInfo(
        bvid: entry.bvid,
        cid: cid,
        seasonId: entry.seasonId,
        epId: entry.ep?.episodeId,
      );
      final List<Subtitle>? subtitleList;
      if (res case Success(:final response)) {
        subtitleList = response.subtitle?.subtitles;
      } else {
        return;
      }
      if (subtitleList == null || subtitleList.isEmpty) return;

      final vttResults = await Future.wait(
        subtitleList.map((sub) async {
          if (sub.subtitleUrl?.isNotEmpty != true) return null;
          try {
            return await VideoHttp.vttSubtitles(sub.subtitleUrl!);
          } catch (_) {
            return null;
          }
        }),
      );

      final subsDir = Directory(
        path.join(entry.entryDirPath, PathUtils.subtitlesDirName),
      );
      if (!subsDir.existsSync()) {
        await subsDir.create(recursive: true);
      }

      final successfulSubs = <Subtitle>[];
      for (int i = 0; i < subtitleList.length; i++) {
        final vtt = vttResults[i];
        if (vtt == null) continue;
        final sub = subtitleList[i];
        try {
          await File(
            path.join(subsDir.path, PathUtils.subtitleVttName(sub.lan)),
          ).writeAsString(vtt);
          successfulSubs.add(sub);
        } catch (_) {}
      }
      if (successfulSubs.isEmpty) return;

      final indexJson = successfulSubs
          .map(
            (sub) => {
              'lan': sub.lan,
              'lan_doc': sub.isAi
                  ? sub.lanDoc!.substring(0, sub.lanDoc!.length - '（AI）'.length)
                  : sub.lanDoc ?? '',
              'subtitle_url': sub.subtitleUrl ?? '',
              'subtitle_url_v2': sub.subtitleUrlV2,
              'type': sub.isAi ? 1 : 0,
            },
          )
          .toList();
      await File(
        path.join(subsDir.path, PathUtils.subtitleIndexName),
      ).writeAsString(jsonEncode(indexJson));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_downloadSubtitles failed: $e');
      }
    }
  }

  Future<bool> _downloadCover({required BiliDownloadEntryInfo entry}) async {
    try {
      final filePath = path.join(entry.entryDirPath, PathUtils.coverName);
      if (File(filePath).existsSync()) {
        return true;
      }
      final file = (await CacheManager.manager.getFileFromCache(
        entry.cover,
      ))?.file;
      if (file != null) {
        await file.copy(filePath);
      } else {
        await Request.dio.download(entry.cover, filePath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<DownloadPlaybackChapters?> _queryPlaybackChapters({
    required BiliDownloadEntryInfo entry,
    required int fetchedAt,
  }) async {
    try {
      final res = await VideoHttp.playInfo(
        bvid: entry.bvid,
        cid: entry.cid,
        seasonId: entry.seasonId,
        epId: entry.ep?.episodeId,
      );
      if (res case Success(:final response)) {
        final viewPoints = response.viewPoints;
        if (viewPoints != null &&
            viewPoints.isNotEmpty &&
            viewPoints.first.type == 2) {
          return DownloadPlaybackChapters(
            fetchedAt: fetchedAt,
            items: viewPoints
                .map(
                  (item) => DownloadPlaybackChapter(
                    type: item.type,
                    fromMs: item.from == null ? null : item.from! * 1000,
                    toMs: item.to == null ? null : item.to! * 1000,
                    content: item.content,
                    imgUrl: item.imgUrl,
                  ),
                )
                .toList(),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('download playback chapters failed: $e');
      }
    }
    return null;
  }

  Future<DownloadPlaybackSkipSegments?> _querySponsorBlockSegments({
    required BiliDownloadEntryInfo entry,
    required int fetchedAt,
  }) async {
    try {
      final res = await SponsorBlock.getSkipSegments(
        bvid: entry.bvid,
        cid: entry.cid,
      );
      switch (res) {
        case Success(:final response) when response.isNotEmpty:
          return DownloadPlaybackSkipSegments(
            fetchedAt: fetchedAt,
            items: response
                .map(DownloadPlaybackSkipSegment.fromSegmentItemModel)
                .toList(),
          );
        case Error(:final code) when code != 404:
          if (kDebugMode) {
            debugPrint('download sponsorblock failed: $res');
          }
        default:
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('download sponsorblock exception: $e');
      }
    }
    return null;
  }

  Future<void> _writePlaybackMeta({
    required BiliDownloadEntryInfo entry,
    List<SegmentItemModel>? clipInfoList,
  }) async {
    try {
      final fetchedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final results = await Future.wait<Object?>([
        _queryPlaybackChapters(entry: entry, fetchedAt: fetchedAt),
        _querySponsorBlockSegments(entry: entry, fetchedAt: fetchedAt),
      ]);
      final meta = DownloadPlaybackMeta(
        chapters: results[0] as DownloadPlaybackChapters?,
        sponsorBlock: results[1] as DownloadPlaybackSkipSegments?,
        clipInfo: clipInfoList?.isNotEmpty == true
            ? DownloadPlaybackSkipSegments(
                fetchedAt: fetchedAt,
                items: clipInfoList!
                    .map(DownloadPlaybackSkipSegment.fromSegmentItemModel)
                    .toList(),
              )
            : null,
      );
      final playbackMetaFile = File(
        path.join(entry.entryDirPath, PathUtils.playbackMetaName),
      );
      if (meta.isEmpty) {
        if (playbackMetaFile.existsSync()) {
          await playbackMetaFile.tryDel();
        }
        return;
      }
      await playbackMetaFile.writeAsString(jsonEncode(meta.toJson()));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('write playback meta failed: $e');
      }
    }
  }

  Future<void> _startDownload(_ActiveDownloadTask task) async {
    final entry = task.entry;
    try {
      final hasDanmaku = await downloadDanmaku(
        entry: entry,
        shouldUpdateStatus: () => _isCurrentTask(task),
      );
      if (await _restoreInterruptedTaskStatus(task)) {
        return;
      }
      if (!hasDanmaku) {
        await _failTask(task, DownloadStatus.failDanmaku);
        return;
      }

      _updateEntryStatus(entry, DownloadStatus.getPlayUrl);

      final downloadResult = await DownloadHttp.getVideoUrl(
        entry: entry,
        ep: entry.ep,
        source: entry.source,
        pageData: entry.pageData,
      );
      if (await _restoreInterruptedTaskStatus(task)) {
        return;
      }
      final mediaFileInfo = downloadResult.mediaFileInfo;

      final videoDir = Directory(path.join(entry.entryDirPath, entry.typeTag));
      if (!videoDir.existsSync()) {
        await videoDir.create(recursive: true);
      }

      final mediaJsonFile = File(path.join(videoDir.path, _indexFile));
      await Future.wait([
        mediaJsonFile.writeAsString(jsonEncode(mediaFileInfo.toJson())),
        _downloadCover(entry: entry),
        _writePlaybackMeta(
          entry: entry,
          clipInfoList: downloadResult.clipInfoList,
        ),
      ]);

      if (await _restoreInterruptedTaskStatus(task)) {
        return;
      }

      unawaited(_downloadSubtitles(entry: entry));

      switch (mediaFileInfo) {
        case Type1 mediaFileInfo:
          final first = mediaFileInfo.segmentList.first;
          task.videoManager = DownloadManager(
            url: first.url,
            path: path.join(videoDir.path, PathUtils.videoNameType1),
            onReceiveProgress: (progress, total) =>
                _onReceive(task, progress, total),
            onDone: ([error]) => _onDone(task, error),
          );
          break;
        case Type2 mediaFileInfo:
          task.videoManager = DownloadManager(
            url: mediaFileInfo.video.first.baseUrl,
            path: path.join(videoDir.path, PathUtils.videoNameType2),
            onReceiveProgress: (progress, total) =>
                _onReceive(task, progress, total),
            onDone: ([error]) => _onDone(task, error),
          );
          final audio = mediaFileInfo.audio;
          if (audio != null && audio.isNotEmpty) {
            task.audioManager = DownloadManager(
              url: audio.first.baseUrl,
              path: path.join(videoDir.path, PathUtils.audioNameType2),
              onReceiveProgress: null,
              onDone: ([error]) => _onAudioDone(task, error),
            );
          }
          late final first = mediaFileInfo.video.first;
          entry.pageData
            ?..width = first.width
            ..height = first.height;
          entry.ep
            ?..width = first.width
            ..height = first.height;
          _updateBiliDownloadEntryJson(entry);
          break;
        default:
          break;
      }
    } catch (e) {
      if (await _restoreInterruptedTaskStatus(task)) {
        return;
      }
      await _failTask(task, DownloadStatus.failPlayUrl);
      if (kDebugMode) {
        debugPrint('get download url error: $e');
      }
    }
  }

  Future<void> _updateBiliDownloadEntryJson(BiliDownloadEntryInfo entry) {
    final entryJsonFile = File(path.join(entry.entryDirPath, _entryFile));
    return entryJsonFile.writeAsString(jsonEncode(entry.toJson()));
  }

  void _onReceive(_ActiveDownloadTask task, int progress, int total) {
    if (!_isCurrentTask(task)) {
      return;
    }
    final entry = task.entry;
    if (progress == 0 && total != 0) {
      unawaited(_updateBiliDownloadEntryJson(entry..totalBytes = total));
    }
    entry
      ..downloadedBytes = progress
      ..status = DownloadStatus.downloading;
    _refreshDownloadState();
  }

  void _onDone(_ActiveDownloadTask task, [Object? error]) {
    unawaited(_handleVideoDone(task, error));
  }

  void _onAudioDone(_ActiveDownloadTask task, [Object? error]) {
    unawaited(_handleAudioDone(task, error));
  }

  Future<void> _handleVideoDone(_ActiveDownloadTask task, Object? error) async {
    await _lock.synchronized(() async {
      if (!_isCurrentTask(task)) {
        return;
      }

      if (error != null) {
        final status = task.videoManager?.status ?? DownloadStatus.pause;
        task.entry.status = status;
        if (status == DownloadStatus.failDownload) {
          await task.audioManager?.cancel(isDelete: false);
          await _updateBiliDownloadEntryJson(task.entry);
          await _releaseTaskLocked(task, scheduleNext: true);
        } else {
          _refreshDownloadState();
        }
        return;
      }

      final status = switch (task.audioManager?.status) {
        DownloadStatus.downloading => DownloadStatus.audioDownloading,
        DownloadStatus.failDownload => DownloadStatus.failDownloadAudio,
        _ => task.videoManager?.status ?? DownloadStatus.pause,
      };
      task.entry
        ..status = status
        ..downloadedBytes = task.entry.totalBytes;
      if (status == DownloadStatus.completed) {
        await _completeDownloadLocked(task);
      } else if (status == DownloadStatus.failDownload ||
          status == DownloadStatus.failDownloadAudio) {
        await _updateBiliDownloadEntryJson(task.entry);
        await _releaseTaskLocked(task, scheduleNext: true);
      } else {
        await _updateBiliDownloadEntryJson(task.entry);
        _refreshDownloadState();
      }
    });
  }

  Future<void> _handleAudioDone(_ActiveDownloadTask task, Object? error) async {
    await _lock.synchronized(() async {
      if (!_isCurrentTask(task) ||
          task.videoManager?.status != DownloadStatus.completed) {
        return;
      }
      if (error == null) {
        await _completeDownloadLocked(task);
      } else {
        final status = task.audioManager?.status ?? DownloadStatus.pause;
        task.entry.status = status == DownloadStatus.failDownload
            ? DownloadStatus.failDownloadAudio
            : status;
        if (task.entry.status == DownloadStatus.failDownloadAudio) {
          await _updateBiliDownloadEntryJson(task.entry);
          await _releaseTaskLocked(task, scheduleNext: true);
        } else {
          _refreshDownloadState();
        }
      }
    });
  }

  Future<void> _completeDownloadLocked(_ActiveDownloadTask task) async {
    if (!_isCurrentTask(task)) {
      return;
    }
    final entry = task.entry;
    entry
      ..downloadedBytes = entry.totalBytes
      ..isCompleted = true;
    await _updateBiliDownloadEntryJson(entry);
    waitDownloadQueue.remove(entry);
    downloadList.insert(0, entry);
    completedEntryNotifier.notify(entry);
    await _releaseTaskLocked(task, scheduleNext: true);
    flagNotifier.refresh();
  }

  void nextDownload() {
    unawaited(_lock.synchronized(_scheduleDownloadsLocked));
  }

  Future<void> deleteDownload({
    required BiliDownloadEntryInfo entry,
    bool removeList = false,
    bool removeQueue = false,
    bool refresh = true,
    bool downloadNext = true,
  }) async {
    if (removeList) {
      downloadList.remove(entry);
    }
    if (removeQueue) {
      waitDownloadQueue.remove(entry);
    }
    if (_activeTasks.containsKey(entry.cid)) {
      await cancelDownload(
        entry: entry,
        isDelete: true,
        downloadNext: downloadNext,
      );
    }
    final downloadDir = Directory(entry.pageDirPath);
    if (downloadDir.existsSync()) {
      if (!await downloadDir.lengthGte(2)) {
        await downloadDir.tryDel(recursive: true);
      } else {
        final entryDir = Directory(entry.entryDirPath);
        if (entryDir.existsSync()) {
          await entryDir.tryDel(recursive: true);
        }
      }
    }
    if (refresh) {
      flagNotifier.refresh();
    }
  }

  Future<void> deletePage({
    required String pageDirPath,
    bool refresh = true,
  }) async {
    await Directory(pageDirPath).tryDel(recursive: true);
    downloadList.removeWhere((e) => e.pageDirPath == pageDirPath);
    if (refresh) {
      flagNotifier.refresh();
    }
  }

  Future<void> cancelDownload({
    BiliDownloadEntryInfo? entry,
    required bool isDelete,
    bool downloadNext = true,
  }) async {
    await _lock.synchronized(() async {
      if (entry == null) {
        _schedulerPaused = !isDelete;
        final tasks = _activeTasks.values.toList();
        for (final task in tasks) {
          await _pauseTaskLocked(task, isDelete: isDelete);
        }
        if (downloadNext) {
          await _scheduleDownloadsLocked();
        } else {
          _refreshDownloadState();
        }
        return;
      }

      final target = entry;
      final task = _activeTasks[target.cid];
      if (task == null) {
        return;
      }
      await _pauseTaskLocked(task, isDelete: isDelete);
      if (isDelete) {
        waitDownloadQueue.remove(target);
      }
      if (downloadNext) {
        await _scheduleDownloadsLocked();
      } else {
        _refreshDownloadState();
      }
    });
  }

  static String get _exportBasePath =>
      path.join('/storage/emulated/0/Download', 'PiliMax');

  static Future<String> exportEntry(
    BiliDownloadEntryInfo entry,
    ValueChanged<double>? onProgress,
  ) async {
    final srcDir = Directory(entry.entryDirPath);
    if (!srcDir.existsSync()) throw '缓存目录不存在';

    final baseDir = Directory(_exportBasePath);
    if (!baseDir.existsSync()) await baseDir.create(recursive: true);

    final nomedia = File(path.join(_exportBasePath, '.nomedia'));
    if (!nomedia.existsSync()) await nomedia.create();

    final dirName = _sanitizeDirName(entry.title, entry.avid);
    final subDirName = path.basename(entry.entryDirPath);
    final destDir = Directory(path.join(_exportBasePath, dirName, subDirName));
    final destPath = destDir.path;

    if (destDir.existsSync() && !await _dirHasDifference(srcDir, destDir)) {
      return destPath;
    }

    final totalSize = await _dirSize(srcDir);
    int copiedSize = 0;

    await _copyDir(srcDir, destDir, (fileCopied) {
      copiedSize += fileCopied;
      if (totalSize > 0) onProgress?.call(copiedSize / totalSize);
    });

    return destPath;
  }

  static Future<void> _copyDir(
    Directory src,
    Directory dest,
    void Function(int bytesCopied) onProgress,
  ) async {
    if (!dest.existsSync()) await dest.create(recursive: true);
    await for (final entity in src.list()) {
      if (entity is File) {
        final target = File(path.join(dest.path, path.basename(entity.path)));
        if (!target.existsSync() ||
            target.lengthSync() != entity.lengthSync()) {
          await entity.copy(target.path);
        }
        onProgress(entity.lengthSync());
      } else if (entity is Directory) {
        await _copyDir(
          entity,
          Directory(path.join(dest.path, path.basename(entity.path))),
          onProgress,
        );
      }
    }
  }

  static Future<int> _dirSize(Directory dir) async {
    int size = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) size += await entity.length();
    }
    return size;
  }

  static Future<bool> _dirHasDifference(Directory src, Directory dest) async {
    await for (final entity in src.list(recursive: true)) {
      if (entity is! File) continue;
      final relPath = path.relative(entity.path, from: src.path);
      final target = File(path.join(dest.path, relPath));
      if (!target.existsSync()) return true;
      final diff = (await entity.length()) - (await target.length());
      if (diff.abs() > 1024) return true;
      if (diff == 0) continue;
      if (target.lastModifiedSync().isBefore(entity.lastModifiedSync())) {
        return true;
      }
    }
    return false;
  }

  static String _sanitizeDirName(String title, int avid) {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return '${clean.isEmpty ? 'video' : clean}_$avid';
  }
}

class _ActiveDownloadTask {
  _ActiveDownloadTask({required this.entry, required this.isManual});

  final BiliDownloadEntryInfo entry;
  final bool isManual;
  DownloadManager? videoManager;
  DownloadManager? audioManager;
  DownloadStatus? interruptedStatus;

  Future<void> cancel({required bool isDelete}) async {
    await videoManager?.cancel(isDelete: isDelete);
    await audioManager?.cancel(isDelete: isDelete);
    videoManager = null;
    audioManager = null;
  }
}

typedef SetNotifier = Set<VoidCallback>;

extension SetNotifierExt on SetNotifier {
  void refresh() {
    for (final i in this) {
      i();
    }
  }
}

extension EntryNotifierExt on Set<ValueChanged<BiliDownloadEntryInfo>> {
  void notify(BiliDownloadEntryInfo entry) {
    for (final i in this) {
      i(entry);
    }
  }
}
