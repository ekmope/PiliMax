import 'package:PiliMax/common/skeleton/video_reply.dart';
import 'package:PiliMax/common/style.dart';
import 'package:PiliMax/common/widgets/flutter/pop_scope.dart';
import 'package:PiliMax/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliMax/common/widgets/loading_widget/http_error.dart';
import 'package:PiliMax/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pages/common/fab_mixin.dart';
import 'package:PiliMax/pages/video/reply/controller.dart';
import 'package:PiliMax/pages/video/reply/widgets/reply_item_grpc.dart';
import 'package:PiliMax/pages/video/reply_reply/view.dart';
import 'package:PiliMax/utils/feed_back.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart';
import 'package:fixnum/fixnum.dart' show Int64;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class VideoReplyPanel extends StatefulWidget {
  const VideoReplyPanel({
    super.key,
    this.replyLevel = 1,
    required this.heroTag,
    required this.isNested,
  });

  final int replyLevel;
  final String heroTag;
  final bool isNested;

  @override
  State<VideoReplyPanel> createState() => _VideoReplyPanelState();
}

class _VideoReplyPanelState extends State<VideoReplyPanel>
    with
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin,
        BaseFabMixin,
        FabMixin {
  late VideoReplyController _videoReplyController;
  final List<_ReplyDetailArgs> _replyDetailStack = <_ReplyDetailArgs>[];

  _ReplyDetailArgs? get _replyDetailArgs =>
      _replyDetailStack.isEmpty ? null : _replyDetailStack.last;

  String get heroTag => widget.heroTag;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _videoReplyController = Get.find<VideoReplyController>(tag: heroTag);
    if (_videoReplyController.loadingState.value is Loading) {
      _videoReplyController.queryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    bottom = MediaQuery.viewPaddingOf(context).bottom;
  }

  late double bottom;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final child = popScope(
      canPop: _replyDetailArgs == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _replyDetailArgs != null) {
          _popReplyDetail();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _replyDetailArgs == null
            ? _buildReplyList(theme)
            : _buildReplyDetail(theme, _replyDetailArgs!),
      ),
    );
    if (widget.isNested) {
      return ExtendedVisibilityDetector(
        uniqueKey: const Key('reply-list'),
        child: child,
      );
    }
    return child;
  }

  Widget _buildReplyList(ThemeData theme) {
    final child = NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        switch (notification.direction) {
          case .forward:
            showFab();
          case .reverse:
            hideFab();
          case _:
        }
        return false;
      },
      child: refreshIndicator(
        onRefresh: _videoReplyController.onRefresh,
        isClampingScrollPhysics: widget.isNested,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CustomScrollView(
              controller: widget.isNested
                  ? null
                  : _videoReplyController.scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              key: const PageStorageKey(_VideoReplyPanelState),
              slivers: [
                SliverFloatingHeaderWidget(
                  backgroundColor: theme.colorScheme.surface,
                  child: Padding(
                    padding: const .fromLTRB(12, 2.5, 6, 2.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Obx(
                          () => Text(
                            _videoReplyController.sortType.value.title,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          style: Style.buttonStyle,
                          onPressed: _videoReplyController.queryBySort,
                          icon: Icon(
                            Icons.sort,
                            size: 16,
                            color: theme.colorScheme.secondary,
                          ),
                          label: Obx(
                            () => Text(
                              _videoReplyController.sortType.value.label,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Obx(
                  () => _buildBody(
                    theme,
                    _videoReplyController.loadingState.value,
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: SlideTransition(
                position: fabAnimation,
                child: Padding(
                  padding: .only(
                    right: kFloatingActionButtonMargin,
                    bottom: kFloatingActionButtonMargin + bottom,
                  ),
                  child: FloatingActionButton(
                    heroTag: null,
                    onPressed: () {
                      feedBack();
                      _videoReplyController.onReply(
                        null,
                        oid: _videoReplyController.aid,
                        replyType: _videoReplyController.videoType.replyType,
                      );
                    },
                    tooltip: '发表评论',
                    child: const Icon(Icons.reply),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return child;
  }

  Widget _buildReplyDetail(ThemeData theme, _ReplyDetailArgs args) {
    return Column(
      key: ValueKey('${args.rpid}-${args.dialog ?? 0}'),
      children: [
        Container(
          height: 45,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 1,
                color: theme.dividerColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(args.dialog == null ? '评论详情' : '对话列表'),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 20),
                onPressed: _popReplyDetail,
              ),
            ],
          ),
        ),
        Expanded(
          child: VideoReplyReplyPanel(
            enableSlide: false,
            id: args.id,
            oid: args.oid,
            rpid: args.rpid,
            dialog: args.dialog,
            firstFloor: args.firstFloor,
            replyType: args.replyType,
            isVideoDetail: false,
            isNested: widget.isNested,
            heroTag: heroTag,
            upMid: args.upMid,
            onShowDialogue: _pushDialogueDetail,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    ThemeData theme,
    LoadingState<List<ReplyInfo>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => SliverList.builder(
        itemBuilder: (context, index) => const VideoReplySkeleton(),
        itemCount: 5,
      ),
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverList.builder(
                itemBuilder: (context, index) {
                  if (index == response.length) {
                    _videoReplyController.onLoadMore();
                    return Container(
                      height: 125,
                      alignment: Alignment.center,
                      margin: EdgeInsets.only(bottom: bottom),
                      child: Text(
                        _videoReplyController.isEnd ? '没有更多了' : '加载中...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    );
                  } else {
                    return ReplyItemGrpc(
                      replyItem: response[index],
                      replyLevel: widget.replyLevel,
                      replyReply: replyReply,
                      onReply: _videoReplyController.onReply,
                      onDelete: (item, subIndex) =>
                          _videoReplyController.onRemove(index, item, subIndex),
                      upMid: _videoReplyController.upMid,
                      getTag: () => heroTag,
                      onCheckReply: (item) => _videoReplyController
                          .onCheckReply(item, isManual: true),
                      onToggleTop: (item) => _videoReplyController.onToggleTop(
                        item,
                        index,
                        _videoReplyController.aid,
                        _videoReplyController.videoType.replyType,
                      ),
                    );
                  }
                },
                itemCount: response.length + 1,
              )
            : HttpError(
                errMsg: '还没有评论',
                onReload: _videoReplyController.onReload,
              ),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _videoReplyController.onReload,
      ),
    };
  }

  // 展示二级回复
  void replyReply(ReplyInfo replyItem, int? id) {
    EasyThrottle.throttle('replyReply', const Duration(milliseconds: 500), () {
      int oid = replyItem.oid.toInt();
      int rpid = replyItem.id.toInt();
      _pushReplyDetail(
        _ReplyDetailArgs(
          id: id,
          oid: oid,
          rpid: rpid,
          firstFloor: replyItem.replyControl.isNote ? null : replyItem,
          replyType: _videoReplyController.videoType.replyType,
          upMid: _videoReplyController.upMid,
        ),
      );
    });
  }

  void _pushDialogueDetail({
    required int oid,
    required int rpid,
    required int dialog,
    required int replyType,
    String? heroTag,
    Int64? upMid,
  }) {
    _pushReplyDetail(
      _ReplyDetailArgs(
        id: null,
        oid: oid,
        rpid: rpid,
        dialog: dialog,
        firstFloor: null,
        replyType: replyType,
        upMid: upMid,
      ),
    );
  }

  void _pushReplyDetail(_ReplyDetailArgs args) {
    setState(() => _replyDetailStack.add(args));
  }

  void _popReplyDetail() {
    if (_replyDetailStack.isEmpty) {
      return;
    }
    setState(() {
      _replyDetailStack.removeLast();
    });
  }
}

class _ReplyDetailArgs {
  const _ReplyDetailArgs({
    required this.id,
    required this.oid,
    required this.rpid,
    this.dialog,
    required this.firstFloor,
    required this.replyType,
    required this.upMid,
  });

  final int? id;
  final int oid;
  final int rpid;
  final int? dialog;
  final ReplyInfo? firstFloor;
  final int replyType;
  final Int64? upMid;
}
