import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;
import 'package:hive_ce/hive.dart' show BoxEvent;

class NormalItem extends StatefulWidget {
  final String? title;
  final ValueGetter<String>? getTitle;
  final String? subtitle;
  final ValueGetter<String>? getSubtitle;
  final Widget? leading;
  final Widget Function(ThemeData theme)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;
  final bool Function()? enabled;
  final String? enabledByKey;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;

  const NormalItem({
    this.title,
    this.getTitle,
    this.subtitle,
    this.getSubtitle,
    this.leading,
    this.getTrailing,
    this.onTap,
    this.enabled,
    this.enabledByKey,
    this.contentPadding,
    this.titleStyle,
    super.key,
  }) : assert(title != null || getTitle != null);

  @override
  State<NormalItem> createState() => _NormalItemState();
}

class _NormalItemState extends State<NormalItem> {
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
  void didUpdateWidget(NormalItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabledByKey != widget.enabledByKey) {
      _setEnabledStream();
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
    late final theme = Theme.of(context);
    final enabled =
        (widget.enabled?.call() ?? true) &&
        (widget.enabledByKey == null || Pref.settingBool(widget.enabledByKey!));
    Widget? subtitle;
    if ((widget.subtitle ?? widget.getSubtitle?.call()) case final text?) {
      subtitle = Text(
        text,
        style: theme.textTheme.labelMedium!.copyWith(
          color: enabled ? theme.colorScheme.outline : theme.disabledColor,
        ),
      );
    }
    return ListTile(
      contentPadding: widget.contentPadding,
      enabled: enabled,
      onTap: widget.onTap == null || !enabled
          ? null
          : () => widget.onTap!(context, refresh),
      title: Text(
        widget.title ?? widget.getTitle!(),
        style: widget.titleStyle ?? theme.textTheme.titleMedium!,
      ),
      subtitle: subtitle,
      leading: widget.leading,
      trailing: widget.getTrailing?.call(theme),
    );
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}
