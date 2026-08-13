import 'dart:async';

import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart' hide ListTile;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hive_ce/hive.dart' show BoxEvent;

typedef SwitchChangeGuard =
    FutureOr<bool> Function(
      BuildContext context,
      bool value,
    );

class SetSwitchItem extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String setKey;
  final ValueChanged<bool>? onChanged;
  final SwitchChangeGuard? onChangeRequested;
  final bool needReboot;
  final Widget? leading;
  final void Function(BuildContext context)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;
  final bool isSplit;
  final bool Function()? enabled;
  final String? enabledByKey;

  const SetSwitchItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.setKey,
    this.onChanged,
    this.onChangeRequested,
    this.needReboot = false,
    this.leading,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    this.isSplit = false,
    this.enabled,
    this.enabledByKey,
  });

  @override
  State<SetSwitchItem> createState() => _SetSwitchItemState();
}

class _SetSwitchItemState extends State<SetSwitchItem> {
  late bool val;
  Stream<BoxEvent>? _enabledStream;

  void setVal() {
    val = Pref.settingBool(widget.setKey);
  }

  void _setEnabledStream() {
    final enabledByKey = widget.enabledByKey;
    _enabledStream = enabledByKey == null
        ? null
        : GStorage.setting.watch(key: enabledByKey);
  }

  @override
  void didUpdateWidget(SetSwitchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setKey != widget.setKey) {
      setVal();
    }
    if (oldWidget.enabledByKey != widget.enabledByKey) {
      _setEnabledStream();
    }
  }

  @override
  void initState() {
    super.initState();
    setVal();
    _setEnabledStream();
  }

  Future<void> switchChange([bool? value]) async {
    var nextValue = value ?? !val;

    final onChangeRequested = widget.onChangeRequested;
    if (onChangeRequested != null &&
        !await onChangeRequested(context, nextValue)) {
      return;
    }
    if (!mounted) return;

    if (widget.setKey == SettingBoxKey.badCertificateCallback && nextValue) {
      nextValue = await showConfirmDialog(
        context: context,
        title: const Text('确定禁用 SSL 证书验证？'),
        content: const Text('禁用容易受到中间人攻击'),
      );
      if (!mounted) return;
    }

    val = nextValue;

    if (widget.setKey == SettingBoxKey.appFontWeight) {
      await GStorage.setting.put(SettingBoxKey.appFontWeight, val ? 4 : -1);
    } else {
      await GStorage.setting.put(widget.setKey, val);
    }

    widget.onChanged?.call(val);
    if (widget.needReboot) {
      SmartDialog.showToast('重启生效');
    }
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
    final enabled = widget.enabled?.call() ?? true;
    final titleStyle =
        widget.titleStyle ??
        theme.textTheme.titleMedium!.copyWith(
          color: !enabled || (widget.onTap != null && !val)
              ? theme.colorScheme.outline
              : null,
        );
    final subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );

    final switchBtn = Transform.scale(
      scale: 0.8,
      alignment: .centerRight,
      child: Switch(
        value: val,
        onChanged: enabled ? switchChange : null,
      ),
    );

    Widget child(Widget? trailing) => ListTile(
      contentPadding: widget.contentPadding,
      enabled: enabled && (widget.onTap == null || val),
      onTap: !enabled
          ? null
          : widget.onTap == null
          ? switchChange
          : () => widget.onTap!(context),
      title: Text(widget.title, style: titleStyle),
      subtitle: widget.subtitle != null
          ? Text(widget.subtitle!, style: subTitleStyle)
          : null,
      leading: widget.leading,
      trailing: trailing,
    );

    if (widget.isSplit) {
      return Row(
        children: [
          Expanded(child: child(null)),
          SizedBox(
            height: 25,
            child: VerticalDivider(
              width: 1,
              color: theme.colorScheme.outline.withValues(alpha: .3),
            ),
          ),
          Padding(
            padding: const .only(left: 4, right: 24),
            child: switchBtn,
          ),
        ],
      );
    }

    return child(switchBtn);
  }
}
