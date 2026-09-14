import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/pages/rcmd/today_watch/today_watch_controller.dart';
import 'package:PiliPlus/pages/rcmd/today_watch/today_watch_policy.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 首页「今日推荐单」卡片：基于本地观看历史生成的个性化队列
class TodayWatchCard extends StatelessWidget {
  const TodayWatchCard({super.key, required this.controller});

  final TodayWatchController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Obx(
      () {
        if (controller.collapsed.value) {
          return _buildCollapsed(context, colorScheme);
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, colorScheme),
                const SizedBox(height: 10),
                _buildModeSelector(colorScheme),
                const SizedBox(height: 10),
                Obx(() => _buildBody(context, colorScheme)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsed(BuildContext context, ColorScheme colorScheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '今日推荐单已收起，展开后恢复自动更新',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: controller.toggleCollapsed,
              icon: const Icon(Icons.expand_more, size: 18),
              label: const Text('展开'),
            ),
            TextButton.icon(
              onPressed: () => controller.generate(force: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, size: 20, color: colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '今日推荐单',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ),
        TextButton.icon(
          onPressed:
              controller.loading.value ? null : () => controller.generate(force: true),
          icon: controller.loading.value
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: const Text('刷新'),
        ),
        TextButton.icon(
          onPressed: controller.toggleCollapsed,
          icon: const Icon(Icons.expand_less, size: 18),
          label: const Text('收起'),
        ),
      ],
    );
  }

  Widget _buildModeSelector(ColorScheme colorScheme) {
    return Obx(
      () => SegmentedButton<TodayWatchMode>(
        segments: [
          for (final mode in TodayWatchMode.values)
            ButtonSegment(value: mode, label: Text(mode.label)),
        ],
        selected: {controller.mode.value},
        onSelectionChanged: (selection) => controller.setMode(selection.first),
        style: const ButtonStyle(
          visualDensity: VisualDensity(horizontal: -2, vertical: -2),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    if (controller.loading.value) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            '正在根据你的历史观看习惯生成推荐…',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }

    final err = controller.error.value;
    if (err != null) {
      return Text(
        err,
        style: TextStyle(fontSize: 13, color: colorScheme.error),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    final plan = controller.plan.value;
    if (plan == null) {
      return Text(
        '点「刷新」根据你的观看习惯生成今日推荐',
        style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '点开后会自动从推荐单移除；想换一批可点右上角「刷新」',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        if (plan.upRanks.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildUpRanks(colorScheme, plan.upRanks),
        ],
        if (plan.videoQueue.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '视频队列',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          for (final (index, video) in plan.videoQueue.take(6).indexed)
            _buildQueueRow(context, colorScheme, plan, index, video),
        ],
      ],
    );
  }

  Widget _buildUpRanks(ColorScheme colorScheme, List<TodayUpRank> upRanks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'UP主榜',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (index, up) in upRanks.indexed)
              GestureDetector(
                onTap: () => Get.toNamed('/member?mid=${up.mid}'),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${index + 1}. ',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.primary,
                        ),
                      ),
                      TextSpan(
                        text: up.name,
                        style: TextStyle(
                          fontSize: 13,
                          color: up.mid > 0
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: ' ${up.watchCount}次',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildQueueRow(
    BuildContext context,
    ColorScheme colorScheme,
    TodayWatchPlan plan,
    int index,
    BaseRcmdVideoItemModel video,
  ) {
    final ownerName = video.owner.name?.trim();
    final displayName =
        (ownerName != null && ownerName.isNotEmpty) ? ownerName : 'UP主';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.onVideoTap(video),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 13, color: colorScheme.primary),
              ),
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (context) {
                final face = switch (video.owner) {
                  Owner(:final face) when face != null && face.isNotEmpty => face,
                  _ => null,
                };
                if (face != null) {
                  return ClipOval(
                    child: NetworkImgLayer(
                      src: face,
                      width: 34,
                      height: 34,
                      type: .avatar,
                    ),
                  );
                }
                return Container(
                  width: 34,
                  height: 34,
                  alignment: .center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    (video.owner.name?.trim().isNotEmpty ?? false)
                        ? video.owner.name!.trim()[0]
                        : 'UP',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$displayName · ${video.duration > 0 ? DurationUtils.formatDuration(video.duration) : '时长未知'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if ((plan.explanationByBvid[video.bvid] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        plan.explanationByBvid[video.bvid]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
