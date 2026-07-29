import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/services/pip_transition_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Lightweight PiP content that avoids mounting a second full player tree.
class PipMiniVideoContent extends StatelessWidget {
  const PipMiniVideoContent({
    super.key,
    required this.plPlayerController,
    required this.transition,
    this.danmuWidget,
  });

  final PlPlayerController plPlayerController;
  final PipTransitionCoordinator transition;
  final Widget? danmuWidget;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Obx(() {
            final videoController = plPlayerController.videoController;
            if (videoController == null) return const SizedBox.shrink();

            final videoFit = plPlayerController.videoFit.value;
            return Transform.flip(
              flipX: plPlayerController.flipX.value,
              flipY: plPlayerController.flipY.value,
              child: FittedBox(
                fit: videoFit.boxFit,
                clipBehavior: Clip.hardEdge,
                child: SimpleVideo(
                  controller: videoController,
                  aspectRatio: videoFit.aspectRatio,
                ),
              ),
            );
          }),
        ),
        if (danmuWidget != null)
          ListenableBuilder(
            listenable: transition,
            builder: (_, _) => transition.phase == PipPhase.active
                ? IgnorePointer(child: danmuWidget)
                : const SizedBox.shrink(),
          ),
        Obx(
          () => plPlayerController.isBuffering.value
              ? const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white70,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
