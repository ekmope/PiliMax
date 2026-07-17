import 'dart:async' show FutureOr, Timer;

import 'package:PiliMax/http/fav.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models_new/fav/fav_folder/data.dart';
import 'package:PiliMax/models_new/video/video_detail/data.dart';
import 'package:PiliMax/models_new/video/video_detail/stat_detail.dart';
import 'package:PiliMax/models_new/video/video_tag/data.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/widgets/triple_mixin.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/loading_action_mixin.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

enum IntroAction {
  like,
  dislike,
  triple,
  coin,
  favorite,
  watchLater,
  relation,
  pgcFollow,
  pugvFavorite,
}

abstract class CommonIntroController extends GetxController
    with
        GetSingleTickerProviderStateMixin,
        LoadingActionMixin<IntroAction>,
        TripleMixin,
        FavMixin {
  late final String heroTag;
  late String bvid;

  // 是否稍后再看
  final RxBool hasLater = false.obs;

  final Rx<List<VideoTagItem>?> videoTags = Rx<List<VideoTagItem>?>(null);

  bool isProcessing = false;
  Future<void> handleAction(
    FutureOr<void> Function() action, {
    IntroAction? loadingAction,
  }) async {
    if (loadingAction != null) {
      await runWithActionLoading(loadingAction, action);
      return;
    }
    if (isProcessing) {
      return;
    }
    isProcessing = true;
    try {
      await action();
    } finally {
      isProcessing = false;
    }
  }

  @override
  late final isLogin = Accounts.main.isLogin;

  StatDetail? getStat();

  @override
  void updateFavCount(int count) {
    getStat()?.favorite += count;
  }

  final Rx<VideoDetailData> videoDetail = VideoDetailData().obs;

  void queryVideoIntro();

  bool prevPlay({bool manual = false});
  bool nextPlay({bool manual = false});

  void actionShareVideo(BuildContext context);

  // 同时观看
  final bool isShowOnlineTotal = Pref.enableOnlineTotal;
  late final RxString total = '1'.obs;
  Timer? timer;

  late final RxInt cid;
  int _introRequestGeneration = 0;

  int nextIntroRequestGeneration() => ++_introRequestGeneration;

  bool isCurrentIntroRequest(int generation) =>
      !isClosed && generation == _introRequestGeneration;

  late final videoDetailCtr = Get.find<VideoDetailController>(tag: heroTag);

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    heroTag = args['heroTag'];
    bvid = args['bvid'];
    cid = RxInt(args['cid']);
    hasLater.value = args['sourceType'] == SourceType.watchLater;

    queryVideoIntro();
    startTimer();
  }

  void startTimer() {
    if (isShowOnlineTotal) {
      queryOnlineTotal();
      timer ??= Timer.periodic(const Duration(minutes: 1), (Timer timer) {
        queryOnlineTotal();
      });
    }
  }

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  // 查看同时在看人数
  Future<void> queryOnlineTotal({bool Function()? isCurrent}) async {
    if (!isShowOnlineTotal) {
      return;
    }
    if (isCurrent?.call() == false) {
      return;
    }
    final result = await VideoHttp.onlineTotal(
      aid: IdUtils.bv2av(bvid),
      bvid: bvid,
      cid: cid.value,
    );
    if (isCurrent?.call() == false) {
      return;
    }
    if (result case Success(:final response)) {
      total.value = response;
    }
  }

  @override
  void onClose() {
    cancelTimer();
    super.onClose();
  }

  @override
  Future<void> onPayCoin(int coin, bool coinWithLike) async {
    await runWithActionLoading(IntroAction.coin, () async {
      final stat = getStat();
      if (stat == null) {
        return;
      }
      final res = await VideoHttp.coinVideo(
        bvid: bvid,
        multiply: coin,
        selectLike: coinWithLike ? 1 : 0,
      );
      if (res.isSuccess) {
        SmartDialog.showToast('投币成功');
        coinNum.value += coin;
        GlobalData().afterCoin(coin);
        stat.coin += coin;
        if (coinWithLike && !hasLike.value) {
          stat.like++;
          hasLike.value = true;
        }
      } else {
        res.toast();
      }
    });
  }

  Future<void> queryVideoTags({bool Function()? isCurrent}) async {
    if (isCurrent?.call() == false) {
      return;
    }
    final result = await UserHttp.videoTags(bvid: bvid, cid: cid.value);
    if (isCurrent?.call() == false) {
      return;
    }
    videoTags.value = result.dataOrNull;
  }

  Future<void> viewLater() async {
    await runWithActionLoading(IntroAction.watchLater, () async {
      final res = await (hasLater.value
          ? UserHttp.toViewDel(aids: IdUtils.bv2av(bvid).toString())
          : UserHttp.toViewLater(bvid: bvid));
      if (res.isSuccess) hasLater.value = !hasLater.value;
    });
  }
}

mixin FavMixin on TripleMixin {
  Set<int>? favIds;
  final Rx<FavFolderData> favFolderData = FavFolderData().obs;
  BuildContext? _favContext;

  String get _favFeedbackTag => 'favorite-feedback-$hashCode';

  bool isActionLoading(IntroAction action);

  Future<T?> runWithActionLoading<T>(
    IntroAction action,
    FutureOr<T> Function() callback,
  );

  (Object, int) get getFavRidType;

  Future<LoadingState<FavFolderData>> queryVideoInFolder() async {
    final (rid, type) = getFavRidType;
    final res = await FavHttp.videoInFolder(
      mid: Accounts.main.mid,
      rid: rid,
      type: type,
    );
    if (res case Success(:final response)) {
      favFolderData.value = response;
      favIds =
          response.list
              ?.where((item) => item.favState == 1)
              .map((item) => item.id)
              .toSet() ??
          <int>{};
    }
    return res;
  }

  BuildContext? get _activeFavContext {
    final context = _favContext;
    if (context != null && context.mounted) {
      return context;
    }
    final getContext = Get.context;
    return getContext != null && getContext.mounted ? getContext : null;
  }

  // 收藏
  void showFavBottomSheet(BuildContext context, {bool isLongPress = false}) {
    _favContext = context;
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    if (isActionLoading(IntroAction.favorite)) {
      return;
    }
    if (isLongPress) {
      PageUtils.showFavBottomSheet(context: context, ctr: this);
    } else {
      actionFavVideo(isQuick: true);
    }
  }

  void updateFavCount(int count);

  void _applyFavMembership(Set<int> oldIds, Set<int> newIds) {
    final wasFav = oldIds.isNotEmpty;
    final isFav = newIds.isNotEmpty;
    hasFav.value = isFav;
    updateFavCount((isFav ? 1 : 0) - (wasFav ? 1 : 0));
  }

  Future<void> _showFavFeedback({
    required String message,
    required Alignment alignment,
    required Duration duration,
    bool showModify = false,
  }) async {
    final tag = _favFeedbackTag;
    await SmartDialog.dismiss(tag: tag);
    if (isClosed) {
      return;
    }
    SmartDialog.show(
      tag: tag,
      keepSingle: true,
      clickMaskDismiss: false,
      usePenetrate: true,
      maskColor: Colors.transparent,
      alignment: alignment,
      animationType: SmartAnimationType.fade,
      displayTime: duration,
      bindPage: true,
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        final content = Material(
          elevation: 6,
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: showModify
                ? const EdgeInsets.fromLTRB(16, 6, 6, 6)
                : const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: showModify
                ? Row(
                    children: [
                      Expanded(child: Text(message)),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await SmartDialog.dismiss(tag: tag);
                          final originContext = _activeFavContext;
                          if (originContext != null && originContext.mounted) {
                            PageUtils.showFavBottomSheet(
                              context: originContext,
                              ctr: this,
                            );
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                        ),
                        child: const Text('修改收藏夹'),
                      ),
                    ],
                  )
                : Text(message),
          ),
        );
        if (!showModify) {
          return content;
        }
        final width = (MediaQuery.sizeOf(context).width - 32)
            .clamp(0, 520)
            .toDouble();
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
          ),
          child: SizedBox(width: width, child: content),
        );
      },
    );
  }

  Future<void> actionFavVideo({bool isQuick = false}) async {
    if (!Accounts.main.isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }
    await runWithActionLoading(IntroAction.favorite, () async {
      final (rid, type) = getFavRidType;
      // 点按只切换接口返回列表中的第一个（默认）收藏夹。
      if (isQuick) {
        final res = await queryVideoInFolder();
        if (!res.isSuccess) {
          res.toast();
          return;
        }
        final folders = favFolderData.value.list;
        if (folders == null || folders.isEmpty) {
          SmartDialog.showToast('未找到默认收藏夹');
          return;
        }
        final defaultFolder = folders.first;
        final oldIds = Set<int>.of(favIds ?? const <int>{});
        final wasInDefault = oldIds.contains(defaultFolder.id);
        final result = await FavHttp.favVideo(
          resources: '$rid:$type',
          addIds: wasInDefault ? null : defaultFolder.id.toString(),
          delIds: wasInDefault ? defaultFolder.id.toString() : null,
        );
        if (!result.isSuccess) {
          result.toast();
          return;
        }

        final newIds = Set<int>.of(oldIds);
        if (wasInDefault) {
          newIds.remove(defaultFolder.id);
          defaultFolder.favState = 0;
          if (defaultFolder.mediaCount > 0) {
            defaultFolder.mediaCount--;
          }
        } else {
          newIds.add(defaultFolder.id);
          defaultFolder
            ..favState = 1
            ..mediaCount = defaultFolder.mediaCount + 1;
        }
        favIds = newIds;
        favFolderData.refresh();
        _applyFavMembership(oldIds, newIds);

        if (wasInDefault) {
          await _showFavFeedback(
            message: newIds.isEmpty ? '已取消收藏' : '已移出默认收藏夹',
            alignment: Alignment.center,
            duration: const Duration(milliseconds: 1200),
          );
        } else {
          await _showFavFeedback(
            message: '已加入「默认收藏夹」',
            alignment: Alignment.bottomCenter,
            duration: const Duration(seconds: 4),
            showModify: true,
          );
        }
        return;
      }

      final folders = favFolderData.value.list;
      if (folders == null) {
        SmartDialog.showToast('收藏夹数据异常');
        return;
      }
      final oldIds = Set<int>.of(favIds ?? const <int>{});
      final newIds = folders
          .where((item) => item.favState == 1)
          .map((item) => item.id)
          .toSet();
      final addMediaIdsNew = newIds.difference(oldIds);
      final delMediaIdsNew = oldIds.difference(newIds);
      SmartDialog.showLoading(msg: '请求中');
      late final LoadingState<void> result;
      try {
        result = await FavHttp.favVideo(
          resources: '$rid:$type',
          addIds: addMediaIdsNew.join(','),
          delIds: delMediaIdsNew.join(','),
        );
      } finally {
        await SmartDialog.dismiss(status: SmartStatus.loading);
      }
      if (result.isSuccess) {
        Get.back();
        favIds = newIds;
        favFolderData.refresh();
        _applyFavMembership(oldIds, newIds);
        SmartDialog.showToast('${newIds.isNotEmpty ? '' : '取消'}收藏成功');
      } else {
        result.toast();
      }
    });
  }
}
