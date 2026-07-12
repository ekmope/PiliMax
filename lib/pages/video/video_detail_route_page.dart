import 'package:PiliMax/common/widgets/video_card/video_detail_hero.dart';
import 'package:PiliMax/pages/video/video_detail_args.dart';
import 'package:PiliMax/pages/video/view.dart';
import 'package:PiliMax/utils/page_utils.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Keeps the lightweight Hero target alive while incomplete launch arguments
/// are resolved, then mounts the real detail page without replacing the route.
class VideoDetailRoutePage extends StatefulWidget {
  const VideoDetailRoutePage({super.key});

  @override
  State<VideoDetailRoutePage> createState() => _VideoDetailRoutePageState();
}

class _VideoDetailRoutePageState extends State<VideoDetailRoutePage> {
  late final Map<dynamic, dynamic> _arguments = VideoDetailArgs.normalize(
    Get.arguments,
  );
  Animation<double>? _routeAnimation;
  bool _routeAnimationCompleted = false;
  bool _argumentsResolved = false;
  bool _showDetail = false;
  bool _isResolving = false;
  Object? _error;

  bool get _hasPendingLaunch =>
      _arguments[PageUtils.videoPendingLaunchKey] is VideoPendingLaunchType;

  String get _heroTag => _arguments['heroTag'] as String;

  @override
  void initState() {
    super.initState();
    if (_hasPendingLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
    } else {
      _argumentsResolved = true;
      _showDetail = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _routeAnimation = animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _routeAnimationCompleted = true;
      _tryShowDetail();
    } else {
      animation.addStatusListener(_onRouteAnimationStatus);
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeAnimationCompleted = true;
      _tryShowDetail();
    }
  }

  Future<void> _resolveArguments() async {
    if (_isResolving) {
      return;
    }
    _isResolving = true;
    try {
      await PageUtils.resolvePendingVideoLaunch(_arguments);
      if (!mounted) {
        return;
      }
      _argumentsResolved = true;
      _error = null;
      _tryShowDetail();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      _isResolving = false;
    }
  }

  void _tryShowDetail() {
    if (!mounted ||
        _showDetail ||
        !_argumentsResolved ||
        !_routeAnimationCompleted) {
      return;
    }
    setState(() => _showDetail = true);
  }

  void _retry() {
    setState(() => _error = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveArguments());
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showDetail) {
      return const VideoDetailPageV();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(child: VideoDetailHero.target(tag: _heroTag)),
          if (_error case final error?)
            SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: Get.back,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 36,
                            color: colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
