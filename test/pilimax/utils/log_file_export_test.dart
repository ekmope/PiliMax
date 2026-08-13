import 'dart:io';

import 'package:PiliMax/pilimax/utils/log_file_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogFileExport', () {
    test('builds a stable log file name without user data', () {
      final fileName = LogFileExport.buildFileName(
        'pilimax_error_log',
        DateTime(2026, 7, 25, 9, 8, 7, 6),
      );

      expect(fileName, 'pilimax_error_log_20260725_090807_006.log');
    });

    test('rejects file prefixes that could escape the target directory', () {
      final timestamp = DateTime(2026, 7, 25);

      expect(
        () => LogFileExport.buildFileName('../private', timestamp),
        throwsArgumentError,
      );
      expect(
        () => LogFileExport.buildFileName(r'folder\private', timestamp),
        throwsArgumentError,
      );
    });

    test('redacts the complete text before writing a log file', () async {
      final directory = await Directory.systemTemp.createTemp(
        'pilimax_error_log_export_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = await LogFileExport.writeToDirectory(
        content:
            'Cookie: SESSDATA=session;bili_jct=csrf\n'
            'Authorization: Bearer access-token\n'
            'path=/data/user/0/com.PiliMax.android/files/private.log',
        filePrefix: 'pilimax_error_log',
        directory: directory,
        timestamp: DateTime(2026, 7, 25, 9, 8, 7, 6),
      );
      final exportText = await file.readAsString();

      expect(file.path, endsWith('.log'));
      expect(exportText, contains('Cookie: [REDACTED]'));
      expect(exportText, contains('Authorization: [REDACTED]'));
      expect(exportText, contains('[local-path]'));
      expect(exportText, isNot(contains('session')));
      expect(exportText, isNot(contains('access-token')));
      expect(exportText, isNot(contains('private.log')));
    });
  });
}
