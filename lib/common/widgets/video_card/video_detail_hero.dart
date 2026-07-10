import 'package:PiliMax/common/style.dart';

import 'package:flutter/material.dart';

class VideoDetailHero extends StatelessWidget {
  const VideoDetailHero.source({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = Style.mdRadius,
  }) : _isDetailTarget = false;

  const VideoDetailHero.target({
    super.key,
    required this.tag,
    required this.child,
  }) : borderRadius = BorderRadius.zero,
       _isDetailTarget = true;

  final Object tag;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final bool _isDetailTarget;

  static Tween<Rect?> _createRectTween(Rect? begin, Rect? end) =>
      MaterialRectArcTween(begin: begin, end: end);

  static Widget _flightShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final fromHero = fromHeroContext.widget as Hero;
    final toHero = toHeroContext.widget as Hero;
    final fromChild = _heroChild(fromHero.child);
    final toChild = _heroChild(toHero.child);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final progress = switch (flightDirection) {
          HeroFlightDirection.push => animation.value,
          HeroFlightDirection.pop => 1 - animation.value,
        };
        final radius =
            BorderRadiusGeometry.lerp(
              fromChild.borderRadius,
              toChild.borderRadius,
              progress,
            ) ??
            toChild.borderRadius;
        final toOpacity = _interval(progress, 0.18, 1);

        return ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: 1 - toOpacity,
                child: _fillFlightBounds(fromChild.child),
              ),
              Opacity(
                opacity: toOpacity,
                child: _fillFlightBounds(toChild.child),
              ),
            ],
          ),
        );
      },
    );
  }

  static _VideoDetailHeroChild _heroChild(Widget child) {
    if (child is _VideoDetailHeroChild) {
      return child;
    }
    return _VideoDetailHeroChild(
      borderRadius: BorderRadius.zero,
      isDetailTarget: false,
      child: child,
    );
  }

  static Widget _fillFlightBounds(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
        height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
        child: child,
      ),
    );
  }

  static double _interval(double value, double begin, double end) {
    if (value <= begin) {
      return 0;
    }
    if (value >= end) {
      return 1;
    }
    return Curves.easeOutCubic.transform((value - begin) / (end - begin));
  }

  Widget _buildPlaceholder(BuildContext context, Size heroSize, Widget child) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      curve: Curves.linear,
      reverseCurve: Curves.linear,
      createRectTween: _createRectTween,
      flightShuttleBuilder: _flightShuttleBuilder,
      transitionOnUserGestures: true,
      placeholderBuilder: _buildPlaceholder,
      child: _VideoDetailHeroChild(
        borderRadius: borderRadius,
        isDetailTarget: _isDetailTarget,
        child: child,
      ),
    );
  }
}

class VideoDetailHeroShell extends StatelessWidget {
  const VideoDetailHeroShell({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mediaSize = MediaQuery.sizeOf(context);
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mediaSize.width;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mediaSize.height;
          final playerHeight = (width / Style.aspectRatio).clamp(
            height * 0.26,
            height * 0.46,
          ).toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: playerHeight,
                width: double.infinity,
                child: const ColoredBox(color: Colors.black),
              ),
              if (height > 120) _TabSkeleton(colorScheme: colorScheme),
              if (height > 180)
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AuthorSkeleton(colorScheme: colorScheme),
                        const SizedBox(height: 14),
                        _LineSkeleton(colorScheme: colorScheme, width: 0.92),
                        const SizedBox(height: 8),
                        _LineSkeleton(colorScheme: colorScheme, width: 0.68),
                        const SizedBox(height: 18),
                        for (int index = 0; index < 4; index++) ...[
                          _RecommendSkeleton(colorScheme: colorScheme),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VideoDetailHeroChild extends StatelessWidget {
  const _VideoDetailHeroChild({
    required this.borderRadius,
    required this.isDetailTarget,
    required this.child,
  });

  final BorderRadiusGeometry borderRadius;
  final bool isDetailTarget;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isDetailTarget) {
      return child;
    }
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}

class _TabSkeleton extends StatelessWidget {
  const _TabSkeleton({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          _PillSkeleton(colorScheme: colorScheme, width: 46),
          const SizedBox(width: 18),
          _PillSkeleton(colorScheme: colorScheme, width: 46, alpha: 0.16),
        ],
      ),
    );
  }
}

class _AuthorSkeleton extends StatelessWidget {
  const _AuthorSkeleton({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _skeletonColor(colorScheme),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineSkeleton(colorScheme: colorScheme, width: 0.38, height: 12),
              const SizedBox(height: 7),
              _LineSkeleton(colorScheme: colorScheme, width: 0.24, height: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecommendSkeleton extends StatelessWidget {
  const _RecommendSkeleton({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: AspectRatio(
            aspectRatio: Style.aspectRatio,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.76),
                borderRadius: Style.mdRadius,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LineSkeleton(colorScheme: colorScheme, width: 0.94),
              const SizedBox(height: 8),
              _LineSkeleton(colorScheme: colorScheme, width: 0.72),
              const SizedBox(height: 12),
              _LineSkeleton(colorScheme: colorScheme, width: 0.46, height: 10),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineSkeleton extends StatelessWidget {
  const _LineSkeleton({
    required this.colorScheme,
    required this.width,
    this.height = 13,
  });

  final ColorScheme colorScheme;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: width,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: _skeletonColor(colorScheme),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

class _PillSkeleton extends StatelessWidget {
  const _PillSkeleton({
    required this.colorScheme,
    required this.width,
    this.alpha = 0.28,
  });

  final ColorScheme colorScheme;
  final double width;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 22,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

Color _skeletonColor(ColorScheme colorScheme) =>
    colorScheme.onSurfaceVariant.withValues(alpha: 0.18);
