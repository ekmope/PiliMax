import 'dart:math' as math;

import 'package:PiliMax/common/widgets/flutter/text_field/controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderObject;
import 'package:flutter/services.dart';

/// Material text field backed by [RichTextEditingController].
///
/// Rich spans are supplied through the public
/// [TextEditingController.buildTextSpan] hook. A formatter keeps the
/// controller's structured items synchronized with keyboard, paste, cut and
/// IME edits, avoiding a fork of Flutter's EditableText/RenderEditable stack.
class RichTextField extends StatefulWidget {
  const RichTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.textDirection,
    this.readOnly = false,
    this.showCursor,
    this.autofocus = false,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.maxLength,
    this.maxLengthEnforcement,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorColor,
    this.keyboardAppearance,
    this.scrollPadding = const EdgeInsets.all(20),
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableInteractiveSelection,
    this.selectionControls,
    this.onTap,
    this.onTapOutside,
    this.mouseCursor,
    this.scrollController,
    this.scrollPhysics,
    this.autofillHints = const <String>[],
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.contextMenuBuilder,
    this.canRequestFocus = true,
  });

  final RichTextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final TextDirection? textDirection;
  final bool readOnly;
  final bool? showCursor;
  final bool autofocus;
  final String obscuringCharacter;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool? enabled;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final Color? cursorColor;
  final Brightness? keyboardAppearance;
  final EdgeInsets scrollPadding;
  final DragStartBehavior dragStartBehavior;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final GestureTapCallback? onTap;
  final TapRegionCallback? onTapOutside;
  final MouseCursor? mouseCursor;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final Iterable<String>? autofillHints;
  final Clip clipBehavior;
  final String? restorationId;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final bool canRequestFocus;

  @override
  State<RichTextField> createState() => RichTextFieldState();
}

class RichTextFieldState extends State<RichTextField> {
  late TextEditingValue _lastValue;
  late ScrollController _scrollController;
  late bool _ownsScrollController;
  bool _normalizingSelection = false;

  static const _caretAnimationDuration = Duration(milliseconds: 100);
  static const _caretAnimationCurve = Curves.fastOutSlowIn;

  @override
  void initState() {
    super.initState();
    _lastValue = widget.controller.value;
    _initScrollController();
    widget.controller.addListener(_handleControllerChanged);
  }

  void _initScrollController() {
    _ownsScrollController = widget.scrollController == null;
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(RichTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lastValue = widget.controller.value;
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      if (_ownsScrollController) {
        _scrollController.dispose();
      }
      _initScrollController();
    }
  }

  void _handleControllerChanged() {
    final value = widget.controller.value;
    if (_normalizingSelection || value.text != _lastValue.text) {
      _lastValue = value;
      return;
    }
    final selection = widget.controller.normalizeSelection(value.selection);
    _lastValue = value;
    if (selection == value.selection) {
      return;
    }
    _normalizingSelection = true;
    widget.controller.value = value.copyWith(selection: selection);
    _lastValue = widget.controller.value;
    _normalizingSelection = false;
  }

  /// Keeps the field and its internal scroll position visible after inserting
  /// a mention, emoji or vote node programmatically.
  void scheduleShowCaretOnScreen({bool withAnimation = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final renderEditable = _findRenderEditable(context.findRenderObject());
      final selection = widget.controller.selection;
      if (renderEditable == null || !selection.isValid) {
        return;
      }

      final position = _scrollController.position;
      final caretRect = renderEditable.getLocalRectForCaret(selection.extent);
      final isMultiline = widget.maxLines != 1;
      final editableSize = renderEditable.size;
      final double additionalOffset;
      final Offset unitOffset;
      if (isMultiline) {
        final expandedRect = Rect.fromCenter(
          center: caretRect.center,
          width: caretRect.width,
          height: math.max(
            caretRect.height,
            renderEditable.preferredLineHeight,
          ),
        );
        additionalOffset = expandedRect.height >= editableSize.height
            ? editableSize.height / 2 - expandedRect.center.dy
            : (expandedRect.bottom - editableSize.height).clamp(
                0.0,
                expandedRect.top,
              );
        unitOffset = const Offset(0, 1);
      } else {
        additionalOffset = caretRect.width >= editableSize.width
            ? editableSize.width / 2 - caretRect.center.dx
            : (caretRect.right - editableSize.width).clamp(
                0.0,
                caretRect.left,
              );
        unitOffset = const Offset(1, 0);
      }

      final target = position.allowImplicitScrolling
          ? (additionalOffset + position.pixels).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            )
          : position.pixels;
      final duration = withAnimation ? _caretAnimationDuration : Duration.zero;
      if (target != position.pixels) {
        if (withAnimation) {
          _scrollController.animateTo(
            target,
            duration: duration,
            curve: _caretAnimationCurve,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
      final revealedRect = caretRect.shift(
        unitOffset * (position.pixels - target),
      );
      renderEditable.showOnScreen(
        rect: widget.scrollPadding.inflateRect(revealedRect),
        duration: duration,
        curve: _caretAnimationCurve,
      );
    });
  }

  static RenderEditable? _findRenderEditable(RenderObject? object) {
    if (object == null) {
      return null;
    }
    if (object is RenderEditable) {
      return object;
    }
    RenderEditable? result;
    object.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  Widget _buildContextMenu(BuildContext context, EditableTextState state) {
    final items = state.contextMenuButtonItems.map((item) {
      return switch (item.type) {
        ContextMenuButtonType.copy => item.copyWith(
          onPressed: () => _copySelection(state),
        ),
        ContextMenuButtonType.cut => item.copyWith(
          onPressed: () => _cutSelection(state),
        ),
        _ => item,
      };
    }).toList();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  String? _selectionClipboardText() {
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.isCollapsed || widget.obscureText) {
      return null;
    }
    return widget.controller.getSelectionText(selection) ??
        selection.textInside(widget.controller.text);
  }

  void _copySelection([EditableTextState? state]) {
    final text = _selectionClipboardText();
    if (text == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    state?.hideToolbar(false);
    if (state != null &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.fuchsia)) {
      final selection = widget.controller.selection;
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.end,
      );
    }
  }

  void _cutSelection([EditableTextState? state]) {
    final selection = widget.controller.selection;
    if (!_canModifyText ||
        widget.obscureText ||
        !selection.isValid ||
        selection.isCollapsed) {
      return;
    }
    final text = _selectionClipboardText();
    if (text == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    final delta = TextEditingDeltaReplacement(
      oldText: widget.controller.text,
      replacementText: '',
      replacedRange: selection,
      selection: TextSelection.collapsed(offset: selection.start),
      composing: TextRange.empty,
    );
    widget.controller.applyRichDelta(delta);
    widget.onChanged?.call(widget.controller.text);
    state?.hideToolbar();
  }

  Object? _handleCopyIntent(CopySelectionTextIntent intent) {
    if (intent.collapseSelection) {
      _cutSelection();
    } else {
      _copySelection();
    }
    return null;
  }

  Object? _handleCharacterMovement(ExtendSelectionByCharacterIntent intent) {
    final value = widget.controller.value;
    final currentSelection = value.selection;
    if (!currentSelection.isValid) {
      return null;
    }

    final TextSelection proposedSelection;
    if (!currentSelection.isCollapsed && intent.collapseSelection) {
      proposedSelection = TextSelection.collapsed(
        offset: intent.forward ? currentSelection.end : currentSelection.start,
      );
    } else {
      final extentOffset = _nextCharacterOffset(
        value.text,
        currentSelection.extentOffset,
        intent.forward,
      );
      proposedSelection = intent.collapseSelection
          ? TextSelection.collapsed(offset: extentOffset)
          : currentSelection.extendTo(TextPosition(offset: extentOffset));
    }
    final selection = proposedSelection.isCollapsed
        ? widget.controller.keyboardOffset(proposedSelection)
        : widget.controller.keyboardOffsets(proposedSelection);
    widget.controller.value = value.copyWith(selection: selection);
    scheduleShowCaretOnScreen();
    return null;
  }

  static int _nextCharacterOffset(String text, int offset, bool forward) {
    final range = CharacterRange.at(text, offset);
    if (range.isEmpty) {
      if (forward) {
        range.moveNext();
      } else {
        range.moveBack();
      }
    }
    return forward
        ? range.stringBeforeLength + range.current.length
        : range.stringBeforeLength;
  }

  Object? _handleUndo(UndoTextIntent intent) {
    if (!_canModifyText) {
      return null;
    }
    final oldText = widget.controller.text;
    if (widget.controller.undoRichEdit() && oldText != widget.controller.text) {
      widget.onChanged?.call(widget.controller.text);
    }
    return null;
  }

  Object? _handleRedo(RedoTextIntent intent) {
    if (!_canModifyText) {
      return null;
    }
    final oldText = widget.controller.text;
    if (widget.controller.redoRichEdit() && oldText != widget.controller.text) {
      widget.onChanged?.call(widget.controller.text);
    }
    return null;
  }

  bool get _canModifyText =>
      !widget.readOnly &&
      (widget.enabled ?? widget.decoration?.enabled ?? true);

  @override
  Widget build(BuildContext context) {
    final maxLengthEnforcement =
        widget.maxLengthEnforcement ??
        LengthLimitingTextInputFormatter.getDefaultMaxLengthEnforcement(
          Theme.of(context).platform,
        );
    final formatters = <TextInputFormatter>[
      ...?widget.inputFormatters,
      if (widget.maxLength != null)
        LengthLimitingTextInputFormatter(
          widget.maxLength,
          maxLengthEnforcement: maxLengthEnforcement,
        ),
      _RichTextSyncFormatter(widget.controller),
    ];
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: _handleCopyIntent,
        ),
        ExtendSelectionByCharacterIntent:
            CallbackAction<ExtendSelectionByCharacterIntent>(
              onInvoke: _handleCharacterMovement,
            ),
        UndoTextIntent: CallbackAction<UndoTextIntent>(onInvoke: _handleUndo),
        RedoTextIntent: CallbackAction<RedoTextIntent>(onInvoke: _handleRedo),
      },
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        style: widget.style,
        strutStyle: widget.strutStyle,
        textAlign: widget.textAlign,
        textAlignVertical: widget.textAlignVertical,
        textDirection: widget.textDirection,
        readOnly: widget.readOnly,
        showCursor: widget.showCursor,
        autofocus: widget.autofocus,
        obscuringCharacter: widget.obscuringCharacter,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        expands: widget.expands,
        maxLength: widget.maxLength,
        maxLengthEnforcement: widget.maxLengthEnforcement,
        onChanged: widget.onChanged,
        onEditingComplete: widget.onEditingComplete,
        onSubmitted: widget.onSubmitted,
        inputFormatters: formatters,
        enabled: widget.enabled,
        cursorWidth: widget.cursorWidth,
        cursorHeight: widget.cursorHeight,
        cursorRadius: widget.cursorRadius,
        cursorColor: widget.cursorColor,
        keyboardAppearance: widget.keyboardAppearance,
        scrollPadding: widget.scrollPadding,
        dragStartBehavior: widget.dragStartBehavior,
        enableInteractiveSelection: widget.enableInteractiveSelection,
        selectionControls: widget.selectionControls,
        onTap: widget.onTap,
        onTapOutside: widget.onTapOutside,
        mouseCursor: widget.mouseCursor,
        scrollController: _scrollController,
        scrollPhysics: widget.scrollPhysics,
        autofillHints: widget.autofillHints,
        clipBehavior: widget.clipBehavior,
        restorationId: widget.restorationId,
        contextMenuBuilder: widget.contextMenuBuilder ?? _buildContextMenu,
        canRequestFocus: widget.canRequestFocus,
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }
}

class _RichTextSyncFormatter extends TextInputFormatter {
  const _RichTextSyncFormatter(this.controller);

  final RichTextEditingController controller;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => controller.reconcileUserEdit(oldValue, newValue);
}
