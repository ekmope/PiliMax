import 'dart:async';

import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/flutter/list_tile.dart';
import 'package:PiliMax/pages/setting/widgets/liquid_glass_switch.dart';
import 'package:PiliMax/pilimax/common/widgets/glass_style.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:hive_ce/hive.dart' show BoxEvent;

typedef SwitchChangeGuard = FutureOr<bool> Function(
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
  final bool liquidGlassThumb;

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
    this.liquidGlassThumb = false,
  });

  @override
  State<SetSwitchItem> createState() => _SetSwitchItemState();
}

class _SetSwitchItemState extends State<SetSwitchItem> {
  late bool val;
  Stream<BoxEvent>? _settingsStream;
  bool _changeInProgress = false;

  void setVal() {
    val = Pref.settingBool(widget.setKey);
  }

  void _watchSettings() {
    final enabledByKey = widget.enabledByKey;
    _settingsStream = widget.liquidGlassThumb
        ? GStorage.setting.watch().where(
            (event) =>
                event.key == enabledByKey ||
                event.key == SettingBoxKey.glassStyle,
          )
        : enabledByKey == null
        ? null
        : GStorage.setting.watch(key: enabledByKey);
  }

  @override
  void didUpdateWidget(SetSwitchItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setKey != widget.setKey) {
      setVal();
    }
    if (oldWidget.enabledByKey != widget.enabledByKey ||
        oldWidget.liquidGlassThumb != widget.liquidGlassThumb) {
      _watchSettings();
    }
  }

  @override
  void initState() {
    super.initState();
    setVal();
    _watchSettings();
  }

  Future<void> switchChange([bool? value]) async {
    final guardConcurrentChanges = widget.liquidGlassThumb;
    if (guardConcurrentChanges && _changeInProgress) return;
    if (guardConcurrentChanges) _changeInProgress = true;
    try {
      await _persistChange(value ?? !val);
    } finally {
      if (guardConcurrentChanges) _changeInProgress = false;
    }
  }

  Future<void> _persistChange(bool nextValue) async {
    final setKey = widget.setKey;
    final waitForPersistence = widget.liquidGlassThumb;
    final onChanged = widget.onChanged;
    final needReboot = widget.needReboot;
    final onChangeRequested = widget.onChangeRequested;
    if (onChangeRequested != null &&
        !await onChangeRequested(context, nextValue)) {
      return;
    }
    if (!mounted || widget.setKey != setKey) return;

    if (setKey == SettingBoxKey.badCertificateCallback && nextValue) {
      nextValue = await showConfirmDialog(
        context: context,
        title: const Text('确定禁用 SSL 证书验证？'),
        content: const Text('禁用容易受到中间人攻击'),
      );
      if (!nextValue || !mounted || widget.setKey != setKey) return;
    }

    if (waitForPersistence && widget.enabled?.call() == false) return;
    if (!waitForPersistence) val = nextValue;
    await GStorage.setting.put(setKey, nextValue);
    if (waitForPersistence && mounted && widget.setKey == setKey) {
      val = nextValue;
    }
    onChanged?.call(nextValue);
    if (needReboot) {
      SmartDialog.showToast('重启生效');
    }
    if (mounted && widget.setKey == setKey) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsStream = _settingsStream;
    if (settingsStream != null) {
      return StreamBuilder<BoxEvent>(
        stream: settingsStream,
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

    final usesGlassThumb =
        widget.liquidGlassThumb && Pref.glassStyle == GlassStyle.liquid;
    final mergeSwitchSemantics =
        usesGlassThumb && !widget.isSplit && widget.onTap == null;
    const switchScale = 0.8;
    final switchBtn = usesGlassThumb
        ? LiquidGlassSwitch(
            value: val,
            onChanged: enabled ? switchChange : null,
            semanticLabel: mergeSwitchSemantics ? null : widget.title,
            visualScale: switchScale,
          )
        : Transform.scale(
            scale: switchScale,
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
      internalAddSemanticForOnTap: !mergeSwitchSemantics,
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

    final tile = child(switchBtn);
    return mergeSwitchSemantics ? MergeSemantics(child: tile) : tile;
  }
}
