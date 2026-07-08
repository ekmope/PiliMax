import 'dart:async';

import 'package:PiliMax/plugin/pl_player/controller.dart';
import 'package:PiliMax/plugin/pl_player/models/play_status.dart';
import 'package:flutter/material.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({super.key, required this.plPlayerController});

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  StreamSubscription<PlayerStatus>? subscription;
  PlPlayerController? _boundController;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      value: widget.plPlayerController.playerStatus.isPlaying ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    _bindController();
  }

  @override
  void didUpdateWidget(covariant PlayOrPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindController();
  }

  void _bindController() {
    if (identical(_boundController, widget.plPlayerController)) {
      return;
    }
    subscription?.cancel();
    _boundController = widget.plPlayerController;
    _syncIcon(
      _boundController!.playerStatus.value,
      animate: false,
      rebuild: false,
    );
    subscription = _boundController!.playerStatus.listen(_syncIcon);
  }

  void _syncIcon(
    PlayerStatus status, {
    bool animate = true,
    bool rebuild = true,
  }) {
    if (animate) {
      if (status.isPlaying) {
        controller.forward();
      } else {
        controller.reverse();
      }
    } else {
      controller.value = status.isPlaying ? 1 : 0;
    }
    if (rebuild && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.plPlayerController.onDoubleTapCenter,
        child: Center(
          child: AnimatedIcon(
            semanticLabel: widget.plPlayerController.playerStatus.isPlaying
                ? '暂停'
                : '播放',
            progress: controller,
            icon: AnimatedIcons.play_pause,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
