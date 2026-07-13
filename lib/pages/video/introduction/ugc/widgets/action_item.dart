import 'package:PiliMax/common/widgets/custom_arc.dart';
import 'package:PiliMax/common/widgets/loading_widget/button_loading.dart';
import 'package:PiliMax/pages/video/video_layout_metrics.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

class ActionItem extends StatelessWidget {
  const ActionItem({
    super.key,
    required this.icon,
    this.selectIcon,
    this.onTap,
    this.onLongPress,
    this.text,
    this.selectStatus = false,
    required this.semanticsLabel,
    this.expand = true,
    this.animation,
    this.onStartTriple,
    this.onCancelTriple,
    this.isLoading = false,
  }) : assert(!selectStatus || selectIcon != null),
       _isThumbsUp = onStartTriple != null;

  final Icon icon;
  final Icon? selectIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? text;
  final bool selectStatus;
  final String semanticsLabel;
  final bool expand;
  final Animation<double>? animation;
  final VoidCallback? onStartTriple;
  final void Function([bool])? onCancelTriple;
  final bool isLoading;
  final bool _isThumbsUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    late final primary = !expand && colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final isInteractive = !isLoading;
    Widget child = isLoading
        ? buttonLoadingIndicator(
            size: 16,
            strokeWidth: 1.8,
            color: selectStatus ? primary : icon.color ?? colorScheme.outline,
          )
        : Icon(
            selectStatus ? selectIcon!.icon! : icon.icon,
            size: VideoDetailLayoutMetrics.actionIconGlyphExtent,
            color: selectStatus ? primary : icon.color ?? colorScheme.outline,
            semanticLabel: semanticsLabel,
          );

    if (animation != null) {
      child = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation!,
            builder: (context, child) => Arc(
              size: VideoDetailLayoutMetrics.actionIconBoxExtent,
              color: primary,
              progress: -animation!.value,
            ),
          ),
          child,
        ],
      );
    } else {
      child = SizedBox.square(
        dimension: VideoDetailLayoutMetrics.actionIconBoxExtent,
        child: child,
      );
    }

    child = Material(
      type: .transparency,
      child: InkWell(
        borderRadius: const .all(.circular(6)),
        onTap: _isThumbsUp || !isInteractive ? null : onTap,
        onLongPress: _isThumbsUp || !isInteractive ? null : onLongPress,
        onSecondaryTap: PlatformUtils.isMobile || _isThumbsUp || !isInteractive
            ? null
            : onLongPress,
        onTapDown: _isThumbsUp && isInteractive
            ? (_) => onStartTriple!()
            : null,
        onTapUp: _isThumbsUp && isInteractive
            ? (_) => onCancelTriple!(true)
            : null,
        onTapCancel: _isThumbsUp && isInteractive ? onCancelTriple : null,
        child: expand
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [child, _buildText(theme)],
              )
            : child,
      ),
    );
    return expand ? Expanded(child: child) : child;
  }

  Widget _buildText(ThemeData theme) {
    final hasText = text != null;
    final child = Text(
      hasText ? text! : '-',
      key: hasText ? ValueKey(text!) : null,
      style: TextStyle(
        color: selectStatus
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        fontSize: theme.textTheme.labelSmall!.fontSize,
      ),
    );
    if (hasText) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: child,
      );
    }
    return child;
  }
}
