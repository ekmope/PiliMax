import 'dart:async';

import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/image_utils.dart';
import 'package:PiliMax/utils/num_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

const _previewTransitionDuration = Duration(milliseconds: 220);
const _previewMetaFadeDuration = Duration(milliseconds: 140);
const _previewMetaCacheTtl = Duration(minutes: 5);
const _previewMetaCacheLimit = 64;

final Map<String, _PreviewMetaCacheEntry> _previewMetaCache = {};
final Map<String, Future<_PreviewMeta?>> _previewMetaInFlight = {};

void imageSaveDialog({
  required String? title,
  required String? cover,
  dynamic aid,
  String? bvid,
  int? pubdate,
  String? pubdateText,
  dynamic view,
  dynamic danmaku,
  dynamic like,
  dynamic favorite,
  String? ownerName,
}) {
  final context = Get.context!;
  final imgWidth = MediaQuery.sizeOf(context).shortestSide - 16;
  final initialMeta = _PreviewMeta.fromFallback(
    pubdate: pubdate,
    pubdateText: pubdateText,
    view: view,
    danmaku: danmaku,
    like: like,
    favorite: favorite,
    ownerName: ownerName,
  );

  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: _previewTransitionDuration,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scaleAnimation = Tween<double>(
        begin: 0.92,
        end: 1,
      ).animate(curvedAnimation);
      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          child: RepaintBoundary(child: child),
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) =>
        _CoverPreviewDialog(
          title: title,
          cover: cover,
          aid: aid,
          bvid: bvid,
          resolvedBvid: _resolveBvid(aid: aid, bvid: bvid),
          imgWidth: imgWidth,
          initialMeta: initialMeta,
          routeAnimation: animation,
        ),
  );
}

class _CoverPreviewDialog extends StatefulWidget {
  const _CoverPreviewDialog({
    required this.title,
    required this.cover,
    required this.aid,
    required this.bvid,
    required this.resolvedBvid,
    required this.imgWidth,
    required this.initialMeta,
    required this.routeAnimation,
  });

  final String? title;
  final String? cover;
  final dynamic aid;
  final String? bvid;
  final String? resolvedBvid;
  final double imgWidth;
  final _PreviewMeta initialMeta;
  final Animation<double> routeAnimation;

  @override
  State<_CoverPreviewDialog> createState() => _CoverPreviewDialogState();
}

class _CoverPreviewDialogState extends State<_CoverPreviewDialog> {
  late final ValueNotifier<_PreviewMeta> _metaNotifier;
  bool _metaLoadStarted = false;

  bool get _showMetadata =>
      widget.resolvedBvid != null || widget.initialMeta.hasAny;

  @override
  void initState() {
    super.initState();
    _metaNotifier = ValueNotifier(widget.initialMeta);
    widget.routeAnimation.addStatusListener(_onRouteAnimationStatus);
    if (widget.routeAnimation.status == AnimationStatus.completed) {
      unawaited(_loadMissingMeta());
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      unawaited(_loadMissingMeta());
    }
  }

  Future<void> _loadMissingMeta() async {
    final resolvedBvid = widget.resolvedBvid;
    if (_metaLoadStarted ||
        resolvedBvid == null ||
        !_metaNotifier.value.needsRefresh) {
      return;
    }
    _metaLoadStarted = true;

    final remoteMeta = await _loadPreviewMeta(resolvedBvid);
    if (!mounted || remoteMeta == null) {
      return;
    }
    _metaNotifier.value = _metaNotifier.value.merge(remoteMeta);
  }

  @override
  void dispose() {
    widget.routeAnimation.removeStatusListener(_onRouteAnimationStatus);
    _metaNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 20.0;
    final theme = Theme.of(context);
    final coverUrl = widget.cover;
    void dismissDialog() => Navigator.of(context).pop();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: widget.imgWidth,
          margin: const .symmetric(horizontal: Style.safeSpace),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Style.mdRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: dismissDialog,
                    child: NetworkImgLayer(
                      src: widget.cover,
                      quality: 100,
                      width: widget.imgWidth,
                      height: widget.imgWidth / Style.aspectRatio16x9,
                      borderRadius: const .vertical(top: Style.imgRadius),
                    ),
                  ),
                  if (coverUrl != null && coverUrl.isNotEmpty)
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 30,
                      height: 30,
                      child: IconButton(
                        tooltip: '保存封面图',
                        style: IconButton.styleFrom(
                          padding: .zero,
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                        onPressed: () async {
                          final saveStatus = await ImageUtils.downloadImg([
                            coverUrl,
                          ]);
                          if (saveStatus && context.mounted) {
                            dismissDialog();
                          }
                        },
                        icon: const Icon(
                          Icons.download,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    top: 8,
                    width: 30,
                    height: 30,
                    child: IconButton(
                      tooltip: '关闭',
                      style: IconButton.styleFrom(
                        padding: .zero,
                        backgroundColor: Colors.black.withValues(alpha: 0.3),
                      ),
                      onPressed: dismissDialog,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.title != null)
                          Expanded(
                            child: SelectableText(
                              widget.title!,
                              style: theme.textTheme.titleSmall,
                            ),
                          )
                        else
                          const Spacer(),
                        if (widget.aid != null || widget.bvid != null)
                          iconButton(
                            iconSize: iconSize,
                            tooltip: '稍后再看',
                            onPressed: () => {
                              dismissDialog(),
                              UserHttp.toViewLater(
                                aid: widget.aid,
                                bvid: widget.bvid,
                              ),
                            },
                            icon: const Icon(Icons.watch_later_outlined),
                          ),
                      ],
                    ),
                    if (_showMetadata) ...[
                      const SizedBox(height: 6),
                      ValueListenableBuilder<_PreviewMeta>(
                        valueListenable: _metaNotifier,
                        builder: (context, meta, _) =>
                            _PreviewMetadataGrid(meta: meta),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewMetadataGrid extends StatelessWidget {
  const _PreviewMetadataGrid({required this.meta});

  final _PreviewMeta meta;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight = textScaler.scale(12) + 7;
    final labelWidth = textScaler.scale(36);
    final style = TextStyle(
      fontSize: 12,
      height: 1,
      letterSpacing: 0,
      color: Theme.of(context).colorScheme.outline,
    );

    return SizedBox(
      height: rowHeight * 3 + 8,
      child: Column(
        children: [
          _PreviewMetadataRow(
            height: rowHeight,
            labelWidth: labelWidth,
            style: style,
            leftLabel: '发布',
            leftValue: meta.pubdateText,
            rightLabel: '播放',
            rightValue: _formatMetaNumber(meta.view),
          ),
          const SizedBox(height: 4),
          _PreviewMetadataRow(
            height: rowHeight,
            labelWidth: labelWidth,
            style: style,
            leftLabel: '点赞',
            leftValue: _formatMetaNumber(meta.like),
            rightLabel: '收藏',
            rightValue: _formatMetaNumber(meta.favorite),
          ),
          const SizedBox(height: 4),
          _PreviewMetadataRow(
            height: rowHeight,
            labelWidth: labelWidth,
            style: style,
            leftLabel: '弹幕',
            leftValue: _formatMetaNumber(meta.danmaku),
            rightLabel: 'UP',
            rightValue: meta.ownerName,
          ),
        ],
      ),
    );
  }
}

class _PreviewMetadataRow extends StatelessWidget {
  const _PreviewMetadataRow({
    required this.height,
    required this.labelWidth,
    required this.style,
    required this.leftLabel,
    required this.leftValue,
    required this.rightLabel,
    required this.rightValue,
  });

  final double height;
  final double labelWidth;
  final TextStyle style;
  final String leftLabel;
  final String? leftValue;
  final String rightLabel;
  final String? rightValue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: _PreviewMetadataCell(
              label: leftLabel,
              value: leftValue,
              labelWidth: labelWidth,
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _PreviewMetadataCell(
              label: rightLabel,
              value: rightValue,
              labelWidth: labelWidth,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMetadataCell extends StatelessWidget {
  const _PreviewMetadataCell({
    required this.label,
    required this.value,
    required this.labelWidth,
    required this.style,
  });

  final String label;
  final String? value;
  final double labelWidth;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim().isNotEmpty == true ? value! : '--';
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            '$label：',
            maxLines: 1,
            textAlign: TextAlign.end,
            overflow: TextOverflow.clip,
            style: style,
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: AnimatedSwitcher(
            duration: _previewMetaFadeDuration,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            ),
            child: Text(
              displayValue,
              key: ValueKey(displayValue),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ],
    );
  }
}

String? _formatMetaNumber(dynamic value) =>
    value == null ? null : NumUtils.numFormat(value);

Future<_PreviewMeta?> _loadPreviewMeta(String bvid) {
  final cached = _previewMetaCache[bvid];
  if (cached != null) {
    if (DateTime.now().difference(cached.cachedAt) < _previewMetaCacheTtl) {
      return Future.value(cached.meta);
    }
    _previewMetaCache.remove(bvid);
  }

  final inFlight = _previewMetaInFlight[bvid];
  if (inFlight != null) {
    return inFlight;
  }

  final future = _requestAndCachePreviewMeta(bvid);
  _previewMetaInFlight[bvid] = future;
  return future;
}

Future<_PreviewMeta?> _requestAndCachePreviewMeta(String bvid) async {
  try {
    final meta = await _requestPreviewMeta(bvid);
    if (meta != null) {
      _previewMetaCache.remove(bvid);
      if (_previewMetaCache.length >= _previewMetaCacheLimit) {
        _previewMetaCache.remove(_previewMetaCache.keys.first);
      }
      _previewMetaCache[bvid] = _PreviewMetaCacheEntry(
        meta: meta,
        cachedAt: DateTime.now(),
      );
    }
    return meta;
  } finally {
    _previewMetaInFlight.remove(bvid);
  }
}

Future<_PreviewMeta?> _requestPreviewMeta(String bvid) async {
  try {
    final res = await VideoHttp.videoIntro(bvid: bvid);
    if (res case Success(:final response)) {
      final stat = response.stat;
      final ownerName = response.owner?.name?.trim();
      return _PreviewMeta(
        pubdateText: response.pubdate == null
            ? null
            : DateFormatUtils.dateFormat(response.pubdate),
        view: stat?.view,
        danmaku: stat?.danmaku,
        like: stat?.like,
        favorite: stat?.favorite,
        ownerName: ownerName?.isNotEmpty == true ? ownerName : null,
      );
    }
  } catch (_) {}
  return null;
}

String? _resolveBvid({dynamic aid, String? bvid}) {
  final resolvedBvid = bvid?.trim();
  if (resolvedBvid?.isNotEmpty == true) {
    return resolvedBvid;
  }
  if (aid is int) {
    return IdUtils.av2bv(aid);
  }
  final resolvedAid = int.tryParse(aid?.toString() ?? '');
  if (resolvedAid != null) {
    return IdUtils.av2bv(resolvedAid);
  }
  return null;
}

class _PreviewMeta {
  const _PreviewMeta({
    this.pubdateText,
    this.view,
    this.danmaku,
    this.like,
    this.favorite,
    this.ownerName,
  });

  final String? pubdateText;
  final dynamic view;
  final dynamic danmaku;
  final dynamic like;
  final dynamic favorite;
  final String? ownerName;

  bool get hasAny =>
      pubdateText != null ||
      view != null ||
      danmaku != null ||
      like != null ||
      favorite != null ||
      ownerName != null;

  bool get needsRefresh =>
      pubdateText == null ||
      view == null ||
      danmaku == null ||
      like == null ||
      favorite == null ||
      ownerName == null;

  _PreviewMeta merge(_PreviewMeta remote) => _PreviewMeta(
    pubdateText: remote.pubdateText ?? pubdateText,
    view: remote.view ?? view,
    danmaku: remote.danmaku ?? danmaku,
    like: remote.like ?? like,
    favorite: remote.favorite ?? favorite,
    ownerName: remote.ownerName ?? ownerName,
  );

  factory _PreviewMeta.fromFallback({
    int? pubdate,
    String? pubdateText,
    dynamic view,
    dynamic danmaku,
    dynamic like,
    dynamic favorite,
    String? ownerName,
  }) {
    final normalizedPubdateText = pubdateText?.trim();
    return _PreviewMeta(
      pubdateText: normalizedPubdateText?.isNotEmpty == true
          ? normalizedPubdateText
          : pubdate != null && pubdate > 0
          ? DateFormatUtils.format(pubdate)
          : null,
      view: view,
      danmaku: danmaku,
      like: like,
      favorite: favorite,
      ownerName: ownerName?.trim().isNotEmpty == true
          ? ownerName!.trim()
          : null,
    );
  }
}

class _PreviewMetaCacheEntry {
  const _PreviewMetaCacheEntry({required this.meta, required this.cachedAt});

  final _PreviewMeta meta;
  final DateTime cachedAt;
}
