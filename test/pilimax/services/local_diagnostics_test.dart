import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/pilimax/services/local_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDiagnosticLogStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'pilimax_local_diagnostics_test_',
      );
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('serializes concurrent appends and redacts every entry', () async {
      final store = LocalDiagnosticLogStore(
        directory: directory,
        maxFileBytes: 64 * 1024,
      );

      await Future.wait([
        for (var index = 0; index < 24; index++)
          store.append(
            LocalDiagnosticEntry(
              area: LocalDiagnosticArea.http,
              event: 'request $index',
              timestamp: DateTime.utc(2026, 7, 28, 1, 2, index),
              details: {
                'index': index,
                'cookie': 'SESSDATA=session-$index',
                'url': 'https://example.com/video?access_key=secret-$index',
              },
            ),
          ),
      ]);

      final text = await store.readText();
      final entries = text
          .trim()
          .split('\n')
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(entries, hasLength(24));
      expect(entries.map((entry) => entry['event']), [
        for (var index = 0; index < 24; index++) 'request $index',
      ]);
      expect(text, contains('[REDACTED]'));
      expect(text, isNot(contains('session-')));
      expect(text, isNot(contains('secret-')));
    });

    test(
      'rotates at the byte limit and keeps only one bounded backup',
      () async {
        final store = LocalDiagnosticLogStore(
          directory: directory,
          maxFileBytes: 420,
          maxEntryBytes: 300,
        );

        for (var index = 0; index < 6; index++) {
          await store.append(
            LocalDiagnosticEntry(
              area: LocalDiagnosticArea.player,
              event: 'player_event_$index',
              timestamp: DateTime.utc(2026, 7, 28, 1, 2, index),
              details: {'payload': 'x' * 180},
            ),
          );
        }

        expect(store.currentFile.lengthSync(), lessThanOrEqualTo(420));
        expect(store.rotatedFile.lengthSync(), lessThanOrEqualTo(420));
        final text = await store.readText();
        expect(text, contains('player_event_5'));
        expect(text, isNot(contains('player_event_0')));
      },
    );

    test('clears current and rotated files', () async {
      final store = LocalDiagnosticLogStore(
        directory: directory,
        maxFileBytes: 420,
      );
      for (var index = 0; index < 4; index++) {
        await store.append(
          LocalDiagnosticEntry(
            area: LocalDiagnosticArea.audio,
            event: 'audio_event_$index',
            timestamp: DateTime.utc(2026, 7, 28),
            details: {'payload': 'x' * 220},
          ),
        );
      }

      await store.clear();

      expect(store.currentFile.existsSync(), isFalse);
      expect(store.rotatedFile.existsSync(), isFalse);
      expect(await store.readText(), isEmpty);
    });
  });
}
