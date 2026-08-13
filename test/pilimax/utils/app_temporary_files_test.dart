import 'dart:io';

import 'package:PiliMax/pilimax/utils/app_temporary_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('clearing one PiliMax owner never traverses the temp root', () async {
    final systemTemp = await Directory.systemTemp.createTemp(
      'pilimax_owned_temp_test_',
    );
    addTearDown(() => systemTemp.delete(recursive: true));

    final appRoot = Directory(path.join(systemTemp.path, 'pilimax'));
    final directories = OwnedTemporaryDirectories(appRoot);
    final cacheDirectory = await directories.ensure(AppTemporaryOwner.cache);
    final logDirectory = await directories.ensure(AppTemporaryOwner.logExport);
    final unrelatedFile = File(path.join(systemTemp.path, 'unrelated.tmp'));
    final cacheFile = File(path.join(cacheDirectory.path, 'cache.bin'));
    final logFile = File(path.join(logDirectory.path, 'report.log'));
    await unrelatedFile.writeAsString('keep');
    await cacheFile.writeAsString('clear');
    await logFile.writeAsString('keep');

    await directories.clear(AppTemporaryOwner.cache);

    expect(cacheDirectory.existsSync(), isFalse);
    expect(logFile.existsSync(), isTrue);
    expect(unrelatedFile.existsSync(), isTrue);
  });

  test('reset removes only the previous files from the same creator', () async {
    final root = await Directory.systemTemp.createTemp(
      'pilimax_owned_temp_reset_test_',
    );
    addTearDown(() => root.delete(recursive: true));
    final directories = OwnedTemporaryDirectories(root);
    final logDirectory = await directories.ensure(AppTemporaryOwner.logExport);
    final crashDirectory = await directories.ensure(
      AppTemporaryOwner.crashReportExport,
    );
    await File(path.join(logDirectory.path, 'old.log')).writeAsString('old');
    final crashFile = File(path.join(crashDirectory.path, 'crash.txt'));
    await crashFile.writeAsString('keep');

    final resetDirectory = await directories.reset(
      AppTemporaryOwner.logExport,
    );

    expect(resetDirectory.existsSync(), isTrue);
    expect(resetDirectory.listSync(), isEmpty);
    expect(crashFile.existsSync(), isTrue);
    expect(
      directories.ownsPath(
        path.join(resetDirectory.path, 'next.log'),
        owner: AppTemporaryOwner.logExport,
      ),
      isTrue,
    );
    expect(directories.ownsPath(crashFile.path), isTrue);
  });
}
