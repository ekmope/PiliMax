import 'package:PiliMax/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliMax/common/widgets/flutter/text_field/text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disjoint plain-text corrections preserve untouched rich metadata', () {
    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'a', range: const TextRange(start: 0, end: 1)),
        RichTextItem(
          type: RichTextType.at,
          text: '@Bob ',
          rawText: 'Bob',
          id: '42',
          range: const TextRange(start: 1, end: 6),
        ),
        RichTextItem(text: 'z', range: const TextRange(start: 6, end: 7)),
      ],
    );
    addTearDown(controller.dispose);
    final nextValue = controller.reconcileUserEdit(
      controller.value,
      const TextEditingValue(
        text: 'x@Bob y',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    controller.value = nextValue;

    expect(controller.text, 'x@Bob y');
    final mention = controller.items.singleWhere(
      (item) => item.type == RichTextType.at,
    );
    expect(mention.text, '@Bob ');
    expect(mention.rawText, 'Bob');
    expect(mention.id, '42');
    expect(mention.range, const TextRange(start: 1, end: 6));
  });

  testWidgets('keyboard movement crosses atomic rich nodes in one step', (
    tester,
  ) async {
    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
        RichTextItem(
          type: RichTextType.at,
          text: '@Bob ',
          rawText: 'Bob',
          id: '42',
          range: const TextRange(start: 1, end: 6),
        ),
        RichTextItem(text: 'Z', range: const TextRange(start: 6, end: 7)),
      ],
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    controller.selection = const TextSelection.collapsed(offset: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RichTextField(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.selection, const TextSelection.collapsed(offset: 6));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.selection, const TextSelection.collapsed(offset: 1));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 6),
    );

    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(
      controller.selection,
      const TextSelection(baseOffset: 6, extentOffset: 1),
    );
  });

  testWidgets('copy cut paste and undo preserve rich item metadata', (
    tester,
  ) async {
    Map<String, dynamic>? clipboardData;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboardData = Map<String, dynamic>.from(call.arguments as Map);
            return null;
          case 'Clipboard.getData':
            return clipboardData;
          case 'Clipboard.hasStrings':
            return <String, bool>{
              'value': (clipboardData?['text'] as String?)?.isNotEmpty ?? false,
            };
          default:
            return null;
        }
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
        RichTextItem(
          type: RichTextType.emoji,
          text: '\uFFFC',
          rawText: '[doge]',
          range: const TextRange(start: 1, end: 2),
          emote: Emote(url: '', width: 32, height: 24),
        ),
        RichTextItem(
          type: RichTextType.common,
          text: '#topic#',
          rawText: 'topic-raw',
          id: 'topic-id',
          range: const TextRange(start: 2, end: 9),
        ),
        RichTextItem(text: 'Z', range: const TextRange(start: 9, end: 10)),
      ],
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RichTextField(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();

    final context = tester.element(find.byType(RichTextField));
    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    expect(span.children!.whereType<WidgetSpan>(), hasLength(1));

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(clipboardData?['text'], '[doge]');
    expect(controller.text, 'A\uFFFC#topic#Z');

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(clipboardData?['text'], '[doge]');
    expect(controller.text, 'A#topic#Z');
    _expectTopicMetadata(controller, const TextRange(start: 1, end: 8));

    await tester.pump(const Duration(milliseconds: 600));
    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(controller.text, 'A\uFFFC#topic#Z');
    final restoredEmoji = controller.items.singleWhere(
      (item) => item.type == RichTextType.emoji,
    );
    expect(restoredEmoji.rawText, '[doge]');
    expect(restoredEmoji.range, const TextRange(start: 1, end: 2));
    expect(restoredEmoji.emote?.url, '');
    expect(restoredEmoji.emote?.width, 32);
    expect(restoredEmoji.emote?.height, 24);
    _expectTopicMetadata(controller, const TextRange(start: 2, end: 9));

    await _sendControlShortcut(
      tester,
      LogicalKeyboardKey.keyZ,
      shift: true,
    );
    await tester.pump();
    expect(controller.text, 'A#topic#Z');
    expect(
      controller.items.where((item) => item.type == RichTextType.emoji),
      isEmpty,
    );
    _expectTopicMetadata(controller, const TextRange(start: 1, end: 8));

    controller.selection = const TextSelection.collapsed(offset: 1);
    await Clipboard.setData(const ClipboardData(text: 'Q'));
    await _sendControlShortcut(tester, LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(controller.text, 'AQ#topic#Z');
    _expectTopicMetadata(controller, const TextRange(start: 2, end: 9));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('immediate undo keeps a redo entry', (tester) async {
    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
      ],
    );
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    controller.selection = const TextSelection.collapsed(offset: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RichTextField(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'AB',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, 'AB');

    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(controller.text, 'A');

    await _sendControlShortcut(
      tester,
      LogicalKeyboardKey.keyZ,
      shift: true,
    );
    await tester.pump();
    expect(controller.text, 'AB');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('read-only fields reject cut, undo, and redo shortcuts', (
    tester,
  ) async {
    final controller = RichTextEditingController(
      items: [
        RichTextItem(text: 'A', range: const TextRange(start: 0, end: 1)),
      ],
    );
    final focusNode = FocusNode();
    var readOnly = false;
    late StateSetter rebuild;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RichTextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: readOnly,
              );
            },
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'AB',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump();
    expect(controller.text, 'AB');

    rebuild(() => readOnly = true);
    await tester.pump();
    await _sendControlShortcut(tester, LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(controller.text, 'AB');

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await _sendControlShortcut(tester, LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(controller.text, 'AB');

    await _sendControlShortcut(
      tester,
      LogicalKeyboardKey.keyZ,
      shift: true,
    );
    await tester.pump();
    expect(controller.text, 'AB');
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('committing unchanged composing text finalizes its item', (
    tester,
  ) async {
    final controller = RichTextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RichTextField(
            controller: controller,
            focusNode: focusNode,
          ),
        ),
      ),
    );
    focusNode.requestFocus();
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(controller.items.single.type, RichTextType.composing);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    );
    await tester.pump();
    expect(controller.items.single.type, RichTextType.text);
    expect(controller.value.composing, TextRange.empty);
    await tester.pump(const Duration(milliseconds: 600));
  });
}

void _expectTopicMetadata(
  RichTextEditingController controller,
  TextRange range,
) {
  final topic = controller.items.singleWhere(
    (item) => item.type == RichTextType.common,
  );
  expect(topic.text, '#topic#');
  expect(topic.rawText, 'topic-raw');
  expect(topic.id, 'topic-id');
  expect(topic.range, range);
}

Future<void> _sendControlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}
