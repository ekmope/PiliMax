import 'dart:io';

import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_adapter.dart';
import 'package:PiliMax/utils/accounts/account_type_adapter.dart';
import 'package:PiliMax/utils/accounts/cookie_jar_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Map<String, String> validCookies({String mid = '24680'}) => {
  'SESSDATA': 'session-secret-value',
  'DedeUserID': mid,
  'bili_jct': 'csrf-secret-value',
};

void main() {
  group('LoginAccount identity validation', () {
    test('reads a valid mid and csrf token', () {
      final account = LoginAccount.fromCookieMap(validCookies());

      expect(account.isValid, isTrue);
      expect(account.mid, 24680);
      expect(account.csrf, 'csrf-secret-value');
      expect(account.headers['x-bili-mid'], '24680');
    });

    for (final testCase
        in <
          (
            String,
            LoginAccountValidationIssue,
          )
        >[
          ('SESSDATA', LoginAccountValidationIssue.missingSession),
          ('DedeUserID', LoginAccountValidationIssue.missingUserId),
          ('bili_jct', LoginAccountValidationIssue.missingCsrf),
        ]) {
      test('rejects a missing ${testCase.$1} cookie', () {
        final cookies = validCookies()..remove(testCase.$1);

        expect(
          () => LoginAccount.fromCookieMap(cookies),
          throwsA(
            isA<LoginAccountValidationException>().having(
              (error) => error.issue,
              'issue',
              testCase.$2,
            ),
          ),
        );
      });

      test('rejects an empty ${testCase.$1} cookie', () {
        final cookies = validCookies()..[testCase.$1] = '   ';

        expect(
          () => LoginAccount.fromCookieMap(cookies),
          throwsA(
            isA<LoginAccountValidationException>().having(
              (error) => error.issue,
              'issue',
              testCase.$2,
            ),
          ),
        );
      });
    }

    for (final invalidMid in ['not-a-number', '0', '-1']) {
      test('rejects invalid user id $invalidMid', () {
        expect(
          () => LoginAccount.fromCookieMap(validCookies(mid: invalidMid)),
          throwsA(
            isA<LoginAccountValidationException>().having(
              (error) => error.issue,
              'issue',
              LoginAccountValidationIssue.invalidUserId,
            ),
          ),
        );
      });
    }

    test('does not expose credentials in validation errors', () {
      const accessToken = 'access-token-must-not-leak';
      const userId = 'user-id-must-not-leak';
      Object? error;
      try {
        LoginAccount.fromCookieMap(
          {
            'SESSDATA': 'session-must-not-leak',
            'DedeUserID': userId,
            'bili_jct': 'csrf-must-not-leak',
          },
          accessKey: accessToken,
        );
      } catch (caught) {
        error = caught;
      }

      expect(error, isA<LoginAccountValidationException>());
      final message = error.toString();
      expect(message, isNot(contains('session-must-not-leak')));
      expect(message, isNot(contains(accessToken)));
      expect(message, isNot(contains(userId)));
      expect(message, isNot(contains('csrf-must-not-leak')));
    });

    test('rejects malformed cookie maps and lists', () {
      expect(
        () => LoginAccount.fromCookieMap({'SESSDATA': 1}),
        throwsA(isA<LoginAccountValidationException>()),
      );
      expect(
        () => LoginAccount.fromCookieList([
          {'name': 'SESSDATA'},
        ]),
        throwsA(isA<LoginAccountValidationException>()),
      );
    });

    test('rejects malformed account JSON', () {
      expect(
        () => LoginAccount.fromJson({
          'cookies': validCookies(),
          'type': ['not-an-index'],
        }),
        throwsA(
          isA<LoginAccountValidationException>().having(
            (error) => error.issue,
            'issue',
            LoginAccountValidationIssue.malformedAccountData,
          ),
        ),
      );
    });

    test('storage construction contains invalid identity data', () {
      final account = LoginAccount.fromStorage(
        cookieJar: BiliCookieJar.fromStorageJson({
          'SESSDATA': 'session-secret-value',
        }),
        accessKey: null,
        refresh: null,
        type: const <AccountType>[],
      );

      expect(account.isValid, isFalse);
      expect(
        account.validationIssue,
        LoginAccountValidationIssue.missingUserId,
      );
      expect(() => account.mid, throwsStateError);
    });
  });

  group('stored login accounts', () {
    late Directory hiveDirectory;

    setUpAll(() async {
      hiveDirectory = await Directory.systemTemp.createTemp(
        'pilimax_account_test_',
      );
      Hive
        ..init(hiveDirectory.path)
        ..registerAdapter(BiliCookieJarAdapter())
        ..registerAdapter(LoginAccountAdapter())
        ..registerAdapter(AccountTypeAdapter());

      final box = await Hive.openBox<LoginAccount>('account');
      await box.put(
        'legacy-invalid-record',
        LoginAccount.fromStorage(
          cookieJar: BiliCookieJar.fromStorageJson({
            'SESSDATA': 'legacy-session-secret',
          }),
          type: const <AccountType>[AccountType.main],
        ),
      );
      await box.put(
        '24680',
        LoginAccount.fromCookieMap(
          validCookies(),
          type: <AccountType>{AccountType.main},
        ),
      );
      await box.close();

      await Accounts.init();
    });

    tearDownAll(() async {
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    test('opens the box and quarantines invalid legacy accounts', () {
      expect(Accounts.account.get('legacy-invalid-record'), isNull);
      expect(Accounts.account.get('24680')?.isValid, isTrue);

      final quarantined = Accounts.accountQuarantine?.get(
        'legacy-invalid-record',
      );
      expect(quarantined, isNotNull);
      expect(quarantined!.isValid, isFalse);
      expect(
        quarantined.validationIssue,
        LoginAccountValidationIssue.missingUserId,
      );
    });

    test(
      'delete is concurrent-safe and onChange rejects deleted accounts',
      () async {
        final account = LoginAccount.fromCookieMap(validCookies(mid: '97531'));
        await account.onChange();

        final firstDelete = account.delete();
        final secondDelete = account.delete();

        expect(identical(firstDelete, secondDelete), isTrue);
        await firstDelete;
        expect(Accounts.account.get('97531'), isNull);
        await expectLater(account.onChange(), throwsStateError);
      },
    );
  });
}
