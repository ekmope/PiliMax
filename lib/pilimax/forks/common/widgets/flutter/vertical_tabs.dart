import 'package:flutter/material.dart';

class VerticalTab extends StatelessWidget {
  const VerticalTab({
    super.key,
    this.text,
    this.icon,
    this.iconMargin,
    this.width,
    this.child,
  }) : assert(text != null || child != null || icon != null),
       assert(text == null || child == null);

  final String? text;
  final Widget? icon;
  final EdgeInsetsGeometry? iconMargin;
  final double? width;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final label =
        child ??
        (text == null
            ? const SizedBox.shrink()
            : Text(text!, style: const TextStyle(fontSize: 15)));
    return SizedBox(
      width: width ?? (icon == null ? 51 : 72),
      child: Center(
        child: icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        iconMargin ?? const EdgeInsets.symmetric(horizontal: 2),
                    child: icon,
                  ),
                  Flexible(child: label),
                ],
              ),
      ),
    );
  }
}

/// A compact vertical counterpart to Flutter's [TabBar].
///
/// It deliberately owns only the vertical layout. Selection and animation are
/// still driven by the public [TabController] shared with [TabBarView].
class VerticalTabBar extends StatefulWidget {
  const VerticalTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.indicatorColor,
    this.indicatorWeight = 2,
    this.indicatorSize,
    this.dividerColor,
    this.dividerWidth,
    this.labelColor,
    this.labelStyle,
    this.labelPadding,
    this.unselectedLabelColor,
    this.unselectedLabelStyle,
    this.onTap,
    this.physics,
  }) : assert(indicatorWeight > 0);

  final List<Widget> tabs;
  final TabController? controller;
  final bool isScrollable;
  final EdgeInsetsGeometry? padding;
  final Color? indicatorColor;
  final double indicatorWeight;
  final TabBarIndicatorSize? indicatorSize;
  final Color? dividerColor;
  final double? dividerWidth;
  final Color? labelColor;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? labelPadding;
  final Color? unselectedLabelColor;
  final TextStyle? unselectedLabelStyle;
  final ValueChanged<int>? onTap;
  final ScrollPhysics? physics;

  @override
  State<VerticalTabBar> createState() => _VerticalTabBarState();
}

class _VerticalTabBarState extends State<VerticalTabBar> {
  TabController? _controller;

  void _updateController() {
    final next = widget.controller ?? DefaultTabController.maybeOf(context);
    assert(next != null, 'VerticalTabBar requires a TabController.');
    if (next == _controller) {
      return;
    }
    _controller?.animation?.removeListener(_handleControllerChanged);
    _controller = next;
    _controller?.animation?.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateController();
  }

  @override
  void didUpdateWidget(VerticalTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _updateController();
    }
  }

  Widget _buildTab(BuildContext context, int index) {
    final theme = Theme.of(context);
    final selected = _controller!.index == index;
    final color = selected
        ? widget.labelColor ?? theme.colorScheme.primary
        : widget.unselectedLabelColor ?? theme.colorScheme.onSurfaceVariant;
    final style =
        (selected
                ? widget.labelStyle
                : widget.unselectedLabelStyle ?? widget.labelStyle)
            ?.copyWith(color: color);
    final border = selected
        ? Border(
            right: BorderSide(
              color: widget.indicatorColor ?? theme.colorScheme.primary,
              width: widget.indicatorWeight,
            ),
          )
        : null;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () {
          if (_controller!.index != index) {
            _controller!.animateTo(index);
          }
          widget.onTap?.call(index);
        },
        child: DefaultTextStyle.merge(
          style: style ?? TextStyle(color: color),
          child: IconTheme.merge(
            data: IconThemeData(color: color),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding:
                  widget.labelPadding ??
                  const EdgeInsets.symmetric(vertical: 7, horizontal: 5),
              decoration: BoxDecoration(border: border),
              child: widget.tabs[index],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(_controller!.length == widget.tabs.length);
    final children = List.generate(
      widget.tabs.length,
      (index) => _buildTab(context, index),
    );
    Widget result = widget.isScrollable
        ? ListView(
            padding: widget.padding,
            physics: widget.physics,
            shrinkWrap: true,
            children: children,
          )
        : Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: Column(
              children: children
                  .map((child) => Expanded(child: child))
                  .toList(),
            ),
          );
    if ((widget.dividerWidth ?? 1) > 0) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              width: widget.dividerWidth ?? 1,
              color: widget.dividerColor ?? Theme.of(context).dividerColor,
            ),
          ),
        ),
        child: result,
      );
    }
    return result;
  }

  @override
  void dispose() {
    _controller?.animation?.removeListener(_handleControllerChanged);
    super.dispose();
  }
}
