import 'dart:async';

import 'package:PiliMax/pages/storage_recovery/view.dart';
import 'package:PiliMax/utils/android/android_mmkv_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AndroidMmkvMigrationException failure({
    AndroidMmkvRecoveryAction action = AndroidMmkvRecoveryAction.resetBox,
  }) => AndroidMmkvMigrationException(
    boxName: 'setting',
    phase: AndroidMmkvMigrationPhase.metadata,
    code: 'invalid_migration_marker',
    recoveryAction: action,
  );

  testWidgets('retry-only failure does not offer destructive recovery', (
    tester,
  ) async {
    var retryCount = 0;
    final controller = AndroidMmkvRecoveryController(
      failure: failure(action: AndroidMmkvRecoveryAction.retry),
      retryStorage: () async {
        retryCount++;
      },
      resetStorage: (_) async => fail('reset must not be offered'),
      closeApplication: () {},
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));

    expect(find.text('存储数据需要修复'), findsOneWidget);
    expect(find.text('备份并重置此数据'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pump();
    expect(retryCount, 1);
    await expectLater(controller.recovered, completes);
  });

  testWidgets('reset requires confirmation before backup and retry', (
    tester,
  ) async {
    var resetCount = 0;
    var retryCount = 0;
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () async {
        retryCount++;
      },
      resetStorage: (failure) async {
        expect(failure.boxName, 'setting');
        resetCount++;
      },
      closeApplication: () {},
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));
    await tester.tap(find.text('备份并重置此数据'));
    await tester.pumpAndSettle();

    expect(find.text('确认重置存储数据？'), findsOneWidget);
    expect(resetCount, 0);
    await tester.tap(find.widgetWithText(FilledButton, '备份并重置'));
    await tester.pumpAndSettle();

    expect(resetCount, 1);
    expect(retryCount, 1);
    await expectLater(controller.recovered, completes);
  });

  testWidgets('retry is single-flight and disables both actions while busy', (
    tester,
  ) async {
    final retryCompleter = Completer<void>();
    var retryCount = 0;
    var closeCount = 0;
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () {
        retryCount++;
        return retryCompleter.future;
      },
      resetStorage: (_) => Future<void>.value(),
      closeApplication: () => closeCount++,
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pump();

    final retryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '重试'),
    );
    final resetButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '备份并重置此数据'),
    );
    expect(retryButton.onPressed, isNull);
    expect(resetButton.onPressed, isNull);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '关闭应用'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    expect(closeCount, 0);
    await controller.retry();
    expect(retryCount, 1);

    retryCompleter.complete();
    await tester.pump();
    await expectLater(controller.recovered, completes);
  });

  testWidgets('a repeated migration failure replaces the displayed fault', (
    tester,
  ) async {
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () => Future<void>.error(
        AndroidMmkvMigrationException(
          boxName: 'video',
          phase: AndroidMmkvMigrationPhase.availability,
          code: 'store_unavailable_with_state',
          recoveryAction: AndroidMmkvRecoveryAction.retry,
        ),
      ),
      resetStorage: (_) => Future<void>.value(),
      closeApplication: () {},
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));
    await tester.tap(find.widgetWithText(FilledButton, '重试'));
    await tester.pumpAndSettle();

    expect(find.textContaining('故障区域：video'), findsOneWidget);
    expect(find.text('备份并重置此数据'), findsNothing);
    expect(find.text('存储仍不可用，请稍后重试。'), findsOneWidget);
  });

  testWidgets('close action is always available', (tester) async {
    var closeCount = 0;
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () => Completer<void>().future,
      resetStorage: (_) => Future<void>.value(),
      closeApplication: () => closeCount++,
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));
    await tester.tap(find.text('关闭应用'));

    expect(closeCount, 1);
  });

  testWidgets('fatal retry failure hides every destructive action', (
    tester,
  ) async {
    final reports = <String>[];
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () => Future<void>.error(StateError('internal detail')),
      resetStorage: (_) => Future<void>.value(),
      closeApplication: () {},
      reportCallbackError: (_, _, operation) => reports.add(operation),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));
    await tester.tap(find.text('备份并重置此数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '备份并重置'));
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsNothing);
    expect(find.text('备份并重置此数据'), findsNothing);
    expect(find.textContaining('存储修复已完成'), findsOneWidget);
    expect(find.text('关闭应用'), findsOneWidget);
    expect(reports, ['retry']);
  });

  testWidgets('small landscape view with large text remains scrollable', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(640, 280)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );
    final controller = AndroidMmkvRecoveryController(
      failure: failure(),
      retryStorage: () => Completer<void>().future,
      resetStorage: (_) => Future<void>.value(),
      closeApplication: () {},
      reportCallbackError: (_, _, _) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(AndroidMmkvRecoveryApp(controller: controller));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('关闭应用'));
    expect(find.text('关闭应用'), findsOneWidget);
  });
}
