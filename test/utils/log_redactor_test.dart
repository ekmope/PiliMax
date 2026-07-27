import 'dart:convert';

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
        'url': 'https://example.com/?[REDACTED]',
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
      expect(redacted, contains('https://example.com/?[REDACTED]'));
      expect(redacted, isNot(contains('access_key')));
      expect(redacted, isNot(contains('qrcode_key')));
      expect(redacted, isNot(contains('code=123456')));
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

      expect(RegExp(r'\[local-path\]').allMatches(redacted), hasLength(4));
      expect(redacted, isNot(contains('com.PiliMax.android')));
      expect(redacted, isNot(contains('private.log')));
      expect(redacted, isNot(contains('state.json')));
    });

    test('redacts buvid device identifiers recursively and in text', () {
      const rawBuvid = 'raw-buvid-secret';
      const rawBuvid3 = 'raw-buvid3-secret';
      const rawBuvid4 = 'raw-buvid4-secret';
      final exported = jsonEncode(
        LogRedactor.redact({
          'buvid': rawBuvid,
          'buvid3': rawBuvid3,
          'buvid4': rawBuvid4,
          'requestId': 'request-123',
          'nested': 'buvid=$rawBuvid&buvid3=$rawBuvid3&buvid4=$rawBuvid4',
        }),
      );

      expect(exported, isNot(contains(rawBuvid)));
      expect(exported, isNot(contains(rawBuvid3)));
      expect(exported, isNot(contains(rawBuvid4)));
      expect(exported, contains('request-123'));
    });

    test('redacts encoded Bilibili identity headers', () {
      final structured =
          LogRedactor.redact({
                'x-bili-device-bin': 'encoded-device-secret',
                'x-bili-metadata-bin': 'encoded-account-secret',
                'x-bili-aurora-eid': 'derived-mid-secret',
                'x-bili-gaia-vtoken': 'gaia-secret',
                'requestId': 'request-123',
              })
              as Map<Object?, Object?>;
      final text = LogRedactor.redactText(
        'x-bili-device-bin: encoded-device-secret\n'
        '"x-bili-metadata-bin":"encoded-account-secret"\n'
        'x-bili-mid=123456\n'
        'gaia_vtoken=gaia-query-secret',
      );

      expect(structured['x-bili-device-bin'], LogRedactor.redacted);
      expect(structured['x-bili-metadata-bin'], LogRedactor.redacted);
      expect(structured['x-bili-aurora-eid'], LogRedactor.redacted);
      expect(structured['x-bili-gaia-vtoken'], LogRedactor.redacted);
      expect(structured['requestId'], 'request-123');
      expect(text, isNot(contains('encoded-device-secret')));
      expect(text, isNot(contains('encoded-account-secret')));
      expect(text, isNot(contains('123456')));
      expect(text, isNot(contains('gaia-query-secret')));
    });

    test('strips query and fragment from signed media URLs', () {
      const plainUrl = 'https://cdn.example.com/health';
      final redacted = LogRedactor.redactText(
        'video=https://cdn.example.com/video.m4s?deadline=123&upsig=secret'
        '&trid=trace#segment '
        'audio=https://cdn.example.com/audio.m4s#part '
        'authenticated=https://alice:password@example.com/private '
        'plain=$plainUrl',
      );

      expect(
        redacted,
        contains('https://cdn.example.com/video.m4s?[REDACTED]'),
      );
      expect(
        redacted,
        contains('https://cdn.example.com/audio.m4s?[REDACTED]'),
      );
      expect(redacted, contains(plainUrl));
      expect(redacted, contains('https://example.com/private'));
      expect(redacted, isNot(contains('deadline')));
      expect(redacted, isNot(contains('upsig')));
      expect(redacted, isNot(contains('#part')));
      expect(redacted, isNot(contains('alice')));
      expect(redacted, isNot(contains('password')));
    });

    test('redacts absolute paths without changing remote URL paths', () {
      const remoteUrl = 'https://cdn.example.com/workspace/public-video.m4s';
      final redacted = LogRedactor.redactText(
        r'windows=D:\private\video.mp4'
        '\n'
        r'quotedWindows="C:\Program Files\PiliMax\debug.log"'
        '\n'
        'spacedWindows=C:\\Users\\Jane Doe\\PiliMax\\debug.log\n'
        r'unc=\\server\share\private.log'
        '\n'
        'unix=/tmp/private.log\n'
        'customUnix=/workspace/user/private.log\n'
        "quotedUnix='/opt/Pili Max/debug.log'\n"
        "quotedCustomUnix='/app/data/private log'\n"
        'remote=$remoteUrl',
      );

      expect(redacted, contains('windows=[local-path]'));
      expect(redacted, contains('quotedWindows="[local-path]"'));
      expect(redacted, contains('spacedWindows=[local-path]'));
      expect(redacted, contains('unc=[local-path]'));
      expect(redacted, contains('unix=[local-path]'));
      expect(redacted, contains('customUnix=[local-path]'));
      expect(redacted, contains("quotedUnix='[local-path]'"));
      expect(redacted, contains("quotedCustomUnix='[local-path]'"));
      expect(redacted, contains(remoteUrl));
      expect(redacted, isNot(contains('Program Files')));
      expect(redacted, isNot(contains('Jane Doe')));
      expect(redacted, isNot(contains('Pili Max')));
      expect(redacted, isNot(contains('/workspace/user')));
      expect(redacted, isNot(contains('/app/data')));
    });
  });
}
