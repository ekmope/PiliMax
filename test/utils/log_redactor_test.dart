import 'package:PiliMax/utils/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRedactor', () {
    test('redacts sensitive map keys recursively', () {
      final redacted = LogRedactor.redact({
        'url': 'https://example.com/?access_key=token&qrcode_key=login-key',
        'headers': {
          'cookie': 'SESSDATA=session;bili_jct=csrf',
          'authorization': 'Bearer token',
        },
        'captcha_key': 'captcha-secret',
        'webdav': {'password': 'secret'},
      });

      expect(redacted, {
        'url':
            'https://example.com/?access_key=[REDACTED]&qrcode_key=[REDACTED]',
        'headers': {
          'cookie': LogRedactor.redacted,
          'authorization': LogRedactor.redacted,
        },
        'captcha_key': LogRedactor.redacted,
        'webdav': {'password': LogRedactor.redacted},
      });
    });

    test('redacts sensitive text values', () {
      final redacted = LogRedactor.redactText(
        'Cookie: SESSDATA=session;bili_jct=csrf\n'
        'url=https://example.com/?access_key=token&foo=bar\n'
        'scan=https://example.com/?qrcode_key=login-key&code=123456\n'
        'request={verify_code: 654321}\n'
        'response={data: {captcha_key: captcha-secret, '
        "recaptcha_token: 'recaptcha-secret'}}\n"
        '"password":"secret"',
      );

      expect(redacted, contains('Cookie: [REDACTED]'));
      expect(redacted, contains('access_key=[REDACTED]'));
      expect(redacted, contains('qrcode_key=[REDACTED]'));
      expect(redacted, contains('code=[REDACTED]'));
      expect(redacted, contains('verify_code: "[REDACTED]"'));
      expect(redacted, contains('captcha_key: "[REDACTED]"'));
      expect(redacted, contains('recaptcha_token: "[REDACTED]"'));
      expect(redacted, contains('"password":"[REDACTED]"'));
      expect(redacted, isNot(contains('session')));
      expect(redacted, isNot(contains('secret')));
      expect(redacted, isNot(contains('access_key=token')));
      expect(redacted, isNot(contains('captcha-secret')));
      expect(redacted, isNot(contains('recaptcha-secret')));
    });

    test('redacts Android private and shared-storage paths', () {
      final redacted = LogRedactor.redactText(
        'credential=/data/user/0/com.PiliMax.android/files/private.log\n'
        'legacy=/data/data/com.PiliMax.android/cache/error.log\n'
        'deviceProtected=/data/user_de/0/com.PiliMax.android/files/state.json\n'
        'shared=/storage/emulated/0/Android/data/com.PiliMax.android/log.txt',
      );

      expect(RegExp(r'\[app-path\]').allMatches(redacted), hasLength(4));
      expect(redacted, isNot(contains('com.PiliMax.android')));
      expect(redacted, isNot(contains('private.log')));
      expect(redacted, isNot(contains('state.json')));
    });
  });
}
