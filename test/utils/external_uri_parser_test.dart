import 'package:PiliMax/utils/external_uri_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExternalUriParser.positiveInt', () {
    test('accepts positive signed 64-bit values', () {
      expect(ExternalUriParser.positiveInt('1'), 1);
      expect(
        ExternalUriParser.positiveInt('9223372036854775807'),
        9223372036854775807,
      );
    });

    test(
      'rejects missing, non-positive, malformed, and overflowing values',
      () {
        for (final value in <String?>[
          null,
          '',
          '0',
          '-1',
          '1.5',
          'abc',
          '9223372036854775808',
          '999999999999999999999999999999999999',
        ]) {
          expect(
            ExternalUriParser.positiveInt(value),
            isNull,
            reason: '$value',
          );
        }
      },
    );
  });

  group('ExternalUriParser.nonNegativeInt', () {
    test('accepts zero and positive signed 64-bit values', () {
      expect(ExternalUriParser.nonNegativeInt('0'), 0);
      expect(ExternalUriParser.nonNegativeInt('1'), 1);
      expect(
        ExternalUriParser.nonNegativeInt('9223372036854775807'),
        9223372036854775807,
      );
    });

    test('rejects negative, malformed, and overflowing values', () {
      for (final value in <String?>[
        null,
        '',
        '-1',
        '1.5',
        'abc',
        '9223372036854775808',
      ]) {
        expect(
          ExternalUriParser.nonNegativeInt(value),
          isNull,
          reason: '$value',
        );
      }
    });
  });

  group('ExternalUriParser.nonNegativeSecondsToMilliseconds', () {
    test('converts finite non-negative seconds', () {
      expect(ExternalUriParser.nonNegativeSecondsToMilliseconds('0'), 0);
      expect(
        ExternalUriParser.nonNegativeSecondsToMilliseconds('1.25'),
        1250,
      );
      expect(
        ExternalUriParser.nonNegativeSecondsToMilliseconds('1e3'),
        1000000,
      );
    });

    test('rejects negative, non-finite, malformed, and overflowing values', () {
      for (final value in <String?>[
        null,
        '',
        '-1',
        'NaN',
        'Infinity',
        'abc',
        '1e1000',
        '9223372036854776',
      ]) {
        expect(
          ExternalUriParser.nonNegativeSecondsToMilliseconds(value),
          isNull,
          reason: '$value',
        );
      }
    });
  });

  group('ExternalUriParser.positivePathSegment', () {
    test('reads valid comment route fields', () {
      final segments = Uri.parse(
        'bilibili://comment/detail/17/832703053858603029/238686570016',
      ).pathSegments;

      expect(ExternalUriParser.positivePathSegment(segments, 1), 17);
      expect(
        ExternalUriParser.positivePathSegment(segments, 2),
        832703053858603029,
      );
      expect(
        ExternalUriParser.positivePathSegment(segments, 3),
        238686570016,
      );
    });

    test('rejects missing and invalid comment route fields', () {
      final missing = Uri.parse(
        'bilibili://comment/detail/17/832703053858603029',
      ).pathSegments;
      final negative = <String>['detail', '17', '-1', '2'];
      final overflowing = <String>[
        'detail',
        '17',
        '9223372036854775808',
        '2',
      ];

      expect(ExternalUriParser.positivePathSegment(missing, 3), isNull);
      expect(ExternalUriParser.positivePathSegment(negative, 2), isNull);
      expect(ExternalUriParser.positivePathSegment(overflowing, 2), isNull);
    });
  });
}
