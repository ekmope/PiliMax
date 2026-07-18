import 'package:flutter/material.dart' hide ListTile;
import 'package:flutter/material.dart' as material show ListTile;

/// Flutter [material.ListTile] with PiliMax's desktop secondary-click hooks
/// and optional horizontal safe-area padding.
class ListTile extends StatelessWidget {
  const ListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine,
    this.dense,
    this.visualDensity,
    this.shape,
    this.style,
    this.selectedColor,
    this.iconColor,
    this.textColor,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.leadingAndTrailingTextStyle,
    this.contentPadding,
    this.enabled = true,
    this.onTap,
    this.onTapUp,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSecondaryTapUp,
    this.onFocusChange,
    this.mouseCursor,
    this.selected = false,
    this.focusColor,
    this.hoverColor,
    this.splashColor,
    this.focusNode,
    this.autofocus = false,
    this.tileColor,
    this.selectedTileColor,
    this.enableFeedback,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.minTileHeight,
    this.titleAlignment,
    this.internalAddSemanticForOnTap = true,
    this.statesController,
    this.safeArea = false,
  }) : assert(isThreeLine != true || subtitle != null);

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool? isThreeLine;
  final bool? dense;
  final VisualDensity? visualDensity;
  final ShapeBorder? shape;
  final ListTileStyle? style;
  final Color? selectedColor;
  final Color? iconColor;
  final Color? textColor;
  final TextStyle? titleTextStyle;
  final TextStyle? subtitleTextStyle;
  final TextStyle? leadingAndTrailingTextStyle;
  final EdgeInsetsGeometry? contentPadding;
  final bool enabled;
  final GestureTapCallback? onTap;
  final GestureTapUpCallback? onTapUp;
  final GestureLongPressCallback? onLongPress;
  final GestureTapCallback? onSecondaryTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final ValueChanged<bool>? onFocusChange;
  final MouseCursor? mouseCursor;
  final bool selected;
  final Color? focusColor;
  final Color? hoverColor;
  final Color? splashColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color? tileColor;
  final Color? selectedTileColor;
  final bool? enableFeedback;
  final double? horizontalTitleGap;
  final double? minVerticalPadding;
  final double? minLeadingWidth;
  final double? minTileHeight;
  final ListTileTitleAlignment? titleAlignment;
  final bool internalAddSemanticForOnTap;
  final WidgetStatesController? statesController;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    EdgeInsetsGeometry? effectiveContentPadding = contentPadding;
    if (safeArea) {
      final theme = Theme.of(context);
      final safePadding =
          (effectiveContentPadding ??
                  ListTileTheme.of(context).contentPadding ??
                  (theme.useMaterial3
                      ? const EdgeInsetsDirectional.only(start: 16, end: 24)
                      : const EdgeInsets.symmetric(horizontal: 16)))
              .resolve(Directionality.of(context));
      final mediaPadding = MediaQuery.paddingOf(context);
      effectiveContentPadding = safePadding.copyWith(
        left: safePadding.left < mediaPadding.left
            ? mediaPadding.left
            : safePadding.left,
        right: safePadding.right < mediaPadding.right
            ? mediaPadding.right
            : safePadding.right,
      );
    }
    final hasExtendedCallbacks =
        onTapUp != null || onSecondaryTap != null || onSecondaryTapUp != null;
    final child = material.ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      isThreeLine: isThreeLine,
      dense: dense,
      visualDensity: visualDensity,
      shape: shape,
      style: style,
      selectedColor: selectedColor,
      iconColor: iconColor,
      textColor: textColor,
      titleTextStyle: titleTextStyle,
      subtitleTextStyle: subtitleTextStyle,
      leadingAndTrailingTextStyle: leadingAndTrailingTextStyle,
      contentPadding: effectiveContentPadding,
      enabled: enabled,
      onTap: hasExtendedCallbacks ? null : onTap,
      onLongPress: hasExtendedCallbacks ? null : onLongPress,
      onFocusChange: hasExtendedCallbacks ? null : onFocusChange,
      mouseCursor: hasExtendedCallbacks ? MouseCursor.defer : mouseCursor,
      selected: selected,
      focusColor: hasExtendedCallbacks ? null : focusColor,
      hoverColor: hasExtendedCallbacks ? null : hoverColor,
      splashColor: hasExtendedCallbacks ? null : splashColor,
      focusNode: hasExtendedCallbacks ? null : focusNode,
      autofocus: hasExtendedCallbacks ? false : autofocus,
      tileColor: tileColor,
      selectedTileColor: selectedTileColor,
      enableFeedback: hasExtendedCallbacks ? false : enableFeedback,
      horizontalTitleGap: horizontalTitleGap,
      minVerticalPadding: minVerticalPadding,
      minLeadingWidth: minLeadingWidth,
      minTileHeight: minTileHeight,
      titleAlignment: titleAlignment,
      internalAddSemanticForOnTap: hasExtendedCallbacks
          ? false
          : internalAddSemanticForOnTap,
      statesController: hasExtendedCallbacks ? null : statesController,
    );
    if (!hasExtendedCallbacks) {
      return child;
    }

    final tileTheme = ListTileTheme.of(context);
    final mouseStates = <WidgetState>{
      if (!enabled ||
          (onTap == null &&
              onTapUp == null &&
              onLongPress == null &&
              onSecondaryTap == null &&
              onSecondaryTapUp == null))
        WidgetState.disabled,
    };
    final effectiveMouseCursor =
        WidgetStateProperty.resolveAs<MouseCursor?>(mouseCursor, mouseStates) ??
        tileTheme.mouseCursor?.resolve(mouseStates) ??
        WidgetStateMouseCursor.clickable.resolve(mouseStates);
    return InkWell(
      customBorder: shape ?? tileTheme.shape,
      onTap: enabled ? onTap : null,
      onTapUp: enabled ? onTapUp : null,
      onLongPress: enabled ? onLongPress : null,
      onSecondaryTap: enabled ? onSecondaryTap : null,
      onSecondaryTapUp: enabled ? onSecondaryTapUp : null,
      onFocusChange: onFocusChange,
      mouseCursor: effectiveMouseCursor,
      canRequestFocus: enabled,
      focusNode: focusNode,
      focusColor: focusColor,
      hoverColor: hoverColor,
      splashColor: splashColor,
      autofocus: autofocus,
      enableFeedback: enableFeedback ?? tileTheme.enableFeedback ?? true,
      statesController: statesController,
      child: child,
    );
  }
}
