import 'dart:async';

import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliMax/grpc/audio.dart';
import 'package:PiliMax/grpc/bilibili/app/listener/v1.pb.dart'
    show
        DetailItem,
        PlayItem,
        PlayURLResp,
        PlaylistSource,
        PlayInfo,
        ThumbUpReq_ThumbType,
        ListOrder,
        DashItem,
        ResponseUrl;
import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/http/constants.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliMax/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliMax/pages/common/common_intro_controller.dart'
    show FavMixin, IntroAction;
import 'package:PiliMax/pages/dynamics_repost/view.dart';
import 'package:PiliMax/pages/main_reply/view.dart';
import 'package:PiliMax/pages/setting/models/play_settings.dart'
    show kMaxVolume;
import 'package:PiliMax/pages/sponsor_block/block_mixin.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/pgc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/play_repeat.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:PiliMax/services/debug_log_service.dart';
import 'package:PiliMax/services/service_locator.dart';
import 'package:PiliMax/services/shutdown_timer_service.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/connectivity_utils.dart';
import 'package:PiliMax/utils/extension/iterable_ext.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/loading_action_mixin.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/share_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:PiliMax/utils/video_utils.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';

class _AudioPlaybackIdentity {
  const _AudioPlaybackIdentity({
    required this.player,
    required this.oid,
    required this.subId,
    required this.index,
    required this.item,
  });

  final Player player;
  final Int64 oid;
  final Int64? subId;
  final int? index;
  final DetailItem? item;
}

class AudioController extends GetxController
    with
        GetTickerProviderStateMixin,
        TripleMixin,
        LoadingActionMixin<IntroAction>,
        FavMixin,
        BlockConfigMixin,
        BlockMixin {
  late Int64 id;
  late Int64 oid;
  late List<Int64> subId;
  late int itemType;
  Int64? extraId;
  late final PlaylistSource from;
  @override
  late final bool isUgc = itemType == 1;

  final audioItem = Rxn<DetailItem>();

  bool _hasInit = false;
  @override
  Player? player;
  late int cacheAudioQa;

  late bool isDragging = false;
  final RxInt position = RxInt(0);
  final RxInt duration = RxInt(0);

  late final AnimationController animController;

  List<StreamSubscription>? _subscriptions;
  Timer? _autoTailSkipCompletedTimer;
  int _autoTailSkipGeneration = 0;
  int _playIndexGeneration = 0;
  int? _audioSwitchZeroPositionGuardGeneration;
  _AudioPlaybackIdentity? _consumedCompletedIdentity;
  int _heartDuration = 0;
  bool _completedHeartBeatSynced = false;

  int? index;
  List<DetailItem>? playlist;
  final Map<String, int> _initialPlaylistProgress = {};

  late double speed = 1.0;

  late final Rx<PlayRepeat> playMode = Pref.audioPlayMode.obs;

  @override
  late final isLogin = Accounts.main.isLogin;

  Duration? _start;
  VideoDetailController? _videoDetailController;
  bool get _hasVideoDetailController => _videoDetailController != null;
  bool get _shouldSyncVideoDetailMetadata => _hasVideoDetailController;
  bool get _shouldSyncVideoDetailSideEffects =>
      !_hasVideoDetailController || _isAppInForeground;
  bool get _isAppInForeground =>
      switch (WidgetsBinding.instance.lifecycleState) {
        AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };

  String? _prev;
  String? _next;
  bool get reachStart => _prev == null;

  ListOrder order = ListOrder.ORDER_NORMAL;

  double? _lastVolume;
  late final RxDouble desktopVolume = RxDouble(Pref.desktopVolume);

  void toggleVolume() {
    if (_lastVolume == null) {
      _lastVolume = desktopVolume.value;
      setVolume(0, clearLastVolme: false);
    } else {
      setVolume(_lastVolume!);
    }
  }

  void setVolume(double volume, {bool clearLastVolme = true}) {
    if (clearLastVolme) {
      _lastVolume = null;
    }
    desktopVolume.value = volume;
    player?.setVolume(volume * 100);
  }

  void syncVolume([_]) {
    final volume = desktopVolume.value;
    PlPlayerController.instance
      ?..volume.value = volume
      ..videoPlayerController?.setVolume(volume * 100);
    GStorage.setting.put(SettingBoxKey.desktopVolume, volume.toPrecision(3));
  }

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    oid = Int64(args['oid']);
    final id = args['id'];
    this.id = id != null ? Int64(id) : oid;
    subId = (args['subId'] as List<int>?)?.map(Int64.new).toList() ?? [oid];
    itemType = args['itemType'];
    from = args['from'];
    _start = args['start'];
    final int? extraId = args['extraId'];
    if (extraId != null) {
      this.extraId = Int64(extraId);
    }
    _initPlaylistProgressSnapshot(args['playlistProgress']);
    if (args['heroTag'] case String heroTag) {
      try {
        _videoDetailController = Get.find<VideoDetailController>(tag: heroTag);
      } catch (_) {}
    }

    _queryPlayList(isInit: true);

    final String? audioUrl = args['audioUrl'];
    final hasAudioUrl = audioUrl != null;
    if (hasAudioUrl) {
      _querySponsorBlock();
      _onOpenMedia(audioUrl, ua: BrowserUa.pc, referer: HttpString.baseUrl);
    }
    ConnectivityUtils.isWiFi.then((isWiFi) {
      cacheAudioQa = isWiFi ? Pref.defaultAudioQa : Pref.defaultAudioQaCellular;
      if (!hasAudioUrl) {
        _queryPlayUrl();
      }
    });
    videoPlayerServiceHandler
      ?..onPlay = onPlay
      ..onPause = onPause
      ..onSeek = onSeek;

    animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    if (shutdownTimerService.isActive) {
      shutdownTimerService
        ..onPause = onPause
        ..isPlaying = isPlaying;
    }
  }

  bool isPlaying() {
    return player?.state.playing ?? false;
  }

  Future<void>? onPlay() {
    _cancelAutoTailSkipCompleted();
    if (player?.state.completed == true) {
      _resetHeartBeatProgress();
    }
    return player?.play();
  }

  Future<void>? onPause() {
    _cancelAutoTailSkipCompleted(clearConsumed: false);
    _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
    return player?.pause();
  }

  Future<void>? onSeek(
    Duration duration, {
    BlockSkipSource skipSource = BlockSkipSource.manual,
  }) {
    _audioSwitchZeroPositionGuardGeneration = null;
    _cancelAutoTailSkipCompleted();
    _heartDuration = duration.inSeconds;
    _completedHeartBeatSynced = false;
    if (skipSource == BlockSkipSource.automatic) {
      _scheduleAutoTailSkipCompleted(duration);
    }
    return player?.seek(duration);
  }

  void _cancelAutoTailSkipCompleted({bool clearConsumed = true}) {
    _autoTailSkipGeneration++;
    _autoTailSkipCompletedTimer?.cancel();
    _autoTailSkipCompletedTimer = null;
    if (clearConsumed) {
      _consumedCompletedIdentity = null;
    }
  }

  _AudioPlaybackIdentity? _currentPlaybackIdentity([Player? currentPlayer]) {
    final resolvedPlayer = currentPlayer ?? player;
    if (resolvedPlayer == null) {
      return null;
    }
    return _AudioPlaybackIdentity(
      player: resolvedPlayer,
      oid: oid,
      subId: subId.firstOrNull,
      index: index,
      item: audioItem.value,
    );
  }

  bool _isSamePlaybackIdentity(_AudioPlaybackIdentity identity) {
    return !isClosed &&
        identical(player, identity.player) &&
        oid == identity.oid &&
        subId.firstOrNull == identity.subId &&
        index == identity.index &&
        identical(audioItem.value, identity.item);
  }

  bool get _enableHeartBeat => Accounts.heartbeat.isLogin && !Pref.historyPause;

  bool get _canReportHeartBeat => isUgc && _enableHeartBeat;

  void _unawaitedHeartBeat(Future<void>? future) {
    if (future != null) {
      unawaited(future);
    }
  }

  Future<void>? _sendHeartBeat(int progress) {
    final currentCid = subId.firstOrNull?.toInt();
    if (!_canReportHeartBeat || currentCid == null || progress == 0) {
      return null;
    }
    return VideoHttp.heartBeat(
      bvid: IdUtils.av2bv(oid.toInt()),
      cid: currentCid,
      progress: progress,
      videoType: VideoType.ugc,
    );
  }

  Future<void>? _reportPlayingHeartBeat(Duration currentPosition) {
    final currentPlayer = player;
    if (currentPlayer?.state.playing != true) {
      return null;
    }
    final progress = currentPosition.inSeconds;
    if (progress <= 0 || progress - _heartDuration < 5) {
      return null;
    }
    _heartDuration = progress;
    return _sendHeartBeat(progress);
  }

  Future<void>? _reportStatusHeartBeat({bool force = false}) {
    final currentPlayer = player;
    if (currentPlayer == null) {
      return null;
    }
    if (_completedHeartBeatSynced && currentPlayer.state.completed) {
      return null;
    }
    final progress = _rawAudioPosition(currentPlayer).inSeconds;
    if (progress <= 0 || (!force && progress - _heartDuration < 2)) {
      return null;
    }
    _heartDuration = progress;
    return _sendHeartBeat(progress);
  }

  void _recordCurrentAudioProgress(int progress) {
    final currentCid = subId.firstOrNull?.toInt();
    if (!isUgc || currentCid == null || progress == 0) {
      return;
    }
    _initialPlaylistProgress[_progressKey(oid.toInt(), currentCid)] = progress;
    final currentItem = audioItem.value;
    if (currentItem != null && currentItem.parts.length <= 1) {
      currentItem.progress = Int64(progress);
    }
  }

  Future<void>? _reportCompletedHeartBeat() {
    if (_completedHeartBeatSynced) {
      return null;
    }
    _completedHeartBeatSynced = true;
    _heartDuration = -1;
    _recordCurrentAudioProgress(-1);
    return _sendHeartBeat(-1);
  }

  void _resetHeartBeatProgress() {
    _heartDuration = 0;
    _completedHeartBeatSynced = false;
  }

  void _scheduleAutoTailSkipCompleted(Duration target) {
    final currentPlayer = player;
    if (currentPlayer == null) return;
    final identity = _currentPlaybackIdentity(currentPlayer);
    if (identity == null) return;
    final total = _rawAudioDuration(currentPlayer);
    if (total <= Duration.zero) return;

    final remaining = total - target;
    if (remaining < Duration.zero ||
        remaining > const Duration(milliseconds: 1500)) {
      return;
    }

    final generation = _autoTailSkipGeneration;
    _autoTailSkipCompletedTimer?.cancel();
    unawaited(
      DebugLogService.log(
        'audio.tail_skip',
        'schedule completed fallback',
        extra: {
          'oid': oid.toString(),
          'subId': subId.firstOrNull?.toString(),
          'targetMs': target.inMilliseconds,
          'durationMs': total.inMilliseconds,
        },
      ),
    );
    _autoTailSkipCompletedTimer = Timer(
      remaining + const Duration(seconds: 1),
      () {
        if (generation != _autoTailSkipGeneration ||
            !_isSamePlaybackIdentity(identity)) {
          return;
        }
        final currentDuration = _rawAudioDuration(currentPlayer);
        if (currentDuration > Duration.zero) {
          position.value = currentDuration.inSeconds;
          _videoDetailController?.playedTime = currentDuration;
          videoPlayerServiceHandler?.onPositionChange(currentDuration);
        }
        _handlePlaybackCompleted(markConsumed: true);
      },
    );
  }

  void _handlePlaybackCompleted({bool markConsumed = false}) {
    final currentPlayer = player;
    final consumedIdentity = _consumedCompletedIdentity;
    if (currentPlayer != null &&
        consumedIdentity != null &&
        identical(consumedIdentity.player, currentPlayer)) {
      return;
    }
    final currentIdentity = markConsumed
        ? _currentPlaybackIdentity(currentPlayer)
        : null;
    _cancelAutoTailSkipCompleted(clearConsumed: false);
    if (currentIdentity != null) {
      _consumedCompletedIdentity = currentIdentity;
    } else {
      _consumedCompletedIdentity = null;
    }
    unawaited(
      DebugLogService.log(
        'audio.completed',
        'handle playback completed',
        extra: {
          'oid': oid.toString(),
          'subId': subId.firstOrNull?.toString(),
          'index': index,
          'markConsumed': markConsumed,
          'playMode': playMode.value.name,
        },
      ),
    );
    _unawaitedHeartBeat(_reportCompletedHeartBeat());
    if (shutdownTimerService.isWaiting) {
      shutdownTimerService.handleWaiting();
    } else {
      switch (playMode.value) {
        case PlayRepeat.pause:
          break;
        case PlayRepeat.listOrder:
          playNext(nextPart: true);
          break;
        case PlayRepeat.singleCycle:
          onPlay();
          break;
        case PlayRepeat.listCycle:
          if (!playNext(nextPart: true)) {
            if (index != null && index != 0 && playlist != null) {
              playIndex(0);
            } else {
              onPlay();
            }
          }
          break;
        case PlayRepeat.autoPlayRelated:
          break;
      }
    }
  }

  Duration _rawAudioPosition([Player? currentPlayer]) {
    final statePosition = currentPlayer?.state.position;
    if (statePosition != null && statePosition > Duration.zero) {
      return statePosition;
    }
    return Duration(seconds: position.value);
  }

  Duration _rawAudioDuration([Player? currentPlayer]) {
    final stateDuration = currentPlayer?.state.duration;
    if (stateDuration != null && stateDuration > Duration.zero) {
      return stateDuration;
    }
    return Duration(seconds: duration.value);
  }

  Future<void> syncBackToVideoPlayer() async {
    final videoDetailController = _videoDetailController;
    final audioPlayer = player;
    if (videoDetailController == null || audioPlayer == null) {
      return;
    }
    final audioPosition = _rawAudioPosition(audioPlayer);
    if (audioPosition <= Duration.zero) {
      return;
    }
    await _syncVideoSourceIfNeeded(videoDetailController, audioPosition);
    final currentCid = subId.firstOrNull?.toInt();
    final currentBvid = IdUtils.av2bv(oid.toInt());
    if (currentCid != null &&
        videoDetailController.bvid == currentBvid &&
        videoDetailController.cid.value == currentCid) {
      videoDetailController
        ..playedTime = audioPosition
        ..defaultST = audioPosition;
      final plPlayerController = videoDetailController.plPlayerController;
      plPlayerController.position.value = audioPosition.inSeconds;
      if (plPlayerController.videoPlayerController != null) {
        await plPlayerController.seekTo(audioPosition, isSeek: false);
      }
    }
  }

  Future<void> _syncVideoSourceIfNeeded(
    VideoDetailController videoDetailController,
    Duration audioPosition,
  ) async {
    final currentCid = subId.firstOrNull?.toInt();
    if (currentCid == null) {
      return;
    }

    final currentAid = oid.toInt();
    final currentBvid = IdUtils.av2bv(currentAid);
    if (videoDetailController.bvid == currentBvid &&
        videoDetailController.cid.value == currentCid) {
      return;
    }

    if (videoDetailController.isUgc) {
      try {
        final ugcIntroController = Get.find<UgcIntroController>(
          tag: videoDetailController.heroTag,
        );
        final target = _findUgcEpisode(
          ugcIntroController,
          aid: currentAid,
          bvid: currentBvid,
          cid: currentCid,
        );
        if (target != null) {
          await ugcIntroController.onChangeEpisode(
            target,
            fromAudioPage: true,
            audioPosition: audioPosition,
          );
        }
      } catch (_) {}
    } else {
      try {
        final pgcIntroController = Get.find<PgcIntroController>(
          tag: videoDetailController.heroTag,
        );
        final target = _findPgcEpisode(
          pgcIntroController,
          aid: currentAid,
          bvid: currentBvid,
          cid: currentCid,
        );
        if (target != null) {
          await pgcIntroController.onChangeEpisode(
            target,
            fromAudioPage: true,
            audioPosition: audioPosition,
          );
        }
      } catch (_) {}
    }
  }

  ugc.BaseEpisodeItem? _findUgcEpisode(
    UgcIntroController controller, {
    required int aid,
    required String bvid,
    required int cid,
  }) {
    final videoDetail = controller.videoDetail.value;
    for (final part in videoDetail.pages ?? const []) {
      if (part.cid == cid) return part;
    }
    for (final section in videoDetail.ugcSeason?.sections ?? const []) {
      for (final episode in section.episodes ?? const []) {
        if (episode.cid == cid) {
          return episode;
        }
        if (episode.aid == aid || episode.bvid == bvid) {
          return ugc.BaseEpisodeItem(
            aid: episode.aid ?? aid,
            bvid: episode.bvid ?? bvid,
            cid: cid,
            title: episode.title,
            cover: episode.cover,
            badge: episode.badge,
          );
        }
        for (final part in episode.pages ?? const []) {
          if (part.cid == cid) return part;
        }
      }
    }
    return null;
  }

  pgc.EpisodeItem? _findPgcEpisode(
    PgcIntroController controller, {
    required int aid,
    required String bvid,
    required int cid,
  }) {
    for (final episode in controller.pgcItem.episodes ?? const []) {
      if (episode.cid == cid || episode.aid == aid || episode.bvid == bvid) {
        return episode;
      }
    }
    return null;
  }

  bool _detailItemContainsSubId(DetailItem item, int cid) =>
      item.parts.any((part) => part.subId.toInt() == cid);

  Future<List<Int64>> _defaultSubIdsForPlaylistItem(
    DetailItem audioItem,
    PlayItem item,
    List<Int64>? requestedSubId, {
    required bool preferHistoryPart,
    required bool Function() isCurrent,
  }) async {
    if (requestedSubId != null) {
      return requestedSubId;
    }

    final parts = audioItem.parts;
    final fallbackSubId = item.subId.firstOrNull ?? parts.firstOrNull?.subId;
    if (fallbackSubId == null) {
      return const <Int64>[];
    }

    if (preferHistoryPart && isUgc && parts.length > 1) {
      try {
        final fallbackCid = fallbackSubId.toInt();
        final res = await VideoHttp.playInfo(
          bvid: IdUtils.av2bv(item.oid.toInt()),
          cid: fallbackCid,
        );
        if (!isCurrent()) {
          return [fallbackSubId];
        }
        if (res case Success(:final response)) {
          final lastPlayCid = response.lastPlayCid;
          if (lastPlayCid != null &&
              lastPlayCid > 0 &&
              _detailItemContainsSubId(audioItem, lastPlayCid)) {
            return [Int64(lastPlayCid)];
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('resolve audio history cid failed: $e');
      }

      final lastPartCid = audioItem.lastPart.toInt();
      if (lastPartCid > 0 && _detailItemContainsSubId(audioItem, lastPartCid)) {
        return [Int64(lastPartCid)];
      }
    }

    return item.subId.isNotEmpty ? item.subId : [fallbackSubId];
  }

  String _progressKey(int aid, int cid) => '$aid:$cid';

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  void _initPlaylistProgressSnapshot(dynamic raw) {
    if (raw is! Iterable) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final aid = _readInt(item['aid']);
      final cid = _readInt(item['cid']);
      final progress = _readInt(item['progress']);
      if (aid == null ||
          aid <= 0 ||
          cid == null ||
          cid <= 0 ||
          progress == null ||
          progress <= 0) {
        continue;
      }
      _initialPlaylistProgress[_progressKey(aid, cid)] = progress;
    }
  }

  int _normalizeProgressSeconds(
    int progress, {
    required int durationSeconds,
  }) {
    if (progress <= 0) return 0;
    if (durationSeconds > 0 &&
        progress > durationSeconds + 30 &&
        progress ~/ Duration.millisecondsPerSecond <= durationSeconds + 30) {
      return progress ~/ Duration.millisecondsPerSecond;
    }
    if (durationSeconds <= 0 &&
        progress > 12 * Duration.secondsPerHour) {
      return progress ~/ Duration.millisecondsPerSecond;
    }
    return progress;
  }

  int _detailItemDurationSeconds(DetailItem item, int cid) {
    final part = item.parts.firstWhereOrNull((e) => e.subId.toInt() == cid);
    if (part != null && part.duration > 0) {
      return part.duration.toInt();
    }
    return item.arc.duration.toInt();
  }

  int _detailProgressSeconds(DetailItem item, int cid) {
    if (item.parts.length > 1 && item.lastPart.toInt() != cid) {
      return 0;
    }
    final durationSeconds = _detailItemDurationSeconds(item, cid);
    final progress = _normalizeProgressSeconds(
      item.progress.toInt(),
      durationSeconds: durationSeconds,
    );
    if (progress > 0) {
      return progress;
    }
    return _normalizeProgressSeconds(
      item.lastPlayTime.toInt(),
      durationSeconds: durationSeconds,
    );
  }

  int _playlistItemProgressSeconds(DetailItem item, int aid, int cid) {
    if (_initialPlaylistProgress[_progressKey(aid, cid)]
        case final snapshotProgress?) {
      if (snapshotProgress <= 0) return 0;
      return snapshotProgress;
    }
    return _detailProgressSeconds(item, cid);
  }

  void _armAudioSwitchZeroPositionGuard() {
    final generation = _playIndexGeneration;
    _audioSwitchZeroPositionGuardGeneration = generation;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_audioSwitchZeroPositionGuardGeneration == generation) {
        _audioSwitchZeroPositionGuardGeneration = null;
      }
    });
  }

  bool _shouldIgnoreAudioSwitchZeroPosition(Duration position) {
    return position == Duration.zero &&
        this.position.value > 0 &&
        _audioSwitchZeroPositionGuardGeneration == _playIndexGeneration;
  }

  void _updateCurrItem(DetailItem item) {
    audioItem.value = item;
    hasLike.value = item.stat.hasLike_7;
    coinNum.value = item.stat.hasCoin_8 ? 2 : 0;
    hasFav.value = item.stat.hasFav;
    if (isClosed) {
      return;
    }
    final expectedOid = oid;
    final expectedSubId = subId.firstOrNull;
    final expectedCid = (expectedSubId ?? expectedOid).toInt();
    if (_shouldSyncVideoDetailSideEffects) {
      videoPlayerServiceHandler?.onVideoDetailChange(
        item,
        expectedCid,
        hashCode.toString(),
      );
    } else if (_shouldSyncVideoDetailMetadata) {
      unawaited(
        videoPlayerServiceHandler?.onAudioDetailChangeInBackground(
              item,
              expectedCid,
              hashCode.toString(),
              isCurrent: () =>
                  !isClosed &&
                  oid == expectedOid &&
                  subId.firstOrNull == expectedSubId,
            ) ??
            Future<void>.value(),
      );
    }
  }

  Future<void> _queryPlayList({
    bool isInit = false,
    bool isLoadPrev = false,
    bool isLoadNext = false,
  }) async {
    final res = await AudioGrpc.audioPlayList(
      id: id,
      oid: isInit ? oid : null,
      subId: isInit ? subId : null,
      itemType: isInit ? itemType : null,
      from: isInit ? from : null,
      next: isLoadPrev
          ? _prev
          : isLoadNext
          ? _next
          : null,
      extraId: extraId,
      order: order,
    );
    if (res case Success(:final response)) {
      if (isInit) {
        late final paginationReply = response.paginationReply;
        _prev = response.reachStart ? null : paginationReply.prev;
        _next = response.reachEnd ? null : paginationReply.next;
        final index = response.list.indexWhere((e) => e.item.oid == oid);
        if (index != -1) {
          this.index = index;
          _updateCurrItem(response.list[index]);
          playlist = response.list;
        }
      } else if (isLoadPrev) {
        _prev = response.reachStart ? null : response.paginationReply.prev;
        if (response.list.isNotEmpty) {
          index += response.list.length;
          playlist?.insertAll(0, response.list);
        }
      } else if (isLoadNext) {
        _next = response.reachEnd ? null : response.paginationReply.next;
        if (response.list.isNotEmpty) {
          playlist?.addAll(response.list);
        }
      }
    } else {
      res.toast();
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _querySponsorBlock() {
    if (isUgc && enableSponsorBlock) {
      try {
        final bvid = IdUtils.av2bv(oid.toInt());
        final cid = subId.first.toInt();
        querySponsorBlock(bvid: bvid, cid: cid);
      } catch (_) {}
    }
  }

  Future<bool> _queryPlayUrl() async {
    unawaited(
      DebugLogService.log(
        'audio.playurl',
        'query play url start',
        extra: {
          'oid': oid.toString(),
          'subId': subId.map((e) => e.toString()).toList(),
          'itemType': itemType,
        },
      ),
    );
    _querySponsorBlock();
    final res = await AudioGrpc.audioPlayUrl(
      itemType: itemType,
      oid: oid,
      subId: subId,
    );
    if (res case Success(:final response)) {
      unawaited(
        DebugLogService.log(
          'audio.playurl',
          'query play url success',
          extra: {
            'oid': oid.toString(),
            'subId': subId.firstOrNull?.toString(),
          },
        ),
      );
      _onPlay(response);
      return true;
    } else {
      unawaited(
        DebugLogService.log(
          'audio.playurl',
          'query play url failed',
          extra: {
            'oid': oid.toString(),
            'subId': subId.firstOrNull?.toString(),
            'error': res.toString(),
          },
        ),
      );
      res.toast();
      return false;
    }
  }

  void _onPlay(PlayURLResp data) {
    final PlayInfo? playInfo = data.playerInfo.values.firstOrNull;
    if (playInfo != null) {
      if (playInfo.hasPlayDash()) {
        final playDash = playInfo.playDash;
        final audios = playDash.audio;
        if (audios.isEmpty) {
          return;
        }
        position.value = 0;
        final audio = audios.findClosestTarget(
          (e) => e.id <= cacheAudioQa,
          (a, b) => a.id > b.id ? a : b,
        );
        _onOpenMedia(VideoUtils.getCdnUrl(audio.playUrls));
      } else if (playInfo.hasPlayUrl()) {
        final playUrl = playInfo.playUrl;
        final durls = playUrl.durl;
        if (durls.isEmpty) {
          return;
        }
        final durl = durls.first;
        position.value = 0;
        _onOpenMedia(VideoUtils.getCdnUrl(durl.playUrls));
      }
    }
  }

  Future<void> _onOpenMedia(
    String url, {
    String ua = Constants.userAgentApp,
    String? referer,
  }) async {
    await _initPlayerIfNeeded();
    final currentPlayer = player;
    if (currentPlayer == null) return;
    final start = _start;
    _resetHeartBeatProgress();
    unawaited(
      DebugLogService.log(
        'audio.open',
        'open media',
        extra: {
          'oid': oid.toString(),
          'subId': subId.firstOrNull?.toString(),
          'startMs': start?.inMilliseconds,
        },
      ),
    );
    currentPlayer.setMediaHeader(
      userAgent: ua,
      // mpv cannot clear referer option
      headers: {'Referer': ?referer},
    );
    await currentPlayer.open(Media(url, start: start));
    _consumedCompletedIdentity = null;
    final stateDuration = _rawAudioDuration(currentPlayer);
    if (stateDuration > Duration.zero) {
      duration.value = stateDuration.inSeconds;
    }
    final statePosition = _rawAudioPosition(currentPlayer);
    if (start != null && start > Duration.zero) {
      position.value = start.inSeconds;
      _armAudioSwitchZeroPositionGuard();
    } else if (statePosition > Duration.zero) {
      position.value = statePosition.inSeconds;
      _armAudioSwitchZeroPositionGuard();
    }
    _start = null;
  }

  Future<void> _initPlayerIfNeeded() async {
    if (_hasInit) return;
    _hasInit = true;
    assert(player == null, _subscriptions = null);
    player = await Player.create(
      configuration: PlayerConfiguration(
        options: {
          'volume': PlatformUtils.isDesktop
              ? (desktopVolume.value * 100).toString()
              : Pref.playerVolume.toString(),
          'volume-max': kMaxVolume.toString(),
          ...Pref.initBuffer(),
        },
      ),
    );
    if (isClosed) {
      player!.dispose();
      player = null;
      return;
    }
    final stream = player!.stream;
    _subscriptions = [
      stream.position.listen((position) {
        if (isDragging) return;
        if (_shouldIgnoreAudioSwitchZeroPosition(position)) return;
        if (position > Duration.zero) {
          _audioSwitchZeroPositionGuardGeneration = null;
        }
        final seconds = position.inSeconds;
        if (seconds != this.position.value) {
          this.position.value = seconds;
          _recordCurrentAudioProgress(seconds);
          _videoDetailController?.playedTime = position;
          videoPlayerServiceHandler?.onPositionChange(position);
          _unawaitedHeartBeat(_reportPlayingHeartBeat(position));
        }
      }),
      stream.duration.listen((duration) {
        this.duration.value = duration.inSeconds;
      }),
      stream.playing.listen((playing) {
        final PlayerStatus playerStatus;
        if (playing) {
          animController.forward();
          playerStatus = PlayerStatus.playing;
        } else {
          animController.reverse();
          playerStatus = PlayerStatus.paused;
        }
        videoPlayerServiceHandler?.onStatusChange(playerStatus, false, false);
      }),
      stream.completed.listen((completed) {
        if (!completed) return;
        _videoDetailController?.playedTime = _rawAudioDuration(player);
        videoPlayerServiceHandler?.onStatusChange(
          PlayerStatus.completed,
          false,
          false,
        );
        _handlePlaybackCompleted(markConsumed: true);
      }),
    ];
  }

  @override
  Future<void> actionLikeVideo() async {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final newVal = !hasLike.value;
    final res = await AudioGrpc.audioThumbUp(
      oid: oid,
      subId: subId,
      itemType: itemType,
      type: newVal
          ? ThumbUpReq_ThumbType.LIKE
          : ThumbUpReq_ThumbType.CANCEL_LIKE,
    );
    if (res case Success(:final response)) {
      hasLike.value = newVal;
      try {
        audioItem.value!.stat
          ..hasLike_7 = newVal
          ..like += newVal ? 1 : -1;
        audioItem.refresh();
      } catch (_) {}
      SmartDialog.showToast(response.message);
    } else {
      res.toast();
    }
  }

  @override
  Future<void> actionTriple() async {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    final res = await AudioGrpc.audioTripleLike(
      oid: oid,
      subId: subId,
      itemType: itemType,
    );
    if (res case Success(:final response)) {
      hasLike.value = true;
      if (response.coinOk && !hasCoin) {
        coinNum.value = 2;
        GlobalData().afterCoin(2);
        try {
          audioItem.value!.stat
            ..hasCoin_8 = true
            ..coin += 2;
          audioItem.refresh();
        } catch (_) {}
      }
      hasFav.value = true;
      if (!hasCoin) {
        SmartDialog.showToast('投币失败');
      } else {
        SmartDialog.showToast('三连成功');
      }
    } else {
      res.toast();
    }
  }

  @override
  int get copyright => audioItem.value?.arc.copyright ?? 1;

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) async {
    final res = await AudioGrpc.audioCoinAdd(
      oid: oid,
      subId: subId,
      itemType: itemType,
      num: coin,
      thumbUp: coinWithLike,
    );
    if (res.isSuccess) {
      final updateLike = !hasLike.value && coinWithLike;
      if (updateLike) {
        hasLike.value = true;
      }
      coinNum.value += coin;
      try {
        final stat = audioItem.value!.stat
          ..hasCoin_8 = true
          ..coin += coin;
        if (updateLike) {
          stat
            ..hasLike_7 = true
            ..like += 1;
        }
        audioItem.refresh();
      } catch (_) {}
      GlobalData().afterCoin(coin);
    } else {
      res.toast();
    }
  }

  @override
  void showFavBottomSheet(BuildContext context, {bool isLongPress = false}) {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    if (enableQuickFav) {
      if (!isLongPress) {
        actionFavVideo(isQuick: true);
      } else {
        PageUtils.showFavBottomSheet(context: context, ctr: this);
      }
    } else if (!isLongPress) {
      PageUtils.showFavBottomSheet(context: context, ctr: this);
    }
  }

  void showReply() {
    MainReplyPage.toMainReplyPage(oid: oid.toInt(), replyType: isUgc ? 1 : 14);
  }

  void actionShareVideo(BuildContext context) {
    final audioUrl = isUgc
        ? '${HttpString.baseUrl}/video/${IdUtils.av2bv(oid.toInt())}'
        : '${HttpString.baseUrl}/audio/au$oid';
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          DialogOption(
            child: const Text('复制链接', style: TextStyle(fontSize: 14)),
            onPressed: () {
              Get.back();
              Utils.copyText(audioUrl);
            },
          ),
          DialogOption(
            child: const Text('其它app打开', style: TextStyle(fontSize: 14)),
            onPressed: () {
              Get.back();
              PageUtils.launchURL(audioUrl);
            },
          ),
          if (PlatformUtils.isMobile)
            DialogOption(
              child: const Text('分享视频', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                if (audioItem.value case DetailItem(:final arc, :final owner)) {
                  ShareUtils.shareText(
                    '${arc.title} '
                    'UP主: ${owner.name}'
                    ' - $audioUrl',
                  );
                }
              },
            ),
          if (isLogin)
            DialogOption(
              child: const Text('分享至动态', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                if (audioItem.value case DetailItem(:final arc, :final owner)) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => RepostPanel(
                      rid: oid.toInt(),
                      dynType: isUgc ? 8 : 256,
                      pic: arc.cover,
                      title: arc.title,
                      uname: owner.name,
                    ),
                  );
                }
              },
            ),
          if (isUgc && isLogin)
            DialogOption(
              child: const Text('分享至消息', style: TextStyle(fontSize: 14)),
              onPressed: () {
                Get.back();
                if (audioItem.value case DetailItem(:final arc, :final owner)) {
                  try {
                    PageUtils.pmShare(
                      context,
                      content: {
                        "id": oid.toString(),
                        "title": arc.title,
                        "headline": arc.title,
                        "source": 5,
                        "thumb": arc.cover,
                        "author": owner.name,
                        "author_id": owner.mid.toString(),
                      },
                    );
                  } catch (e) {
                    SmartDialog.showToast(e.toString());
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void>? playOrPause() {
    if (player case final player?) {
      if (duration.value - position.value < 1) {
        return _restartPlayback();
      }
      return player.state.playing ? onPause() : onPlay();
    }
    return null;
  }

  Future<void> _restartPlayback() async {
    await onSeek(Duration.zero);
    await onPlay();
  }

  bool playPrev() {
    if (index != null && playlist != null && player != null) {
      _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
      final prev = index! - 1;
      if (prev >= 0) {
        playIndex(prev, preferHistoryPart: false);
        return true;
      }
    }
    return false;
  }

  bool playNext({bool nextPart = false}) {
    unawaited(
      DebugLogService.log(
        'audio.switch',
        'play next',
        extra: {
          'oid': oid.toString(),
          'subId': subId.firstOrNull?.toString(),
          'index': index,
          'nextPart': nextPart,
        },
      ),
    );
    if (nextPart) {
      if (audioItem.value case DetailItem(:final parts)) {
        if (parts.length > 1) {
          final subId = this.subId.firstOrNull;
          final nextIndex = parts.indexWhere((e) => e.subId == subId) + 1;
          if (nextIndex != 0 && nextIndex < parts.length) {
            _cancelAutoTailSkipCompleted(clearConsumed: false);
            _playIndexGeneration++;
            _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
            final prevOid = oid;
            final prevSubId = this.subId;
            final prevStart = _start;
            final nextPart = parts[nextIndex];
            oid = nextPart.oid;
            this.subId = [nextPart.subId];
            final progress = _playlistItemProgressSeconds(
              audioItem.value!,
              oid.toInt(),
              nextPart.subId.toInt(),
            );
            _start = progress > 0 ? Duration(seconds: progress) : null;
            _resetHeartBeatProgress();
            _queryPlayUrl().then((res) {
              if (res) {
                final currentItem = audioItem.value;
                if (currentItem != null) {
                  _updateCurrItem(currentItem);
                }
              } else {
                oid = prevOid;
                this.subId = prevSubId;
                _start = prevStart;
                final currentItem = audioItem.value;
                if (currentItem != null) {
                  _updateCurrItem(currentItem);
                }
              }
            });
            return true;
          }
        }
      }
    }
    if (index != null && playlist != null && player != null) {
      final next = index! + 1;
      if (next < playlist!.length) {
        _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
        if (next == playlist!.length - 1 && _next != null) {
          _queryPlayList(isLoadNext: true);
        }
        playIndex(next, preferHistoryPart: false);
        return true;
      }
    }
    return false;
  }

  void playIndex(
    int index, {
    List<Int64>? subId,
    bool preferHistoryPart = true,
  }) {
    if (index == this.index && subId == null) return;
    unawaited(
      DebugLogService.log(
        'audio.switch',
        'play index',
        extra: {
          'fromIndex': this.index,
          'toIndex': index,
          'oid': oid.toString(),
          'requestedSubId': subId?.map((e) => e.toString()).toList(),
          'preferHistoryPart': preferHistoryPart,
        },
      ),
    );
    _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
    final prevIndex = this.index;
    final prevOid = oid;
    final prevSubId = this.subId;
    final prevItemType = itemType;
    final prevStart = _start;
    final audioItem = playlist![index];
    final item = audioItem.item;
    final generation = ++_playIndexGeneration;
    _cancelAutoTailSkipCompleted(clearConsumed: false);
    unawaited(() async {
      final resolvedSubId = await _defaultSubIdsForPlaylistItem(
        audioItem,
        item,
        subId,
        preferHistoryPart: preferHistoryPart,
        isCurrent: () =>
            generation == _playIndexGeneration &&
            this.index == prevIndex &&
            oid == prevOid,
      );
      if (generation != _playIndexGeneration) return;
      this.index = index;
      oid = item.oid;
      this.subId = resolvedSubId;
      itemType = item.itemType;
      final currentCid = resolvedSubId.firstOrNull?.toInt();
      final progress = currentCid == null
          ? 0
          : _playlistItemProgressSeconds(audioItem, oid.toInt(), currentCid);
      _start = progress > 0 ? Duration(seconds: progress) : null;
      _resetHeartBeatProgress();
      final res = await _queryPlayUrl();
      if (generation != _playIndexGeneration) return;
      if (res) {
        _updateCurrItem(audioItem);
      } else {
        this.index = prevIndex;
        oid = prevOid;
        this.subId = prevSubId;
        itemType = prevItemType;
        _start = prevStart;
        final currentItem = this.index == null
            ? this.audioItem.value
            : playlist?.elementAtOrNull(this.index!) ?? this.audioItem.value;
        if (currentItem != null) {
          _updateCurrItem(currentItem);
        }
      }
    }());
  }

  void setSpeed(double speed) {
    if (player case final player?) {
      this.speed = speed;
      player.setRate(speed);
    }
  }

  @override
  (Object, int) get getFavRidType => (oid, isUgc ? 2 : 12);

  @override
  void updateFavCount(int count) {
    try {
      audioItem.value!.stat
        ..hasFav = count > 0
        ..favourite += count;
      audioItem.refresh();
    } catch (_) {}
  }

  Future<void> loadPrev(BuildContext context) async {
    if (_prev == null) return;
    final length = playlist!.length;
    await _queryPlayList(isLoadPrev: true);
    if (length != playlist!.length && context.mounted) {
      (context as Element).markNeedsBuild();
    }
  }

  Future<void> loadNext(BuildContext context) async {
    if (_next == null) return;
    final length = playlist!.length;
    await _queryPlayList(isLoadNext: true);
    if (length != playlist!.length && context.mounted) {
      (context as Element).markNeedsBuild();
    }
  }

  void onChangeOrder(ListOrder value) {
    if (order != value) {
      order = value;
      _queryPlayList(isInit: true);
    }
  }

  @override
  BlockConfigMixin get blockConfig => this;

  @override
  int get currPosInMilliseconds => player?.state.position.inMilliseconds ?? 0;

  @override
  int? get timeLength => player?.state.duration.inMilliseconds ?? 0;

  @override
  Future<void>? seekTo(
    Duration duration, {
    required bool isSeek,
    BlockSkipSource skipSource = BlockSkipSource.manual,
  }) => onSeek(duration, skipSource: skipSource);

  @override
  bool get autoPlay => true;

  @override
  bool get preInitPlayer => true;

  @override
  void onClose() {
    shutdownTimerService
      ..onPause = null
      ..isPlaying = null
      ..reset();
    videoPlayerServiceHandler
      ?..onPlay = null
      ..onPause = null
      ..onSeek = null
      ..onVideoDetailDispose(hashCode.toString());
    _subscriptions?.forEach((e) => e.cancel());
    _subscriptions?.clear();
    _subscriptions = null;
    _cancelAutoTailSkipCompleted();
    _unawaitedHeartBeat(_reportStatusHeartBeat(force: true));
    player?.dispose();
    player = null;
    animController.dispose();
    super.onClose();
  }
}

extension on DashItem {
  Iterable<String> get playUrls sync* {
    yield baseUrl;
    yield* backupUrl;
  }
}

extension on ResponseUrl {
  Iterable<String> get playUrls sync* {
    yield url;
    yield* backupUrl;
  }
}
