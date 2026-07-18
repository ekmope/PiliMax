import 'package:flutter/material.dart' as flutter;
import 'package:flutter/rendering.dart' show RenderObject, RenderParagraph;

/// Text with PiliMax's compact "查看更多" overflow affordance.
///
/// Rendering, selection, semantics and inline widgets are delegated to
/// Flutter's public [flutter.Text] implementation. Only overflow detection and
/// the optional action row remain app-owned.
class Text extends flutter.StatefulWidget {
  const Text(
    String this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    required this.primary,
    this.onShowMore,
  }) : textSpan = null;

  const Text.rich(
    flutter.InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
    required this.primary,
    this.onShowMore,
  }) : data = null;

  final String? data;
  final flutter.InlineSpan? textSpan;
  final flutter.TextStyle? style;
  final flutter.StrutStyle? strutStyle;
  final flutter.TextAlign? textAlign;
  final flutter.TextDirection? textDirection;
  final flutter.Locale? locale;
  final bool? softWrap;
  final flutter.TextOverflow? overflow;
  final flutter.TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final flutter.TextWidthBasis? textWidthBasis;
  final flutter.TextHeightBehavior? textHeightBehavior;
  final flutter.Color? selectionColor;
  final flutter.Color primary;
  final flutter.VoidCallback? onShowMore;

  @override
  flutter.State<Text> createState() => _TextState();
}

class _TextState extends flutter.State<Text> {
  final _textKey = flutter.GlobalKey();
  bool _didOverflow = false;

  void _checkOverflow() {
    final root = _textKey.currentContext?.findRenderObject();
    final paragraph = _findParagraph(root);
    final didOverflow = paragraph?.didExceedMaxLines ?? false;
    if (mounted && didOverflow != _didOverflow) {
      setState(() => _didOverflow = didOverflow);
    }
  }

  static RenderParagraph? _findParagraph(RenderObject? object) {
    if (object == null) {
      return null;
    }
    if (object is RenderParagraph) {
      return object;
    }
    RenderParagraph? result;
    object.visitChildren((child) {
      result ??= _findParagraph(child);
    });
    return result;
  }

  @override
  flutter.Widget build(flutter.BuildContext context) {
    flutter.WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOverflow();
    });
    final text = widget.textSpan == null
        ? flutter.Text(
            widget.data!,
            key: _textKey,
            style: widget.style,
            strutStyle: widget.strutStyle,
            textAlign: widget.textAlign,
            textDirection: widget.textDirection,
            locale: widget.locale,
            softWrap: widget.softWrap,
            overflow: widget.overflow,
            textScaler: widget.textScaler,
            maxLines: widget.maxLines,
            semanticsLabel: widget.semanticsLabel,
            textWidthBasis: widget.textWidthBasis,
            textHeightBehavior: widget.textHeightBehavior,
            selectionColor: widget.selectionColor,
          )
        : flutter.Text.rich(
            widget.textSpan!,
            key: _textKey,
            style: widget.style,
            strutStyle: widget.strutStyle,
            textAlign: widget.textAlign,
            textDirection: widget.textDirection,
            locale: widget.locale,
            softWrap: widget.softWrap,
            overflow: widget.overflow,
            textScaler: widget.textScaler,
            maxLines: widget.maxLines,
            semanticsLabel: widget.semanticsLabel,
            textWidthBasis: widget.textWidthBasis,
            textHeightBehavior: widget.textHeightBehavior,
            selectionColor: widget.selectionColor,
          );

    if (!_didOverflow) {
      return text;
    }
    final more = flutter.Text(
      '查看更多',
      style: flutter.DefaultTextStyle.of(
        context,
      ).style.merge(widget.style).copyWith(color: widget.primary),
    );
    return flutter.Column(
      mainAxisSize: flutter.MainAxisSize.min,
      crossAxisAlignment: flutter.CrossAxisAlignment.start,
      children: [
        text,
        if (widget.onShowMore == null)
          more
        else
          flutter.GestureDetector(
            behavior: flutter.HitTestBehavior.opaque,
            onTap: widget.onShowMore,
            child: more,
          ),
      ],
    );
  }
}
