/*
 * This file is part of PiliMax
 *
 * PiliMax is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * PiliMax is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with PiliMax.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io' show File, Platform;

import 'package:PiliMax/common/widgets/colored_box_transition.dart';
import 'package:PiliMax/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliMax/pilimax/common/widgets/flutter/page/page_view.dart';
import 'package:PiliMax/common/widgets/gesture/image_horizontal_drag_gesture_recognizer.dart';
import 'package:PiliMax/common/widgets/image_viewer/image.dart';
import 'package:PiliMax/common/widgets/image_viewer/image_hero_tag.dart';
import 'package:PiliMax/common/widgets/image_viewer/loading_indicator.dart';
import 'package:PiliMax/common/widgets/image_viewer/viewer.dart';
import 'package:PiliMax/common/widgets/scroll_physics.dart';
import 'package:PiliMax/main.dart' show tmpPadding;
import 'package:PiliMax/models/common/image_preview_type.dart';
import 'package:PiliMax/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/max_screen_size.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart' hide Image, PageView;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

///
/// created by dom on 2026/02/14
///

class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    this.minScale = 1.0,
    this.maxScale = 8.0,
    required this.quality,
    required this.sources,
    this.initIndex = 0,
    this.onPageChanged,
    this.tag = '',
    this.heroScope,
    this.backGestureProgress,
    this.backGestureCommand,
  });

  final double minScale;
  final double maxScale;
  final int quality;
  final List<SourceModel> sources;
  final int initIndex;
  final ValueChanged<int>? onPageChanged;

  /// Stable business scope used to match the source image Hero.
  final String? heroScope;
  final String tag;

  /// Android predictive-back gesture progress [0,1]; drives the gallery's own
  /// mask fade + image scale so the surface follows the finger.
  final ValueNotifier<double>? backGestureProgress;

  /// 0 = idle, 1 = commit (pop), 2 = cancel (spring back).
  final ValueNotifier<int>? backGestureCommand;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer>
    with SingleTickerProviderStateMixin {
  late Size _containerSize;
  late final int _quality;
  late final RxInt _currIndex;
  GlobalKey? _key;
  EdgeInsets? _padding;

  late bool _hasInit = false;
  Player? _player;
  VideoController? _videoController;

  late final PageController _pageController;

  late final TapGestureRecognizer _tapGestureRecognizer;
  late final DoubleTapGestureRecognizer _doubleTapGestureRecognizer;
  late final ImageHorizontalDragGestureRecognizer
  _horizontalDragGestureRecognizer;

  ImageHorizontalDragGestureRecognizer horizontalDragGestureRecognizer() {
    return _horizontalDragGestureRecognizer;
  }

  late final LongPressGestureRecognizer _longPressGestureRecognizer;

  late final AnimationController _animateController;
  late final Animation<Color?> _opacityAnimation;
  double dx = 0, dy = 0;

  Offset _offset = Offset.zero;
  bool _dragging = false;
  bool _closing = false;

  String _getActualUrl(String url) {
    return _quality != 100
        ? ImageUtils.thumbnailUrl(url, _quality)
        : url.http2https;
  }

  Future<void> _initPlayer() async {
    assert(_player == null);
    final player = await Player.create();
    _videoController = await VideoController.create(player);
    if (!mounted) {
      player.dispose();
      _videoController = null;
      return;
    }
    _player = player;
    final currItem = widget.sources[_currIndex.value];
    if (currItem.sourceType == .livePhoto) {
      player.open(Media(currItem.liveUrl!));
      _currIndex.refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    _quality = Pref.previewQ;
    _currIndex = widget.initIndex.obs;
    final item = widget.sources[widget.initIndex];
    _playIfNeeded(item);

    if (!item.isLongPic) {
      _key = GlobalKey();
      WidgetsBinding.instance.addPostFrameCallback((_) => _key = null);
    }

    _pageController = PageController(initialPage: widget.initIndex);

    final gestureSettings = MediaQuery.maybeGestureSettingsOf(Get.context!);
    _tapGestureRecognizer = TapGestureRecognizer()
      // ..onTap = _onTap
      ..gestureSettings = gestureSettings;
    if (PlatformUtils.isDesktop) {
      _tapGestureRecognizer.onSecondaryTapUp = _showDesktopMenu;
    }
    _doubleTapGestureRecognizer = DoubleTapGestureRecognizer()
      ..onDoubleTap = () {}
      ..gestureSettings = gestureSettings;
    _horizontalDragGestureRecognizer = ImageHorizontalDragGestureRecognizer();
    _longPressGestureRecognizer = LongPressGestureRecognizer()
      ..onLongPress = _onLongPress
      ..gestureSettings = gestureSettings;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _tapGestureRecognizer.onTap = _onTap;
      }
    });

    _animateController = AnimationController(
      duration: const Duration(
        milliseconds: 750,
      ), // reverse only if value <= 0.2
      vsync: this,
    );

    _opacityAnimation = _animateController.drive(
      ColorTween(
        begin: Colors.black,
        end: Colors.transparent,
      ),
    );

    widget.backGestureProgress?.addListener(_onBackGestureProgress);
    widget.backGestureCommand?.addListener(_onBackGestureCommand);
  }

  void _onBackGestureProgress() {
    if (!mounted) return;
    final progress = widget.backGestureProgress?.value ?? 0.0;
    _animateController.value = progress.clamp(0.0, 1.0);
  }

  void _onBackGestureCommand() {
    if (!mounted) return;
    if (widget.backGestureCommand?.value == 1) {
      // The owning PageRoute commits the pop. Calling Navigator.pop here too
      // races that transaction and can pop the underlying page or require a
      // second swipe on Android.
      _closing = true;
    } else if (widget.backGestureCommand?.value == 2) {
      _dragging = false;
      _closing = false;
      if (_animateController.value > 0) {
        _animateController.reverse();
      }
    }
  }

  late final bool _hideSystemBar;

  void _initHideSystemBar() {
    if (Platform.isAndroid) {
      if (showSystemBar_) {
        final size = DeviceUtils.size;
        _hideSystemBar = !MaxScreenSize.isWindowMode(
          width: size.width,
          height: size.height,
        );
      } else {
        _hideSystemBar = false;
      }
    } else if (Platform.isIOS) {
      _hideSystemBar = showSystemBar_;
    } else {
      _hideSystemBar = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_padding == null) {
      final padding = MediaQuery.viewPaddingOf(context);
      _padding = padding;
      _initHideSystemBar();
      if (_hideSystemBar) {
        tmpPadding = padding;
        hideSystemBar()!.whenComplete(
          () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => tmpPadding = null,
          ),
        );
      }
    }
  }

  Matrix4 _onTransform(double val) {
    // Follow the finger one-to-one while shrinking the image enough for the
    // dismiss feedback to stay visible. The 0.72 floor keeps the preview on
    // screen until the Hero flight actually takes over on release.
    final scale = val.lerp(1.0, 0.72);
    final drag = val;

    // Matrix4.identity()
    //   ..translateByDouble(size.width / 2, size.height / 2, 0, 1)
    //   ..translateByDouble(size.width * val * dx, size.height * val * dy, 0, 1)
    //   ..scaleByDouble(scale, scale, scale, 1)
    //   ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);

    final tmp = (1.0 - scale) / 2.0;
    return Matrix4.diagonal3Values(scale, scale, scale)..setTranslationRaw(
      _containerSize.width * (drag * dx + tmp),
      _containerSize.height * (drag * dy + tmp),
      0,
    );
  }

  void _updateMoveAnimation() {
    dy = _offset.dy.sign;
    if (dy == 0) {
      dx = 0;
    } else {
      dx = (_offset.dx / _offset.dy.abs()).clamp(-1.0, 1.0).toDouble();
    }
  }

  void _onDragStart(ScaleStartDetails details) {
    if (_closing) return;
    _dragging = true;

    if (_animateController.isAnimating) {
      _animateController.stop();
    }
    _offset = Offset.zero;
    _animateController.value = 0.0;
    _updateMoveAnimation();
  }

  void _onDragUpdate(ScaleUpdateDetails details) {
    if (_closing || !_dragging || _animateController.isAnimating) {
      return;
    }

    _offset += details.focalPointDelta;
    _updateMoveAnimation();

    if (!_animateController.isAnimating && _containerSize.height > 0) {
      final rawProgress = _offset.dy.abs() / _containerSize.height;
      // No damping or cap: the mask opacity and image transform must keep
      // tracking the gesture all the way up to (and past) the close threshold.
      // The previous clamp to 0.32 made the surface barely move/fade and then
      // pop abruptly, which read as "not following the hand".
      final progress = rawProgress.clamp(0.0, 1.0).toDouble();
      _animateController.value = progress;
    }
  }

  void _onDragEnd(ScaleEndDetails details) {
    if (_closing || !_dragging || _animateController.isAnimating) {
      return;
    }

    _dragging = false;

    if (!_animateController.isDismissed) {
      if (_animateController.value > 0.2) {
        _dismiss();
      } else {
        _animateController.reverse();
      }
    }
  }

  void _dismiss() {
    if (_closing || !mounted) return;
    _closing = true;
    // Let the route animation and HeroController perform the closing flight
    // from the current bounded transform. Never animate the gallery controller
    // to 1.0 first, which would push the image off-screen before popping.
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.backGestureProgress?.removeListener(_onBackGestureProgress);
    widget.backGestureCommand?.removeListener(_onBackGestureCommand);
    _player?.dispose();
    _player = null;
    _videoController = null;
    _pageController.dispose();
    _animateController.dispose();
    _tapGestureRecognizer.dispose();
    _doubleTapGestureRecognizer
      ..onDoubleTapDown = null
      ..onDoubleTap = null
      ..dispose();
    _longPressGestureRecognizer.dispose();
    if (widget.quality != _quality) {
      for (final item in widget.sources) {
        if (item.sourceType == SourceType.networkImage) {
          CachedNetworkImageProvider(_getActualUrl(item.url)).evict();
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 200), _currIndex.close);
    super.dispose();
    if (_hideSystemBar) {
      showSystemBar();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _tapGestureRecognizer.addPointer(event);
    _doubleTapGestureRecognizer.addPointer(event);
    _longPressGestureRecognizer.addPointer(event);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .opaque,
      onPointerDown: _onPointerDown,
      child: Stack(
        fit: .expand,
        alignment: .center,
        clipBehavior: .none,
        children: [
          ColoredBoxTransition(color: _opacityAnimation),
          LayoutBuilder(
            builder: (context, constraints) {
              _containerSize = constraints.biggest;
              return MatrixTransition(
                alignment: .topLeft,
                animation: _animateController,
                onTransform: _onTransform,
                child: PageView<ImageHorizontalDragGestureRecognizer>.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const CustomTabBarViewScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: widget.sources.length,
                  itemBuilder: _itemBuilder,
                  horizontalDragGestureRecognizer:
                      horizontalDragGestureRecognizer,
                ),
              );
            },
          ),
          _buildIndicator,
        ],
      ),
    );
  }

  Widget get _buildIndicator => Positioned(
    bottom: 0,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Container(
        padding: _padding! + const EdgeInsets.fromLTRB(12, 8, 20, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.3),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Obx(
          () => Text(
            "${_currIndex.value + 1}/${widget.sources.length}",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  );

  void _playIfNeeded(SourceModel item) {
    if (item.sourceType == .livePhoto) {
      if (_player != null) {
        _player!.open(Media(item.liveUrl!));
      } else if (!_hasInit) {
        _hasInit = true;
        _initPlayer();
      }
    }
  }

  void _onPageChanged(int index) {
    _player?.pause();
    _playIfNeeded(widget.sources[index]);
    _currIndex.value = index;
    widget.onPageChanged?.call(index);
  }

  late final ValueChanged<int>? _onChangePage = widget.sources.length == 1
      ? null
      : (int offset) {
          final currPage = _pageController.page?.round() ?? 0;
          final nextPage = (currPage + offset).clamp(
            0,
            widget.sources.length - 1,
          );
          if (nextPage != currPage) {
            _pageController.animateToPage(
              nextPage,
              duration: const Duration(milliseconds: 200),
              curve: Curves.ease,
            );
          }
        };

  Widget _itemBuilder(BuildContext context, int index) {
    final item = widget.sources[index];
    final Widget child;
    switch (item.sourceType) {
      case SourceType.fileImage:
        child = Image.file(
          key: _key,
          File(item.url),
          filterQuality: .low,
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
        );
      case SourceType.networkImage:
        child = Image(
          key: _key,
          image: CachedNetworkImageProvider(_getActualUrl(item.url)),
          minScale: widget.minScale,
          maxScale: widget.maxScale,
          containerSize: _containerSize,
          doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
          horizontalDragGestureRecognizer: _horizontalDragGestureRecognizer,
          onChangePage: _onChangePage,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              return child;
            }
            if (frame == null) {
              if (widget.quality == _quality) {
                return child;
              } else {
                return Image(
                  image: ResizeImage.resizeIfNeeded(
                    _containerSize.width.cacheSize(context),
                    null,
                    CachedNetworkImageProvider(
                      ImageUtils.thumbnailUrl(item.url, widget.quality),
                    ),
                  ),
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  containerSize: _containerSize,
                  onDragStart: null,
                  onDragUpdate: null,
                  onDragEnd: null,
                  doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
                  horizontalDragGestureRecognizer:
                      _horizontalDragGestureRecognizer,
                  onChangePage: _onChangePage,
                );
                // final isLongPic = item.isLongPic;
                // return CachedNetworkImage(
                //   fadeInDuration: Duration.zero,
                //   fadeOutDuration: Duration.zero,
                //   // fit: isLongPic ? .fitWidth : null,
                //   // alignment: isLongPic ? .topCenter : .center,
                //   imageUrl: ImageUtils.thumbnailUrl(item.url, widget.quality),
                //   placeholder: (_, _) => const SizedBox.expand(),
                // );
              }
            }
            return child;
          },
          loadingBuilder: loadingBuilder,
          onDragStart: _onDragStart,
          onDragUpdate: _onDragUpdate,
          onDragEnd: _onDragEnd,
        );
      case SourceType.livePhoto:
        child = Obx(
          key: _key,
          () => _currIndex.value == index && _videoController != null
              ? Viewer(
                  minScale: widget.minScale,
                  maxScale: widget.maxScale,
                  containerSize: _containerSize,
                  childSize: _containerSize,
                  onDragStart: _onDragStart,
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _onDragEnd,
                  doubleTapGestureRecognizer: _doubleTapGestureRecognizer,
                  horizontalDragGestureRecognizer:
                      _horizontalDragGestureRecognizer,
                  onChangePage: _onChangePage,
                  child: FittedBox(
                    child: SimpleVideo(
                      controller: _videoController!,
                      fill: Colors.transparent,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        );
    }
    final tag = widget.heroScope == null
        ? '${item.url}${widget.tag}'
        : ImageHeroTag.item(
            scope: widget.heroScope!,
            url: item.url,
            index: index,
          );
    return Hero(
      tag: tag,
      child: child,
    );
  }

  void _onTap() {
    EasyThrottle.throttle(
      'VIEWER_TAP',
      const Duration(milliseconds: 555),
      _dismiss,
    );
  }

  void _onLongPress() {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == .fileImage) return;
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        clipBehavior: Clip.hardEdge,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (PlatformUtils.isMobile)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.onShareImg(item.url);
              },
              child: const Text('分享', style: TextStyle(fontSize: 14)),
            ),
          DialogOption(
            onPressed: () {
              Get.back();
              Utils.copyText(item.url);
            },
            child: const Text('复制链接', style: TextStyle(fontSize: 14)),
          ),
          DialogOption(
            onPressed: () {
              Get.back();
              ImageUtils.downloadImg([item.url]);
            },
            child: const Text('保存图片', style: TextStyle(fontSize: 14)),
          ),
          if (PlatformUtils.isDesktop)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.copyImg(item.url);
              },
              child: const Text('澶嶅埗鍥剧墖', style: TextStyle(fontSize: 14)),
            ),
          if (PlatformUtils.isDesktop)
            DialogOption(
              onPressed: () {
                Get.back();
                PageUtils.launchURL(item.url);
              },
              child: const Text('网页打开', style: TextStyle(fontSize: 14)),
            )
          else if (widget.sources.length > 1)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.downloadImg(
                  widget.sources.map((item) => item.url).toList(),
                );
              },
              child: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
            ),
          if (item.sourceType == SourceType.livePhoto)
            DialogOption(
              onPressed: () {
                Get.back();
                ImageUtils.downloadLivePhoto(
                  url: item.url,
                  liveUrl: item.liveUrl!,
                  width: item.width!,
                  height: item.height!,
                );
              },
              child: Text(
                '保存${Platform.isIOS ? ' Live Photo' : '视频'}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  void _showDesktopMenu(TapUpDetails details) {
    final item = widget.sources[_currIndex.value];
    if (item.sourceType == .fileImage) return;
    showMenu(
      context: context,
      position: PageUtils.menuPosition(details.globalPosition),
      items: [
        PopupMenuItem(
          height: 42,
          onTap: () => ImageUtils.downloadImg([item.url]),
          child: const Text('保存图片', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => Utils.copyText(item.url),
          child: const Text('复制链接', style: TextStyle(fontSize: 14)),
        ),
        PopupMenuItem(
          height: 42,
          onTap: () => PageUtils.launchURL(item.url),
          child: const Text('网页打开', style: TextStyle(fontSize: 14)),
        ),
        if (item.sourceType == SourceType.livePhoto)
          PopupMenuItem(
            height: 42,
            onTap: () => ImageUtils.downloadLivePhoto(
              url: item.url,
              liveUrl: item.liveUrl!,
              width: item.width!,
              height: item.height!,
            ),
            child: const Text('保存视频', style: TextStyle(fontSize: 14)),
          ),
      ],
    );
  }

  Widget loadingBuilder(
    BuildContext context,
    Widget child,
    ImageChunkEvent? loadingProgress,
  ) {
    return Stack(
      fit: .expand,
      alignment: .center,
      clipBehavior: .none,
      children: [
        child,
        if (loadingProgress != null &&
            loadingProgress.expectedTotalBytes != null &&
            loadingProgress.cumulativeBytesLoaded !=
                loadingProgress.expectedTotalBytes)
          Center(
            child: LoadingIndicator(
              size: 39.4,
              progress:
                  loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!,
            ),
          ),
      ],
    );
  }
}
