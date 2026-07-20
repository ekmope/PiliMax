import 'package:PiliMax/utils/platform_utils.dart';
import 'package:flutter/material.dart';

typedef SelectionTextContextMenuBuilder = Widget Function(
  BuildContext context,
  SelectableRegionState selectableRegionState,
  String? selectedText,
);

class SelectionText extends StatefulWidget {
  const SelectionText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
  }) : textSpan = null;

  const SelectionText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final SelectionTextContextMenuBuilder contextMenuBuilder;

  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
    String? selectedText,
  ) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }

  @override
  State<SelectionText> createState() => _SelectionTextState();
}

class _SelectionTextState extends State<SelectionText> {
  String? _selectedText;

  void _onSelectionChanged(SelectedContent? content) {
    final selectedText = content?.plainText;
    if (selectedText == _selectedText || !mounted) return;
    setState(() => _selectedText = selectedText);
  }

  @override
  Widget build(BuildContext context) {
    final textSpan = widget.textSpan;
    return SelectionArea(
      onSelectionChanged: _onSelectionChanged,
      contextMenuBuilder: (context, selectableRegionState) =>
          widget.contextMenuBuilder(
            context,
            selectableRegionState,
            _selectedText,
          ),
      child: Text.rich(
        TextSpan(
          text: widget.data,
          children: textSpan == null ? null : <InlineSpan>[textSpan],
        ),
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}

Widget selectableText(
  String text, {
  TextStyle? style,
}) {
  if (PlatformUtils.isDesktop) {
    return SelectionArea(
      child: Text(
        style: style,
        text,
      ),
    );
  }
  return SelectableText(
    style: style,
    text,
    scrollPhysics: const NeverScrollableScrollPhysics(),
  );
}

Widget selectableRichText(
  TextSpan textSpan, {
  TextStyle? style,
}) {
  if (PlatformUtils.isDesktop) {
    return SelectionArea(
      child: Text.rich(
        style: style,
        textSpan,
      ),
    );
  }
  return SelectableText.rich(
    style: style,
    textSpan,
    scrollPhysics: const NeverScrollableScrollPhysics(),
  );
}
