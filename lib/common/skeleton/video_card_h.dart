import 'package:PiliMax/common/skeleton/skeleton.dart';
import 'package:PiliMax/common/widgets/video_card/video_card_h_layout_metrics.dart';
import 'package:flutter/material.dart';

class VideoCardHSkeleton extends StatelessWidget {
  const VideoCardHSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onInverseSurface;
    return Skeleton(
      child: SizedBox(
        height: VideoCardHLayoutMetrics.itemHeight,
        child: Padding(
          padding: VideoCardHLayoutMetrics.contentPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: VideoCardHLayoutMetrics.thumbnailWidth,
                height: VideoCardHLayoutMetrics.thumbnailHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: VideoCardHLayoutMetrics.thumbnailBorderRadius,
                  ),
                ),
              ),
              const SizedBox(width: VideoCardHLayoutMetrics.contentGap),
              Expanded(
                child: Padding(
                  padding: const .fromLTRB(0, 4, 6, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        color: color,
                        width: 200,
                        height: 11,
                        margin: const EdgeInsets.only(bottom: 5),
                      ),
                      Container(
                        color: color,
                        width: 150,
                        height: 13,
                      ),
                      const Spacer(),
                      Container(
                        color: color,
                        width: 100,
                        height: 13,
                        margin: const EdgeInsets.only(bottom: 5),
                      ),
                      Row(
                        children: [
                          Container(
                            color: color,
                            width: 40,
                            height: 13,
                            margin: const EdgeInsets.only(right: 8),
                          ),
                          Container(color: color, width: 40, height: 13),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
