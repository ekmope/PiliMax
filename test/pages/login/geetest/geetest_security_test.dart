import 'dart:convert' show jsonEncode;

import 'package:PiliMax/pages/login/geetest/geetest_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeetestSecurity.isAllowedRemoteUri', () {
    test('allows HTTPS Geetest and Geevisit hosts', () {
      for (final uri in [
        Uri.parse('https://api.geetest.com/get.php'),
        Uri.parse('https://static.geetest.com/static/js/fullpage.js'),
        Uri.parse('https://api.geevisit.com/ajax.php'),
        Uri.parse('https://geetest.com/'),
      ]) {
        expect(GeetestSecurity.isAllowedRemoteUri(uri), isTrue, reason: '$uri');
      }
    });

    test('rejects insecure, deceptive, credentialed, and custom-port URLs', () {
      for (final uri in [
        Uri.parse('http://api.geetest.com/get.php'),
        Uri.parse('https://geetest.com.example.org/'),
        Uri.parse('https://evilgeetest.com/'),
        Uri.parse('https://user@api.geetest.com/'),
        Uri.parse('https://api.geetest.com:444/'),
        Uri.parse('https://%/'),
      ]) {
        expect(
          GeetestSecurity.isAllowedRemoteUri(uri),
          isFalse,
          reason: '$uri',
        );
      }
    });
  });

  group('Geetest result validation', () {
    const challenge = 'challenge-1234567890';
    const validResult = {
      'geetest_challenge': challenge,
      'geetest_validate': 'validate-1234567890',
      'geetest_seccode': 'seccode-1234567890|jordan',
    };

    test('accepts bounded string fields matching the challenge', () {
      expect(
        GeetestSecurity.validateResult(
          validResult,
          expectedChallenge: challenge,
        ),
        validResult,
      );
      expect(
        GeetestSecurity.decodeLinuxResult(
          jsonEncode(validResult),
          expectedChallenge: challenge,
        ),
        validResult,
      );
    });

    test('rejects missing, non-string, control, and mismatched fields', () {
      for (final value in <Object?>[
        null,
        const {},
        {...validResult, 'geetest_validate': 42},
        {...validResult, 'geetest_validate': 'bad\nvalue'},
        {...validResult, 'geetest_challenge': 'different-challenge'},
      ]) {
        expect(
          () => GeetestSecurity.validateResult(
            value,
            expectedChallenge: challenge,
          ),
          throwsA(isA<GeetestValidationException>()),
          reason: '$value',
        );
      }
    });

    test('rejects oversized Linux callback JSON before decoding', () {
      final oversized = List.filled(
        GeetestSecurity.maxLinuxMessageLength + 1,
        'x',
      ).join();
      expect(
        () => GeetestSecurity.decodeLinuxResult(
          oversized,
          expectedChallenge: challenge,
        ),
        throwsA(isA<GeetestValidationException>()),
      );
    });
  });

  test('validates bootstrap token bounds', () {
    expect(GeetestSecurity.isValidBootstrapToken('12345678'), isTrue);
    expect(GeetestSecurity.isValidBootstrapToken('short'), isFalse);
    expect(GeetestSecurity.isValidBootstrapToken('valid-token\n'), isFalse);
  });
}
