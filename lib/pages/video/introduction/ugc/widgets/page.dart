import 'dart:async';
import 'dart:math';

import 'package:PiliMax/common/assets.dart';
import 'package:PiliMax/models_new/video/video_detail/page.dart';
import 'package:PiliMax/models/common/episode_panel_type.dart';
import 'package:PiliMax/models_new/video/video_detail/episode.dart'
    show ShowEpisodes;
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/scroll_offset_helper.dart';
import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

// TODO refa
class PagesPanel extends StatefulWidget {
  const PagesPanel({
    super.key,
    this.list,
    this.cover,
    required this.bvid,
    required this.heroTag,
    this.showEpisodes,
    this.onBack,
    required this.ugcIntroController,
    this.onDownload,
    this.cidSet,
  });

  final List<Part>? list;
  final String? cover;

  final String bvid;
  final String heroTag;
  final ShowEpisodes? showEpisodes;
  final VoidCallback? onBack;
  final UgcIntroController ugcIntroController;

  final Set<int>? cidSet;
  final bool Function(Part part)? onDownload;

  @override
  State<PagesPanel> createState() => _PagesPanelState();
}

class _PagesPanelState extends State<PagesPanel> {
  late int cid;
  int pageIndex = -1;
  late final VideoDetailController _videoDetailController;
  late final ScrollController _scrollController;
  StreamSubscription? _listener;

  List<Part> get pages =>
      widget.list ??
      widget.ugcIntroController.videoDetail.value.pages ??
      const [];

  void _updatePageIndex() {
    pageIndex = max(0, pages.indexWhere((e) => e.cid == cid));
  }

  void _syncSource() {
    _listener?.cancel();
    _listener = null;
    if (widget.list != null) {
      pageIndex = -1;
      return;
    }
    cid = widget.ugcIntroController.cid.value;
    _updatePageIndex();
    _listener = _videoDetailController.cid.listen((cid) {
      this.cid = cid;
      _updatePageIndex();
      if (!mounted) return;
      setState(() {});
      jumpToCurr();
    });
  }

  @override
  void initState() {
    super.initState();
    _videoDetailController = Get.find<VideoDetailController>(
      tag: widget.heroTag,
    );
    _syncSource();
    _scrollController = ScrollController(keepScrollOffset: false);
    if (widget.list == null && pageIndex > 0) jumpToCurr(animate: false);
  }

  @override
  void didUpdateWidget(PagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.list != oldWidget.list || widget.bvid != oldWidget.bvid) {
      _syncSource();
      if (widget.list == null) {
        jumpToCurr(animate: false);
      }
    }
  }

  void jumpToCurr({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          pages.isEmpty ||
          pageIndex < 0 ||
          pageIndex >= pages.length) {
        return;
      }
      final position = _scrollController.position;
      final offset = calcPageItemOffset(
        index: pageIndex,
        itemCount: pages.length,
        viewportDimension: position.viewportDimension,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (animate) {
        position.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        position.jumpTo(offset);
      }
    });
  }

  @override
  void dispose() {
    _listener?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) return const SizedBox.shrink();
    final colorScheme = ColorScheme.of(context);
    return Column(
      children: [
        if (widget.showEpisodes != null &&
            pageIndex >= 0 &&
            pageIndex < pages.length)
          Padding(
            padding: const .only(top: 8, bottom: 2),
            child: Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                const Text('视频选集 '),
                Expanded(
                  child: Text(
                    ' 正在播放：${pages[pageIndex].part}',
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 34,
                  child: TextButton(
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(.zero),
                    ),
                    onPressed: () =>
                        widget.showEpisodes!(type: EpisodeType.part),
                    child: Text(
                      '共${pages.length}集',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 45,
          child: ListView.builder(
            key: PageStorageKey(widget.bvid),
            controller: _scrollController,
            scrollDirection: .horizontal,
            itemCount: pages.length,
            itemExtent: 150,
            padding: .zero,
            itemBuilder: (context, index) {
              bool isCurrentIndex = pageIndex == index;
              final item = pages[index];
              return Container(
                width: 150,
                margin: index != pages.length - 1
                    ? const .only(right: 10)
                    : null,
                child: Material(
                  color: colorScheme.onInverseSurface,
                  borderRadius: const .all(.circular(6)),
                  child: InkWell(
                    borderRadius: const .all(.circular(6)),
                    onTap: () {
                      if (widget.onDownload case final onDownload?) {
                        if (onDownload(item) && mounted) {
                          setState(() {});
                        }
                        return;
                      }
                      if (widget.showEpisodes == null) {
                        widget.onBack?.call();
                      }
                      if (isCurrentIndex) return;
                      widget.ugcIntroController.onChangeEpisode(
                        item
                          ..bvid ??= widget.bvid
                          ..cover ??= widget.cover,
                        manual: true,
                      );
                      if (widget.list != null &&
                          widget
                                  .ugcIntroController
                                  .videoDetail
                                  .value
                                  .ugcSeason !=
                              null) {
                        _videoDetailController.seasonCid = pages.first.cid;
                      }
                    },
                    child: Stack(
                      clipBehavior: .none,
                      children: [
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const .symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(
                                alpha: .7,
                              ),
                              borderRadius: const .only(
                                topLeft: .circular(2),
                                bottomRight: .circular(6),
                              ),
                            ),
                            child: Text(
                              (index + 1).toString(),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const .fromLTRB(8, 0, 28, 0),
                          child: Align(
                            alignment: .centerLeft,
                            child: Text.rich(
                              maxLines: 2,
                              overflow: .ellipsis,
                              style: TextStyle(
                                height: 1.1,
                                fontSize: 13,
                                color: isCurrentIndex
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                              strutStyle: const .new(
                                height: 1.1,
                                fontSize: 13,
                              ),
                              TextSpan(
                                children: [
                                  if (isCurrentIndex)
                                    WidgetSpan(
                                      alignment: .middle,
                                      child: Padding(
                                        padding: const .only(right: 6),
                                        child: Image.asset(
                                          Assets.livingStatic,
                                          color: colorScheme.primary,
                                          height: 12,
                                          cacheHeight: 12.cacheSize(
                                            context,
                                          ),
                                          semanticLabel: "正在播放：",
                                        ),
                                      ),
                                    )
                                  else if (widget.cidSet?.contains(
                                        item.cid,
                                      ) ??
                                      false)
                                    WidgetSpan(
                                      alignment: .middle,
                                      child: Icon(
                                        size: 13,
                                        color: colorScheme.secondary.withValues(
                                          alpha: .8,
                                        ),
                                        FontAwesomeIcons.circleDown,
                                      ),
                                    ),
                                  TextSpan(text: item.part),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
