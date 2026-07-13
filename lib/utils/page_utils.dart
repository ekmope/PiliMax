import 'dart:math';

import 'package:PiliMax/common/widgets/fractionally_sized_box.dart';
import 'package:PiliMax/common/widgets/image_viewer/gallery_viewer.dart';
import 'package:PiliMax/common/widgets/image_viewer/hero_dialog_route.dart';
import 'package:PiliMax/common/widgets/video_card/video_transition_registry.dart';
import 'package:PiliMax/grpc/im.dart';
import 'package:PiliMax/http/dynamics.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/common/image_preview_type.dart';
import 'package:PiliMax/models/common/video/source_type.dart' as video_source;
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/models_new/pgc/pgc_info_model/episode.dart';
import 'package:PiliMax/models_new/video/video_detail/dimension.dart';
import 'package:PiliMax/pages/common/common_intro_controller.dart';
import 'package:PiliMax/pages/common/publish/publish_route.dart';
import 'package:PiliMax/pages/contact/view.dart';
import 'package:PiliMax/pages/fav_panel/view.dart';
import 'package:PiliMax/pages/share/view.dart';
import 'package:PiliMax/pages/video/video_detail_page_route.dart';
import 'package:PiliMax/pages/video/video_detail_session.dart';
import 'package:PiliMax/pages/video/video_detail_entry_overlay.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/services/live_pip_overlay_service.dart';
import 'package:PiliMax/services/pip_overlay_service.dart';
import 'package:PiliMax/utils/android/android_helper.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/extension/context_ext.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/url_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

enum VideoPendingLaunchType { ugc, pgc, pugv }

final class VideoLaunchException implements Exception {
  const VideoLaunchException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class PageUtils {
  static const videoPendingLaunchKey = '_videoPendingLaunch';
  static const _videoPendingPartKey = '_videoPendingPart';
  static bool _videoRouteLaunchPending = false;
  static bool _videoRouteNavigationInstalling = false;
  static int _videoRouteLaunchGeneration = 0;

  static bool get isOpeningVideoRoute =>
      _videoRouteLaunchPending ||
      _videoRouteNavigationInstalling ||
      VideoDetailEntryOverlayController.isEnteringVideo;

  static RelativeRect menuPosition(Offset offset) {
    return .fromLTRB(offset.dx, offset.dy, offset.dx, 0);
  }

  static Future<void> imageView({
    int initialPage = 0,
    required List<SourceModel> imgList,
    int? quality,
    ValueChanged<int>? onPageChanged,
    String tag = '',
  }) {
    return Get.key.currentState!.push<void>(
      HeroDialogRoute(
        pageBuilder: (context, animation, secondaryAnimation) => GalleryViewer(
          sources: imgList,
          initIndex: initialPage,
          quality: quality ?? GlobalData().imgQuality,
          onPageChanged: onPageChanged,
          tag: tag,
        ),
      ),
    );
  }

  static Future<void> pmShare(
    BuildContext context, {
    required Map content,
  }) async {
    // if (kDebugMode) debugPrint(content.toString());

    List<UserModel> userList = <UserModel>[];

    final res = await ImGrpc.shareList(size: 5);
    if (res case Success(:final response)) {
      if (response.sessionList.isNotEmpty) {
        userList.addAll(
          response.sessionList.map<UserModel>(
            (item) => UserModel(
              mid: item.talkerId.toInt(),
              name: item.talkerUname,
              avatar: item.talkerIcon,
            ),
          ),
        );
      }
    }

    if (userList.isEmpty && context.mounted) {
      final UserModel? userModel = await Navigator.of(context).push(
        GetPageRoute(page: () => const ContactPage()),
      );
      if (userModel != null) {
        userList.add(userModel);
      }
    }

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        builder: (context) => SharePanel(
          content: content,
          userList: userList,
        ),
        useSafeArea: true,
        enableDrag: false,
        isScrollControlled: true,
      );
    }
  }

  static Future<void> pushDynFromId({
    String? id,
    Object? rid,
    bool off = false,
    Object? type,
  }) async {
    assert(id != null || rid != null);
    SmartDialog.showLoading();
    final res = await DynamicsHttp.dynamicDetail(
      id: id,
      rid: rid,
      type: rid != null ? 2 : null,
    );
    SmartDialog.dismiss();
    if (res case Success(:final response)) {
      if (response.basic?.commentType == 12) {
        toDupNamed(
          '/articlePage',
          parameters: {
            'id': id!,
            'type': 'opus',
          },
          off: off,
        );
      } else {
        toDupNamed(
          '/dynamicDetail',
          arguments: {
            'item': response,
          },
          off: off,
        );
      }
    } else {
      SmartDialog.showToast('${type != null ? 'type: $type ' : ''}$res');
    }
  }

  static void showFavBottomSheet({
    required BuildContext context,
    required FavMixin ctr,
  }) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, context.mediaQueryShortestSide),
      ),
      builder: (BuildContext context) {
        final maxChildSize =
            PlatformUtils.isMobile && !context.mediaQuerySize.isPortrait
            ? 1.0
            : 0.7;
        return DraggableScrollableSheet(
          minChildSize: 0,
          maxChildSize: 1,
          snap: true,
          expand: false,
          snapSizes: [maxChildSize],
          initialChildSize: maxChildSize,
          builder: (BuildContext context, ScrollController scrollController) {
            return FavPanel(
              ctr: ctr,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  static void reportVideo(int aid) {
    Get.toNamed(
      '/webview',
      parameters: {'url': 'https://www.bilibili.com/appeal/?avid=$aid'},
    );
  }

  static bool _fitsInAndroidRequirements(int width, int height) {
    final aspectRatio = width / height;
    const min = 1 / 2.39;
    const max = 2.39;
    return (min <= aspectRatio) && (aspectRatio <= max);
  }

  static void enterPip({
    int? width,
    int? height,
    bool autoEnter = false,
    required bool isLive,
    required bool isPlaying,
  }) {
    if (width != null &&
        height != null &&
        !_fitsInAndroidRequirements(width, height)) {
      if (height > width) {
        width = 9;
        height = 16;
      } else {
        width = 16;
        height = 9;
      }
    }
    PiliAndroidHelper.enterPip(
      width ?? 16,
      height ?? 9,
      autoEnter: autoEnter,
      isLive: isLive,
      isPlaying: isPlaying,
    );
  }

  static Future<void> pushDynDetail(
    DynamicItemModel item, {
    bool isPush = false,
    ValueChanged<DynamicItemModel>? onUpdate,
    bool viewComment = false,
    String? heroTag,
  }) async {
    feedBack();

    void push() {
      if (item.basic?.commentType == 12) {
        toDupNamed(
          '/articlePage',
          parameters: {
            'id': item.idStr,
            'type': 'opus',
          },
        );
      } else {
        toDupNamed(
          '/dynamicDetail',
          arguments: {
            'item': item,
            if (onUpdate != null) 'onUpdate': onUpdate,
            if (viewComment) 'viewComment': true,
          },
        );
      }
    }

    /// 点击评论action 直接查看评论
    if (isPush) {
      push();
      return;
    }

    // if (kDebugMode) debugPrint('pushDynDetail: ${item.type}');

    switch (item.type) {
      case 'DYNAMIC_TYPE_AV':
        final archive = item.modules.moduleDynamic!.major!.archive!;
        // pgc
        if (archive.type == 2) {
          if (heroTag != null &&
              (archive.epid != null || archive.seasonId != null)) {
            viewPgc(
              seasonId: archive.seasonId,
              epId: archive.epid,
              heroTag: heroTag,
              cover: archive.cover,
              title: archive.title,
            );
            return;
          }
          // jumpUrl
          if (archive.jumpUrl case final jumpUrl?) {
            if (viewPgcFromUri(
              jumpUrl,
              heroTag: heroTag,
              cover: archive.cover,
              title: archive.title,
            )) {
              return;
            }
          }
          // redirectUrl from intro
          final res = await VideoHttp.videoIntro(bvid: archive.bvid!);
          if (res.dataOrNull?.redirectUrl case final redirectUrl?) {
            if (viewPgcFromUri(
              redirectUrl,
              heroTag: heroTag,
              cover: archive.cover,
              title: archive.title,
            )) {
              return;
            }
          }
          // redirectUrl from jumpUrl
          if (await UrlUtils.parseRedirectUrl(archive.jumpUrl.http2https, false)
              case final redirectUrl?) {
            if (viewPgcFromUri(
              redirectUrl,
              heroTag: heroTag,
              cover: archive.cover,
              title: archive.title,
            )) {
              return;
            }
          }
        }

        if (heroTag != null && (archive.bvid != null || archive.aid != null)) {
          toVideoPage(
            aid: archive.aid,
            bvid: archive.bvid,
            cid: null,
            cover: archive.cover,
            title: archive.title,
            heroTag: heroTag,
          );
          return;
        }

        try {
          String bvid = archive.bvid!;
          String cover = archive.cover!;
          final res = await SearchHttp.ab2cWithDimension(bvid: bvid);
          final cid = res?.cid;
          if (cid != null) {
            toVideoPage(
              bvid: bvid,
              cid: cid,
              cover: cover,
              dimension: res!.dimension,
              heroTag: heroTag,
            );
          }
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;

      /// 涓撴爮鏂囩珷鏌ョ湅
      case 'DYNAMIC_TYPE_ARTICLE':
        toDupNamed(
          '/articlePage',
          parameters: {
            'id': item.idStr,
            'type': 'opus',
          },
        );
        break;

      case 'DYNAMIC_TYPE_PGC':
        final pgc = item.modules.moduleDynamic?.major?.pgc;
        if (pgc == null) {
          SmartDialog.showToast('暂未支持的类型，请联系开发者');
          break;
        }
        if (pgc.epid != null || pgc.seasonId != null) {
          viewPgc(
            seasonId: pgc.seasonId,
            epId: pgc.epid,
            heroTag: heroTag,
            cover: pgc.cover,
            title: pgc.title,
          );
        } else if (pgc.jumpUrl case final jumpUrl?) {
          if (!viewPgcFromUri(
            jumpUrl,
            heroTag: heroTag,
            cover: pgc.cover,
            title: pgc.title,
          )) {
            handleWebview(jumpUrl.http2https);
          }
        } else {
          SmartDialog.showToast('暂未支持的类型，请联系开发者');
        }
        break;

      case 'DYNAMIC_TYPE_LIVE':
        DynamicLive2Model liveRcmd = item.modules.moduleDynamic!.major!.live!;
        toLiveRoom(liveRcmd.id);
        break;

      case 'DYNAMIC_TYPE_LIVE_RCMD':
        DynamicLiveModel liveRcmd =
            item.modules.moduleDynamic!.major!.liveRcmd!;
        toLiveRoom(liveRcmd.roomId);
        break;

      case 'DYNAMIC_TYPE_SUBSCRIPTION_NEW':
        LivePlayInfo live = item
            .modules
            .moduleDynamic!
            .major!
            .subscriptionNew!
            .liveRcmd!
            .content!
            .livePlayInfo!;
        toLiveRoom(live.roomId);
        break;

      /// 鍚堥泦鏌ョ湅
      case 'DYNAMIC_TYPE_UGC_SEASON':
        DynamicArchiveModel ugcSeason =
            item.modules.moduleDynamic!.major!.ugcSeason!;
        int aid = ugcSeason.aid!;
        String bvid = IdUtils.av2bv(aid);
        String cover = ugcSeason.cover!;
        if (heroTag != null) {
          toVideoPage(
            aid: aid,
            bvid: bvid,
            cid: null,
            cover: cover,
            title: ugcSeason.title,
            heroTag: heroTag,
          );
          return;
        }
        final res = await SearchHttp.ab2cWithDimension(bvid: bvid);
        final cid = res?.cid;
        if (cid != null) {
          toVideoPage(
            aid: aid,
            bvid: bvid,
            cid: cid,
            cover: cover,
            dimension: res!.dimension,
            heroTag: heroTag,
          );
        }
        break;

      /// 鐣墽鏌ョ湅
      case 'DYNAMIC_TYPE_PGC_UNION':
        // if (kDebugMode) debugPrint('DYNAMIC_TYPE_PGC_UNION 鐣墽');
        DynamicArchiveModel pgc = item.modules.moduleDynamic!.major!.pgc!;
        if (pgc.epid != null) {
          viewPgc(
            epId: pgc.epid,
            heroTag: heroTag,
            cover: pgc.cover,
            title: pgc.title,
          );
        }
        break;

      case 'DYNAMIC_TYPE_MEDIALIST':
        if (item.modules.moduleDynamic?.major?.medialist
            case final medialist?) {
          final String? url = medialist.jumpUrl;
          if (url != null) {
            if (url.contains('medialist/detail/ml')) {
              Get.toNamed(
                '/favDetail',
                parameters: {
                  'heroTag': '${medialist.cover}',
                  'mediaId': '${medialist.id}',
                },
              );
            } else {
              handleWebview(url.http2https);
            }
          }
        }
        break;

      case 'DYNAMIC_TYPE_COURSES_SEASON':
        final courses = item.modules.moduleDynamic!.major!.courses!;
        PageUtils.viewPugv(
          seasonId: courses.id,
          heroTag: heroTag,
          cover: courses.cover,
          title: courses.title,
        );
        break;

      // 绾枃瀛楀姩鎬佹煡鐪?
      // case 'DYNAMIC_TYPE_WORD':
      // # 瑁呮壆/鍓ч泦鐐硅瘎/鏅€氬垎浜?
      // case 'DYNAMIC_TYPE_COMMON_SQUARE':
      // 杞彂鐨勫姩鎬?
      // case 'DYNAMIC_TYPE_FORWARD':
      // 鍥炬枃鍔ㄦ€佹煡鐪?
      // case 'DYNAMIC_TYPE_DRAW':
      default:
        push();
        break;
    }
  }

  static void onHorizontalPreviewState(
    ScaffoldState state,
    List<SourceModel> imgList,
    int index,
  ) {
    state.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => GalleryViewer(
        sources: imgList,
        initIndex: index,
        quality: GlobalData().imgQuality,
      ),
      enableDrag: false,
      elevation: 0.0,
      backgroundColor: Colors.transparent,
      sheetAnimationStyle: AnimationStyle.noAnimation,
    );
  }

  static void inAppWebview(
    String url, {
    bool off = false,
  }) {
    if (Pref.openInBrowser) {
      launchURL(url);
    } else {
      if (off) {
        Get.offNamed(
          '/webview',
          parameters: {'url': url},
          arguments: {'inApp': true},
        );
      } else {
        Get.toNamed(
          '/webview',
          parameters: {'url': url},
          arguments: {'inApp': true},
        );
      }
    }
  }

  static Future<void> launchURL(
    String url, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: mode)) {
        SmartDialog.showToast('Could not launch $url');
      }
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  static Future<void> handleWebview(
    String url, {
    bool off = false,
    bool inApp = false,
    Map? parameters,
  }) async {
    if (!inApp && Pref.openInBrowser) {
      if (!await PiliScheme.routePushFromUrl(url, selfHandle: true)) {
        launchURL(url);
      }
    } else {
      if (off) {
        Get.offNamed(
          '/webview',
          parameters: {
            'url': url,
            ...?parameters,
          },
        );
      } else {
        PiliScheme.routePushFromUrl(url, parameters: parameters);
      }
    }
  }

  static Future<void>? showVideoBottomSheet(
    BuildContext context, {
    required Widget child,
    ValueGetter<EdgeInsets>? padding,
    double maxWidth = 500,
  }) {
    if (!context.mounted) {
      return null;
    }
    return Get.key.currentState!.push(
      PublishRoute(
        pageBuilder: (context, animation, secondaryAnimation) {
          final isPortrait = context.isPortrait;
          return SafeArea(
            child: CustomFractionallySizedBox(
              maxWidth: maxWidth,
              widthFactor: isPortrait ? 1.0 : 0.5,
              heightFactor: isPortrait ? 0.7 : 1.0,
              alignment: isPortrait ? .bottomCenter : .centerRight,
              child: Padding(
                padding: isPortrait ? padding?.call() ?? .zero : .zero,
                child: child,
              ),
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final begin = context.isPortrait
              ? const Offset(0.0, 1.0)
              : const Offset(1.0, 0.0);
          return SlideTransition(
            position: animation.drive(
              Tween<Offset>(
                begin: begin,
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeInOut)),
            ),
            child: child,
          );
        },
        settings: RouteSettings(arguments: Get.arguments),
      ),
    );
  }

  static void toLiveRoom(
    int? roomId, {
    bool off = false,
  }) {
    if (roomId == null) {
      return;
    }
    if (off) {
      Get.offNamed('/liveRoom', arguments: roomId);
    } else {
      PageUtils.toDupNamed('/liveRoom', arguments: roomId);
    }
  }

  static Future<void>? toVideoPage({
    VideoType videoType = VideoType.ugc,
    int? aid,
    String? bvid,
    required int? cid,
    int? seasonId,
    int? epId,
    int? pgcType,
    String? cover,
    String? title,
    int? progress, // milliseconds
    Map? extraArguments,
    bool off = false,
    bool? isVertical,
    Dimension? dimension,
    String? heroTag,
    int? part,
    VideoPendingLaunchType? pendingLaunchType,
  }) {
    final hasValidDimension = _hasValidDimension(dimension);
    final effectivePendingType =
        pendingLaunchType ??
        (cid == null
            ? switch (videoType) {
                VideoType.ugc => VideoPendingLaunchType.ugc,
                VideoType.pgc => VideoPendingLaunchType.pgc,
                VideoType.pugv => VideoPendingLaunchType.pugv,
              }
            : null);
    final arguments = _buildVideoPageArguments(
      videoType: videoType,
      aid: aid,
      bvid: bvid,
      cid: cid,
      seasonId: seasonId,
      epId: epId,
      pgcType: pgcType,
      cover: cover,
      title: title,
      progress: progress,
      extraArguments: extraArguments,
      isVertical: hasValidDimension
          ? dimension!.isVertical
          : isVertical ?? false,
      videoOrientationKnown: hasValidDimension || isVertical != null,
      heroTag: heroTag,
      part: part,
      pendingLaunchType: effectivePendingType,
    );
    return _openVideoPage(arguments, off: off);
  }

  static Map<dynamic, dynamic> _buildVideoPageArguments({
    required VideoType videoType,
    required int? aid,
    required String? bvid,
    required int? cid,
    int? seasonId,
    int? epId,
    int? pgcType,
    String? cover,
    String? title,
    int? progress,
    Map? extraArguments,
    bool isVertical = false,
    bool videoOrientationKnown = false,
    String? heroTag,
    int? part,
    VideoPendingLaunchType? pendingLaunchType,
  }) {
    final resolveIdentityNow = pendingLaunchType == null;
    final resolvedAid =
        aid ??
        (resolveIdentityNow && bvid != null ? IdUtils.bv2av(bvid) : null);
    final resolvedBvid =
        bvid ?? (resolveIdentityNow && aid != null ? IdUtils.av2bv(aid) : null);
    final fallbackHeroKey =
        cid ??
        resolvedBvid ??
        resolvedAid ??
        '${pendingLaunchType?.name}-$seasonId-$epId';
    return <dynamic, dynamic>{
      'aid': resolvedAid,
      'bvid': resolvedBvid,
      'cid': cid,
      'seasonId': ?seasonId,
      'epId': ?epId,
      'pgcType': ?pgcType,
      'cover': ?cover,
      'title': ?title,
      'progress': ?progress,
      'videoType': videoType,
      'isVertical': isVertical,
      'videoOrientationKnown': videoOrientationKnown,
      'heroTag': heroTag ?? Utils.makeHeroTag(fallbackHeroKey),
      ...?extraArguments,
      videoPendingLaunchKey: ?pendingLaunchType,
      _videoPendingPartKey: ?part,
    };
  }

  static Future<void> _openVideoPage(
    Map<dynamic, dynamic> arguments, {
    required bool off,
  }) async {
    if (!off &&
        (_videoRouteLaunchPending ||
            VideoDetailEntryOverlayController.isEnteringVideo)) {
      return;
    }
    final launchGeneration = ++_videoRouteLaunchGeneration;
    VideoDetailEntryOverlayController? entryOverlay;
    Future<void>? navigation;
    final rootOverlay = Get.key.currentState?.overlay;
    final rootOverlaySize = rootOverlay?.mounted == true
        ? MediaQuery.maybeSizeOf(rootOverlay!.context) ?? Size.zero
        : Size.zero;
    final ownsPendingGate = !off;
    if (ownsPendingGate) {
      _videoRouteLaunchPending = true;
    }
    try {
      if (!off && arguments[videoTransitionTokenKey] == null) {
        final heroTag = arguments['heroTag'];
        if (heroTag is String && heroTag.isNotEmpty) {
          final token = VideoTransitionRegistry.claim(
            tag: heroTag,
            contentKey: VideoDetailSession.contentKeyFor(arguments),
            coverUrl: arguments['cover'] is String
                ? arguments['cover'] as String
                : null,
          );
          if (token != null) {
            arguments[videoTransitionTokenKey] = token;
          }
        }
      }
      if (!off && arguments[videoTransitionTokenKey] is VideoTransitionToken) {
        // Preserve the card's release/ripple frame before covering the source.
        await WidgetsBinding.instance.endOfFrame;
        if (launchGeneration != _videoRouteLaunchGeneration) {
          (arguments.remove(videoTransitionTokenKey) as VideoTransitionToken?)
              ?.dispose();
          return;
        }
        final overlayIsMounted = rootOverlay?.mounted == true;
        final canUseEntryOverlay =
            overlayIsMounted &&
            rootOverlaySize.height >= rootOverlaySize.width &&
            arguments['fromPip'] != true &&
            !PipOverlayService.isInPipMode &&
            !LivePipOverlayService.isInPipMode;
        if (canUseEntryOverlay) {
          final variant =
              arguments['sourceType'] == video_source.SourceType.file
              ? VideoDetailSkeletonVariant.local
              : switch (arguments['videoType']) {
                  VideoType.pgc => VideoDetailSkeletonVariant.pgc,
                  VideoType.pugv => VideoDetailSkeletonVariant.pugv,
                  _ => VideoDetailSkeletonVariant.ugc,
                };
          final rawIsVertical = arguments['isVertical'];
          final rawTitle = arguments['title'];
          entryOverlay = VideoDetailEntryOverlayController(
            overlay: rootOverlay!,
            transitionToken:
                arguments[videoTransitionTokenKey] as VideoTransitionToken,
            isVertical:
                arguments['videoOrientationKnown'] == true &&
                    rawIsVertical is bool
                ? rawIsVertical
                : null,
            variant: variant,
            title: rawTitle is String ? rawTitle : null,
            expandedIntro: Pref.alwaysExpandIntroPanel,
            showRecommendations:
                Pref.showRelatedVideo && !Pref.alwaysExpandIntroPanel,
          )..insert();
          arguments[videoDetailEntryOverlayKey] = entryOverlay;
        } else {
          (arguments.remove(videoTransitionTokenKey) as VideoTransitionToken?)
              ?.dispose();
        }
      }
      _videoRouteNavigationInstalling = true;
      final useAdvancedRoute =
          !off && arguments[videoTransitionTokenKey] is VideoTransitionToken;
      final videoPage = useAdvancedRoute
          ? Get.routeTree.matchRoute('/videoV').route
          : null;
      navigation = videoPage == null
          ? off
                ? Get.offNamed<void>(
                    '/videoV',
                    arguments: arguments,
                    preventDuplicates: false,
                  )
                : Get.toNamed<void>(
                    '/videoV',
                    arguments: arguments,
                    preventDuplicates: false,
                  )
          : Get.key.currentState?.push<void>(
              VideoDetailPageRoute<void>(
                definition: videoPage,
                arguments: arguments,
              ),
            );
      if (navigation == null) {
        entryOverlay?.abort();
        arguments.remove(videoDetailEntryOverlayKey);
        (arguments.remove(videoTransitionTokenKey) as VideoTransitionToken?)
            ?.dispose();
        return;
      }
      // Navigator has installed the route synchronously, but no frame has
      // painted yet. Lift the skeleton above it; Hero installs above both.
      entryOverlay?.bringToFront();
    } catch (_) {
      entryOverlay?.abort();
      arguments.remove(videoDetailEntryOverlayKey);
      (arguments.remove(videoTransitionTokenKey) as VideoTransitionToken?)
          ?.dispose();
      rethrow;
    } finally {
      if (ownsPendingGate) {
        _videoRouteLaunchPending = false;
      }
      _videoRouteNavigationInstalling = false;
    }
    try {
      await navigation;
    } catch (_) {
      entryOverlay?.abort();
      (arguments[videoTransitionTokenKey] as VideoTransitionToken?)?.dispose();
      rethrow;
    }
  }

  static Future<void> resolvePendingVideoLaunch(
    Map<dynamic, dynamic> arguments,
  ) async {
    final pendingType = arguments[videoPendingLaunchKey];
    if (pendingType is! VideoPendingLaunchType) {
      return;
    }

    final resolved = Map<dynamic, dynamic>.from(arguments);
    switch (pendingType) {
      case VideoPendingLaunchType.ugc:
        await _resolvePendingUgc(resolved);
        break;
      case VideoPendingLaunchType.pgc:
        await _resolvePendingPgc(resolved);
        break;
      case VideoPendingLaunchType.pugv:
        await _resolvePendingPugv(resolved);
        break;
    }
    resolved
      ..remove(videoPendingLaunchKey)
      ..remove(_videoPendingPartKey);
    arguments
      ..clear()
      ..addAll(resolved);
  }

  static Future<void> _resolvePendingUgc(Map<dynamic, dynamic> args) async {
    final aid = args['aid'];
    final bvid = args['bvid'];
    if (aid == null && bvid == null) {
      throw const VideoLaunchException('缺少视频标识');
    }
    final result = await SearchHttp.ab2cWithDimension(
      aid: aid,
      bvid: bvid,
      part: args[_videoPendingPartKey] as int?,
    );
    final cid = result?.cid;
    if (cid == null) {
      throw const VideoLaunchException('视频资源加载失败');
    }
    _setVideoIdentity(args, aid: aid as int?, bvid: bvid as String?);
    args['cid'] = cid;
    args['videoType'] = VideoType.ugc;
    final hasValidDimension = _hasValidDimension(result?.dimension);
    args['isVertical'] = hasValidDimension
        ? result!.dimension!.isVertical
        : args['isVertical'] ?? false;
    args['videoOrientationKnown'] =
        hasValidDimension || args['videoOrientationKnown'] == true;
  }

  static Future<void> _resolvePendingPgc(Map<dynamic, dynamic> args) async {
    final result = await SearchHttp.pgcInfo(
      seasonId: args['seasonId'],
      epId: args['epId'],
    );
    final response = result.dataOrNull;
    if (response == null) {
      throw VideoLaunchException(_loadingError(result));
    }

    final episodes = response.episodes;
    final hasEpisode = episodes != null && episodes.isNotEmpty;
    final requestedEpId = args['epId']?.toString();
    EpisodeItem? episode;
    var viewAsSection = false;

    if (requestedEpId != null) {
      if (hasEpisode) {
        episode = episodes.firstWhereOrNull(
          (item) => item.epId.toString() == requestedEpId,
        );
      }
      if (episode == null) {
        for (final section in response.section ?? const []) {
          for (final sectionEpisode in section.episodes ?? const []) {
            if (sectionEpisode.epId.toString() == requestedEpId) {
              episode = sectionEpisode;
              viewAsSection = true;
              break;
            }
          }
          if (episode != null) {
            break;
          }
        }
      }
    }

    if (episode == null && hasEpisode) {
      episode = findEpisode(
        episodes,
        epId: response.userStatus?.progress?.lastEpId,
      );
    } else if (episode == null) {
      episode = response.section?.firstOrNull?.episodes?.firstOrNull;
      viewAsSection = episode != null;
    }
    if (episode == null) {
      throw const VideoLaunchException('视频资源加载失败');
    }

    _applyEpisode(
      args,
      episode: episode,
      videoType: viewAsSection ? VideoType.ugc : VideoType.pgc,
      seasonId: response.seasonId,
      epId: episode.epId,
    );
    args['pgcItem'] = response;
    if (viewAsSection) {
      args
        ..['pgcApi'] = true
        ..remove('pgcType');
    } else {
      args
        ..['pgcType'] = response.type
        ..remove('pgcApi');
    }
  }

  static Future<void> _resolvePendingPugv(Map<dynamic, dynamic> args) async {
    final result = await SearchHttp.pugvInfo(
      seasonId: args['seasonId'],
      epId: args['epId'],
    );
    final response = result.dataOrNull;
    if (response == null) {
      throw VideoLaunchException(_loadingError(result));
    }
    final episodes = response.episodes;
    if (episodes == null || episodes.isEmpty) {
      throw const VideoLaunchException('视频资源加载失败');
    }

    EpisodeItem? episode;
    final aid = args['aid'];
    if (aid != null) {
      episode = episodes.firstWhereOrNull((item) => item.aid == aid);
    }
    episode ??= findEpisode(
      episodes,
      epId: args['epId'] ?? response.userStatus?.progress?.lastEpId,
      isPgc: false,
    );
    _applyEpisode(
      args,
      episode: episode,
      videoType: VideoType.pugv,
      seasonId: response.seasonId,
      epId: episode.id,
    );
    args
      ..['pgcItem'] = response
      ..remove('pgcApi')
      ..remove('pgcType');
  }

  static void _applyEpisode(
    Map<dynamic, dynamic> args, {
    required EpisodeItem episode,
    required VideoType videoType,
    required int? seasonId,
    required int? epId,
  }) {
    final cid = episode.cid;
    if (cid == null) {
      throw const VideoLaunchException('视频资源缺少 cid');
    }
    _setVideoIdentity(args, aid: episode.aid, bvid: episode.bvid);
    args
      ..['cid'] = cid
      ..['videoType'] = videoType
      ..['seasonId'] = seasonId
      ..['epId'] = epId;
    if (episode.cover != null) {
      args['cover'] = episode.cover;
    }
    if (episode.dimension case final dimension?
        when _hasValidDimension(dimension)) {
      args
        ..['isVertical'] = dimension.isVertical
        ..['videoOrientationKnown'] = true;
    }
  }

  static bool _hasValidDimension(Dimension? dimension) =>
      dimension?.width != null &&
      dimension!.width! > 0 &&
      dimension.height != null &&
      dimension.height! > 0;

  static void _setVideoIdentity(
    Map<dynamic, dynamic> args, {
    required int? aid,
    required String? bvid,
  }) {
    final resolvedAid = aid ?? (bvid == null ? null : IdUtils.bv2av(bvid));
    final resolvedBvid = bvid ?? (aid == null ? null : IdUtils.av2bv(aid));
    if (resolvedAid == null || resolvedBvid == null) {
      throw const VideoLaunchException('视频资源缺少 aid 或 bvid');
    }
    args
      ..['aid'] = resolvedAid
      ..['bvid'] = resolvedBvid;
  }

  static String _loadingError(LoadingState result) {
    final message = result.toString().trim();
    return message.isEmpty ? '视频资源加载失败' : message;
  }

  static Future<void> _resolveAndOpenVideoPage(
    Map<dynamic, dynamic> arguments, {
    required bool off,
  }) async {
    try {
      SmartDialog.showLoading(msg: '资源获取中');
      await resolvePendingVideoLaunch(arguments);
      SmartDialog.dismiss();
      _openVideoPage(arguments, off: off);
    } catch (error) {
      SmartDialog.dismiss();
      SmartDialog.showToast(error.toString());
      if (kDebugMode) {
        debugPrint(error.toString());
      }
    }
  }

  static final _pgcRegex = RegExp(r'(ep|ss)(\d+)');
  static bool viewPgcFromUri(
    String uri, {
    bool isPgc = true,
    int? progress, // milliseconds
    int? aid,
    bool off = false,
    String? heroTag,
    String? cover,
    String? title,
  }) {
    RegExpMatch? match = _pgcRegex.firstMatch(uri);
    if (match != null) {
      bool isSeason = match.group(1) == 'ss';
      String id = match.group(2)!;
      if (isPgc) {
        viewPgc(
          seasonId: isSeason ? id : null,
          epId: isSeason ? null : id,
          progress: progress,
          off: off,
          heroTag: heroTag,
          cover: cover,
          title: title,
        );
      } else {
        viewPugv(
          seasonId: isSeason ? id : null,
          epId: isSeason ? null : id,
          aid: aid,
          off: off,
          heroTag: heroTag,
          cover: cover,
          title: title,
        );
      }
      return true;
    }
    return false;
  }

  static EpisodeItem findEpisode(
    List<EpisodeItem> episodes, {
    dynamic epId,
    bool isPgc = true,
  }) {
    // epId episode -> progress episode -> first episode
    EpisodeItem? episode;
    if (epId != null) {
      epId = epId.toString();
      episode = episodes.firstWhereOrNull(
        (item) => (isPgc ? item.epId : item.id).toString() == epId,
      );
    }
    return episode ?? episodes.first;
  }

  static Future<void> viewPgc({
    dynamic seasonId,
    dynamic epId,
    int? progress, // milliseconds
    bool off = false,
    String? heroTag,
    String? cover,
    String? title,
  }) async {
    final arguments = _buildVideoPageArguments(
      videoType: VideoType.pgc,
      aid: null,
      bvid: null,
      cid: null,
      seasonId: seasonId is int ? seasonId : int.tryParse('$seasonId'),
      epId: epId is int ? epId : int.tryParse('$epId'),
      progress: progress,
      cover: cover,
      title: title,
      heroTag: heroTag,
      pendingLaunchType: VideoPendingLaunchType.pgc,
    );
    if (heroTag != null && !off) {
      _openVideoPage(arguments, off: false);
      return;
    }
    await _resolveAndOpenVideoPage(arguments, off: off);
  }

  static Future<void> viewPugv({
    dynamic seasonId,
    dynamic epId,
    int? aid,
    bool off = false,
    String? heroTag,
    String? cover,
    String? title,
  }) async {
    final arguments = _buildVideoPageArguments(
      videoType: VideoType.pugv,
      aid: aid,
      bvid: null,
      cid: null,
      seasonId: seasonId is int ? seasonId : int.tryParse('$seasonId'),
      epId: epId is int ? epId : int.tryParse('$epId'),
      cover: cover,
      title: title,
      heroTag: heroTag,
      pendingLaunchType: VideoPendingLaunchType.pugv,
    );
    if (heroTag != null && !off) {
      _openVideoPage(arguments, off: false);
      return;
    }
    await _resolveAndOpenVideoPage(arguments, off: off);
  }

  static void toDupNamed(
    String page, {
    dynamic arguments,
    Map<String, String>? parameters,
    bool off = false,
  }) {
    if (off) {
      Get.offNamed(
        page,
        arguments: arguments,
        parameters: parameters,
        preventDuplicates: false,
      );
    } else {
      Get.toNamed(
        page,
        arguments: arguments,
        parameters: parameters,
        preventDuplicates: false,
      );
    }
  }
}
