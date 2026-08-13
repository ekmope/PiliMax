import 'dart:io';

import 'package:PiliMax/pilimax/utils/storage_init_resource_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'pilimax_storage_init_',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('rollback disposes locally owned resources in reverse order', () async {
    final tracker = StorageInitResourceTracker();
    final disposed = <int>[];
    tracker
      ..own(1, disposed.add)
      ..own(2, disposed.add);

    await tracker.rollback();

    expect(disposed, [2, 1]);
  });

  test('rollback closes a typed Hive box opened before a fault', () async {
    final tracker = StorageInitResourceTracker()
      ..watchHiveBox<String>('migrationState');
    await Hive.openBox<String>('migrationState');

    await tracker.rollback();

    expect(Hive.isBoxOpen('migrationState'), isFalse);
  });

  test('rollback leaves a Hive box that predates this session open', () async {
    final existing = await Hive.openBox<String>('existing');
    final tracker = StorageInitResourceTracker()
      ..watchHiveBox<String>('existing')
      ..watchHiveBox<String>('openedThisTime');
    await Hive.openBox<String>('openedThisTime');

    await tracker.rollback();

    expect(existing.isOpen, isTrue);
    expect(Hive.isBoxOpen('openedThisTime'), isFalse);
  });

  test('commit transfers ownership and makes rollback a no-op', () async {
    final tracker = StorageInitResourceTracker();
    var disposed = false;
    tracker
      ..own(Object(), (_) => disposed = true)
      ..commit();

    await tracker.rollback();

    expect(disposed, isFalse);
  });
}
