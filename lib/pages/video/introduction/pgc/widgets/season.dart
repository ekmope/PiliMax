import 'dart:math' show max;

import 'package:PiliMax/models_new/pgc/pgc_info_model/season.dart';
import 'package:PiliMax/pages/video/introduction/pgc/controller.dart';
import 'package:PiliMax/utils/scroll_offset_helper.dart';
import 'package:material_ui/material_ui.dart';

/// Horizontal selector for PGC series that expose more than one season.
class SeasonPanel extends StatelessWidget {
  const SeasonPanel({
    super.key,
    required this.seasons,
    required this.pgcController,
    required this.onSeasonChanged,
  });

  final List<Season> seasons;
  final PgcIntroController pgcController;
  final VoidCallback onSeasonChanged;

  void _scrollToCurrent(
    BuildContext context,
    ScrollController controller, {
    bool animate = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || !controller.hasClients) return;
      final items = pgcController.pgcItem.seasons ?? seasons;
      final index = items.indexWhere(
        (item) => item.seasonId == pgcController.seasonId,
      );
      if (index < 0) return;
      final position = controller.position;
      final offset = calcPageItemOffset(
        index: index,
        itemCount: items.length,
        extent: 160,
        itemExtent: 160,
        viewportDimension: position.viewportDimension,
      ).clamp(position.minScrollExtent, position.maxScrollExtent);
      if (animate) {
        position.animateTo(
          offset,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else {
        position.jumpTo(offset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = max(
      0,
      seasons.indexWhere((item) => item.seasonId == pgcController.seasonId),
    );
    final controller = pgcController.seasonController(currentIndex);
    if (!controller.hasClients && currentIndex > 0) {
      _scrollToCurrent(context, controller);
    }
    final colorScheme = ColorScheme.of(context);
    return SizedBox(
      height: 35,
      child: ListView.builder(
        controller: controller,
        padding: EdgeInsets.zero,
        itemCount: seasons.length,
        itemExtent: 160,
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final item = seasons[index];
          final isCurrent = index == currentIndex;
          return Padding(
            padding: EdgeInsets.only(
              right: index == seasons.length - 1 ? 0 : 10,
            ),
            child: Material(
              color: colorScheme.onInverseSurface,
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                onTap:
                    item.seasonId == null ||
                        isCurrent ||
                        pgcController.changingSeason
                    ? null
                    : () async {
                        final changed = await pgcController.changeSeason(
                          item.seasonId!,
                        );
                        if (changed && context.mounted) {
                          onSeasonChanged();
                          _scrollToCurrent(context, controller, animate: true);
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.seasonTitle ?? '分季 ${index + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1,
                        fontSize: 13,
                        color: isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                      strutStyle: const StrutStyle(height: 1, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
