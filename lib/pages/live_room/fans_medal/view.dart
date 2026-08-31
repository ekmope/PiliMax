import 'dart:async' show unawaited;

import 'package:PiliMax/common/widgets/image/network_img_layer.dart';
import 'package:PiliMax/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliMax/models/common/image_type.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/item.dart';
import 'package:PiliMax/pages/live_room/controller.dart';
import 'package:PiliMax/pages/member/widget/medal_widget.dart';
import 'package:PiliMax/utils/num_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FansMedalPanel extends StatefulWidget {
  const FansMedalPanel({
    super.key,
    required this.liveRoomController,
  });

  final LiveRoomController liveRoomController;

  @override
  State<FansMedalPanel> createState() => _FansMedalPanelState();
}

class _FansMedalPanelState extends State<FansMedalPanel> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.liveRoomController.loadFansMedal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _TitleBar(liveRoomController: widget.liveRoomController),
        Expanded(
          child: Obx(() {
            final data = widget.liveRoomController.fansMedalData.value;
            final loading = widget.liveRoomController.fansMedalLoading.value;
            final error = widget.liveRoomController.fansMedalError.value;

            if (data == null && loading) {
              return const SizedBox(height: 160, child: m3eLoading);
            }
            if (data == null && error != null) {
              return _ErrorView(
                error: error,
                onRetry: () =>
                    widget.liveRoomController.loadFansMedal(force: true),
              );
            }
            if (data == null) return const SizedBox.shrink();

            final items = [...?data.specialList, ...?data.list];
            if (items.isEmpty) {
              return Center(
                child: Text(
                  '还没有粉丝勋章',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return _FansMedalList(
              items: items,
              liveRoomController: widget.liveRoomController,
            );
          }),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.liveRoomController});

  final LiveRoomController liveRoomController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            Text('粉丝勋章', style: theme.textTheme.titleMedium),
            const Spacer(),
            Obx(() {
              final total = liveRoomController.fansMedalData.value?.totalNumber;
              if (total == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '共 $total 枚',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }),
            Obx(
              () => IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed:
                    liveRoomController.fansMedalLoading.value ||
                        liveRoomController.fansMedalActing.value
                    ? null
                    : () => liveRoomController.loadFansMedal(force: true),
                tooltip: '刷新',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _FansMedalList extends StatefulWidget {
  const _FansMedalList({
    required this.items,
    required this.liveRoomController,
  });

  final List<FansMedalItem> items;
  final LiveRoomController liveRoomController;

  @override
  State<_FansMedalList> createState() => _FansMedalListState();
}

class _FansMedalListState extends State<_FansMedalList> {
  bool _acting = false;
  bool _autoFillScheduled = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleAutoFill();
  }

  @override
  void didUpdateWidget(covariant _FansMedalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleAutoFill();
  }

  void _scheduleAutoFill() {
    if (_autoFillScheduled) return;
    _autoFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoFillScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      if (widget.liveRoomController.fansMedalHasMore.value &&
          _scrollController.position.maxScrollExtent <= 0) {
        unawaited(widget.liveRoomController.loadMoreFansMedal());
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          unawaited(widget.liveRoomController.loadMoreFansMedal());
        }
        return false;
      },
      child: Obx(() {
        final hasMore = widget.liveRoomController.fansMedalHasMore.value;
        final loading = widget.liveRoomController.fansMedalLoading.value;
        final acting = widget.liveRoomController.fansMedalActing.value;
        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          itemCount: widget.items.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 2),
          itemBuilder: (context, index) {
            if (hasMore && index == widget.items.length) {
              return const SizedBox(height: 48, child: m3eLoading);
            }
            final item = widget.items[index];
            return _FansMedalTile(
              item: item,
              acting: _acting || loading || acting,
              onTap: () => _handleTap(item),
            );
          },
        );
      }),
    );
  }

  Future<void> _handleTap(FansMedalItem item) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      if (item.medal?.wearingStatus == 1) {
        await widget.liveRoomController.takeOffFansMedal(item);
      } else {
        final success = await widget.liveRoomController.wearFansMedal(item);
        if (success && mounted) Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }
}

class _FansMedalTile extends StatelessWidget {
  const _FansMedalTile({
    required this.item,
    required this.acting,
    required this.onTap,
  });

  final FansMedalItem item;
  final bool acting;
  final VoidCallback onTap;

  bool get _isWearing => item.medal?.wearingStatus == 1;

  String? get _supportingText {
    final medal = item.medal;
    if (medal == null) return null;
    final parts = [
      if (medal.nextIntimacy case final next? when next > 0)
        '${medal.intimacy ?? 0}/$next 亲密度',
      if (medal.dayLimit case final limit?)
        '今日上限 ${NumUtils.numFormat(medal.todayFeed ?? 0)}/${NumUtils.numFormat(limit)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWearing = _isWearing;
    final containerColor = isWearing
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerLow;
    final foregroundColor = isWearing
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurface;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: acting ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 88),
              decoration: BoxDecoration(
                color: containerColor,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.fromLTRB(16, 10, isWearing ? 48 : 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: NetworkImgLayer(
                      src: item.anchorAvatar ?? '',
                      width: 40,
                      height: 40,
                      type: ImageType.avatar,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.superscript case final superscript?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              superscript,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isWearing
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            _buildMedalChip(),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.anchorName ?? '',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: foregroundColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (item.medal?.nextIntimacy case final next?
                            when next > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: LinearProgressIndicator(
                              value: ((item.medal?.intimacy ?? 0) / next).clamp(
                                0.0,
                                1.0,
                              ),
                              minHeight: 4,
                              backgroundColor: isWearing
                                  ? colorScheme.onSecondaryContainer.withValues(
                                      alpha: 0.24,
                                    )
                                  : null,
                            ),
                          ),
                        if (_supportingText case final supportingText?)
                          Text(
                            supportingText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isWearing
                                  ? colorScheme.onSecondaryContainer
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isWearing)
              Positioned(
                top: 10,
                right: 16,
                child: Icon(
                  Icons.check_circle,
                  size: 20,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedalChip() {
    final uinfoMedal = item.uinfoMedal;
    if (uinfoMedal?.name != null &&
        uinfoMedal?.level != null &&
        uinfoMedal?.v2MedalColorStart?.isNotEmpty == true &&
        uinfoMedal?.v2MedalColorText?.isNotEmpty == true) {
      return MedalWidget.fromMedalInfo(
        medal: uinfoMedal!,
        padding: MedalWidget.mediumPadding,
      );
    }
    return MedalWidget(
      medalName: item.medal?.medalName ?? '',
      level: item.medal?.level ?? 0,
      backgroundColor: const Color(0xCC919298),
      nameColor: Colors.white,
      padding: MedalWidget.mediumPadding,
    );
  }
}
