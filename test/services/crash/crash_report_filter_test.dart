import 'package:PiliMax/services/crash/crash_report_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrashReportFilter', () {
    test('ignores SSL seek failures regardless of case or punctuation', () {
      expect(CrashReportFilter.shouldIgnore('SSL seek failed'), isTrue);
      expect(
        CrashReportFilter.shouldIgnore('Player error: ssl: avio seek failed'),
        isTrue,
      );
    });

    test('ignores recoverable player transport failures', () {
      expect(
        CrashReportFilter.shouldIgnore(
          'Failed to open https://example.invalid/video.m4s',
        ),
        isTrue,
      );
      expect(
        CrashReportFilter.shouldIgnore(
          'https: Stream ends prematurely at 1, should be 2',
        ),
        isTrue,
      );
    });

    test('ignores bare player diagnostics instead of treating them as code', () {
      const messages = <String>[
        'Seek failed (to 1790, size 18217805)',
        'tcp: Connection to tcp://upos.example:443 failed: Connection refused',
        'tls: mbedtls_ssl_handshake returned -0x7280',
        'amediacodec: java.lang.IllegalStateException: Released state',
        'NULL: Invalid NAL unit size (115387 > 86588).',
        'unsupported format for accessing property',
        '',
      ];

      for (final message in messages) {
        expect(
          CrashReportFilter.shouldIgnore(message),
          isTrue,
          reason: message,
        );
      }
    });

    test('ignores known player diagnostics even when wrapped', () {
      expect(
        CrashReportFilter.shouldIgnore(
          Exception('tcp: Failed to resolve hostname upos.example'),
        ),
        isTrue,
      );
      expect(
        CrashReportFilter.shouldIgnore(
          Exception('NULL: missing picture in access unit with size 86598'),
        ),
        isTrue,
      );
    });

    test('keeps real Dart failures reportable', () {
      final stackTrace = StackTrace.fromString(
        '#0 Navigator.of (package:flutter/src/widgets/navigator.dart:2937)',
      );

      expect(
        CrashReportFilter.shouldIgnore(
          'application invariant failed',
          stackTrace,
        ),
        isFalse,
      );
      expect(
        CrashReportFilter.shouldIgnore(
          StateError('Null check operator used on a null value'),
          stackTrace,
        ),
        isFalse,
      );
      expect(
        CrashReportFilter.shouldIgnore(
          StateError('tcp: Connection refused while updating app state'),
          StackTrace.fromString(
            '#0 Controller.load (package:PiliMax/pages/video/controller.dart:1)',
          ),
        ),
        isFalse,
      );
    });

    test('does not throw when error text conversion fails', () {
      expect(CrashReportFilter.shouldIgnore(_BrokenToString()), isFalse);
    });
  });
}

final class _BrokenToString {
  @override
  String toString() => throw StateError('unavailable');
}
