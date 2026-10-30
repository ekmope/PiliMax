import 'package:PiliMax/pilimax/pages/setting/widgets/list_editor_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('shows existing invalid rules and saves corrected visible text', (
    tester,
  ) async {
    List<String>? result;
    await _openEditor(
      tester,
      initialItems: const ['good', '[broken'],
      validator: _ruleValidator,
      onResult: (value) => result = value,
    );

    expect(find.text('规则语法无效'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.byType(ListEditorDialog), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextField).at(2), 'fixed');
    await tester.pump();
    expect(find.text('规则语法无效'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, ['good', 'fixed']);
  });

  testWidgets('save rejects an invalid focused edit instead of its old value', (
    tester,
  ) async {
    List<String>? result;
    await _openEditor(
      tester,
      initialItems: const ['original'],
      validator: _ruleValidator,
      onResult: (value) => result = value,
    );

    await tester.enterText(find.byType(TextField).at(1), '[invalid');
    // Invoke the callback without moving focus so this also covers keyboard
    // submission/accessibility paths that do not cause onTapOutside first.
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
    await tester.pump();
    expect(find.byType(ListEditorDialog), findsOneWidget);
    expect(find.text('规则语法无效'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'corrected');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, ['corrected']);
  });

  testWidgets(
    'empty edits remain visible and cannot silently restore old text',
    (
      tester,
    ) async {
      List<String>? result;
      await _openEditor(
        tester,
        initialItems: const ['original'],
        onResult: (value) => result = value,
      );

      await tester.enterText(find.byType(TextField).at(1), '   ');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.text('项目不能为空'), findsOneWidget);
      expect(result, isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        '   ',
      );

      await tester.tap(find.byTooltip('删除'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending edits are compared with each other for duplicates', (
    tester,
  ) async {
    List<String>? result;
    await _openEditor(
      tester,
      initialItems: const ['first', 'second'],
      onResult: (value) => result = value,
    );

    await tester.enterText(find.byType(TextField).at(1), 'second');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('该项目已存在'), findsNWidgets(2));
    expect(result, isNull);

    await tester.enterText(find.byType(TextField).at(2), 'first');
    await tester.pump();
    expect(find.text('该项目已存在'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, ['second', 'first']);
  });

  testWidgets(
    'add errors appear inline and save includes an unadded valid rule',
    (
      tester,
    ) async {
      List<String>? result;
      await _openEditor(
        tester,
        initialItems: const [],
        validator: _ruleValidator,
        onResult: (value) => result = value,
      );

      await tester.enterText(find.byType(TextField).first, '[invalid');
      await tester.tap(find.byTooltip('添加'));
      await tester.pump();
      expect(find.text('规则语法无效'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'valid');
      await tester.pump();
      expect(find.text('规则语法无效'), findsNothing);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, ['valid']);
    },
  );

  testWidgets('deleting a row preserves errors and controllers of later rows', (
    tester,
  ) async {
    List<String>? result;
    await _openEditor(
      tester,
      initialItems: const ['valid', '[invalid'],
      validator: _ruleValidator,
      onResult: (value) => result = value,
    );

    await tester.tap(find.byTooltip('删除').first);
    await tester.pump();
    expect(find.text('规则语法无效'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '[invalid',
    );
    await tester.enterText(find.byType(TextField).at(1), 'corrected');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(result, ['corrected']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'read-only named UID entries keep their existing display values',
    (
      tester,
    ) async {
      List<String>? result;
      await _openEditor(
        tester,
        initialItems: const ['用户名 (123)'],
        allowEdit: false,
        validator: (value) => int.tryParse(value) == null ? 'UID必须是数字' : null,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onResult: (value) => result = value,
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('用户名 (123)'), findsOneWidget);
      expect(find.text('UID必须是数字'), findsNothing);
      await tester.enterText(find.byType(TextField), '456');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(result, ['用户名 (123)', '456']);
    },
  );
}

String? _ruleValidator(String value) => value.startsWith('[') ? '规则语法无效' : null;

Future<void> _openEditor(
  WidgetTester tester, {
  required List<String> initialItems,
  required ValueChanged<List<String>?> onResult,
  String? Function(String)? validator,
  bool allowEdit = true,
  List<TextInputFormatter>? inputFormatters,
}) async {
  await tester.pumpWidget(
    GetMaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              onResult(
                await showDialog<List<String>>(
                  context: context,
                  builder: (_) => ListEditorDialog(
                    title: '测试列表',
                    initialItems: initialItems,
                    validator: validator,
                    allowEdit: allowEdit,
                    inputFormatters: inputFormatters,
                  ),
                ),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}
