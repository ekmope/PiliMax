import 'dart:async';

import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/models/common/enum_with_label.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;
import 'package:hive_ce/hive.dart' show BoxEvent;

typedef PopupMenuItemSelected<T> = void Function(
  T value,
  VoidCallback setState,
);

List<PopupMenuEntry<T>> enumItemBuilder<T extends EnumWithLabel>(
  Iterable<T> items,
) => items.map((e) => PopupMenuItem(value: e, child: Text(e.label))).toList();

enum DescPosType { subtitle, title, trailing }

class PopupListTile<T> extends StatefulWidget {
  const PopupListTile({
    super.key,
    this.dense,
    this.safeArea = true,
    this.enabled = true,
    this.enabledByKey,
    this.allowSameSelection = false,
    this.leading,
    required this.title,
    this.descPosType = .subtitle,
    required this.value,
    required this.itemBuilder,
    required this.onSelected,
    this.titleStyle,
    this.descStyle,
  });

  final bool? dense;
  final bool safeArea;
  final bool enabled;
  final String? enabledByKey;
  final bool allowSameSelection;
  final Widget? leading;
  final Widget title;

  final DescPosType descPosType;
  final ValueGetter<(T, String)> value;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final TextStyle? titleStyle;
  final TextStyle? descStyle;

  @override
  State<PopupListTile<T>> createState() => _PopupListTileState<T>();
}

class _PopupListTileState<T> extends State<PopupListTile<T>> {
  final _key = PlatformUtils.isDesktop ? null : GlobalKey();
  Stream<BoxEvent>? _enabledStream;

  void _setEnabledStream() {
    final enabledByKey = widget.enabledByKey;
    _enabledStream = enabledByKey == null
        ? null
        : GStorage.setting.watch(key: enabledByKey);
  }

  @override
  void initState() {
    super.initState();
    _setEnabledStream();
  }

  @override
  void didUpdateWidget(PopupListTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabledByKey != widget.enabledByKey) {
      _setEnabledStream();
    }
  }

  void _showButtonMenu(
    BuildContext menuContext,
    TapUpDetails details,
    T value,
  ) {
    final thisOffset = details.globalPosition - details.localPosition;
    final double dx;
    if (PlatformUtils.isDesktop) {
      dx = details.globalPosition.dx + 1;
    } else {
      final thisBox = context.findRenderObject();
      final titleBox = _key!.currentContext!.findRenderObject() as RenderBox;
      final titleOffset = titleBox.localToGlobal(.zero, ancestor: thisBox);
      dx = thisOffset.dx + titleOffset.dx;
    }
    showMenu<T>(
      context: menuContext,
      position: RelativeRect.fromLTRB(dx, thisOffset.dy + 5, dx, 0),
      items: widget.itemBuilder(menuContext),
      initialValue: value,
      requestFocus: false,
    ).then<void>((newValue) {
      if (!mounted) return;
      if (newValue == null ||
          (newValue == value && !widget.allowSameSelection)) {
        return;
      }
      widget.onSelected(newValue, _refresh);
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabledStream = _enabledStream;
    if (enabledStream != null) {
      return StreamBuilder<BoxEvent>(
        stream: enabledStream,
        builder: (context, _) => _build(context),
      );
    }
    return _build(context);
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        widget.enabled &&
        (widget.enabledByKey == null || Pref.settingBool(widget.enabledByKey!));
    final (value, descStr) = widget.value();
    Widget title = KeyedSubtree(key: _key, child: widget.title);
    Widget? subtitle;
    Widget? trailing;
    final desc = Text(
      descStr,
      style: (widget.descStyle ?? theme.textTheme.labelMedium!).copyWith(
        color: enabled ? theme.colorScheme.secondary : theme.disabledColor,
      ),
    );
    switch (widget.descPosType) {
      case DescPosType.subtitle:
        subtitle = desc;
      case DescPosType.title:
        title = Row(
          spacing: 12,
          mainAxisSize: .min,
          children: [title, desc],
        );
      case DescPosType.trailing:
        trailing = desc;
    }
    final menuTheme = theme.copyWith(highlightColor: Colors.transparent);
    return Theme(
      data: menuTheme,
      child: Builder(
        builder: (menuContext) => Theme(
          data: theme,
          child: ListTile(
            dense: widget.dense,
            safeArea: widget.safeArea,
            enabled: enabled,
            onTapUp: enabled
                ? (details) => _showButtonMenu(
                    menuContext,
                    details,
                    value,
                  )
                : null,
            leading: widget.leading,
            title: title,
            titleTextStyle: widget.titleStyle ?? theme.textTheme.titleMedium,
            subtitle: subtitle,
            trailing: trailing,
          ),
        ),
      ),
    );
  }
}
