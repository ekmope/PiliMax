import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_manager/account_mgr.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  group('AccountManager cookies', () {
    late Directory hiveDirectory;
    late AnonymousAccount anonymous;

    Future<void> clearAnonymousCookies() => anonymous.cookieJar.deleteAll();

    setUpAll(() async {
      hiveDirectory = await Directory.systemTemp.createTemp(
        'pilimax_account_manager_test_',
      );
      Hive.init(hiveDirectory.path);
      GStorage.setting = await Hive.openBox<dynamic>('setting');
      GStorage.video = await Hive.openBox<dynamic>('video');
      GStorage.localCache = await Hive.openBox<dynamic>('localCache');
      anonymous = AnonymousAccount();
    });

    tearDownAll(() async {
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    setUp(clearAnonymousCookies);
    tearDown(clearAnonymousCookies);

    test('isolates malformed cookies and redirect locations', () async {
      final dio = _dioWithResponse(
        ResponseBody.fromString(
          'redirect',
          HttpStatus.found,
          headers: {
            HttpHeaders.setCookieHeader: [
              'malformed-cookie, valid_cookie=value; Path=/',
            ],
            HttpHeaders.locationHeader: [
              'http://[',
              'https://redirect.example.test/next',
            ],
          },
        ),
      );

      final response = await dio.get<String>(
        'https://api.bilibili.com/original',
        options: Options(
          extra: {'account': anonymous},
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );

      expect(response.statusCode, HttpStatus.found);
      expect(
        await anonymous.cookieJar.loadForRequest(
          Uri.parse('https://api.bilibili.com/original'),
        ),
        contains(
          isA<Cookie>()
              .having((cookie) => cookie.name, 'name', 'valid_cookie')
              .having((cookie) => cookie.value, 'value', 'value'),
        ),
      );
      expect(
        await anonymous.cookieJar.loadForRequest(
          Uri.parse('https://redirect.example.test/next'),
        ),
        contains(
          isA<Cookie>().having(
            (cookie) => cookie.name,
            'name',
            'valid_cookie',
          ),
        ),
      );
    });

    test(
      'keeps the original Dio error when account persistence fails',
      () async {
        final account = LoginAccount.fromCookieMap({
          'SESSDATA': 'session',
          'DedeUserID': '1',
          'bili_jct': 'csrf',
        });
        final dio = _dioWithResponse(
          ResponseBody.fromString(
            'failed',
            HttpStatus.internalServerError,
            headers: {
              HttpHeaders.setCookieHeader: ['new_cookie=value; Path=/'],
            },
          ),
        );

        await expectLater(
          dio.post<String>(
            'https://api.bilibili.com/failure',
            options: Options(extra: {'account': account}),
          ),
          throwsA(
            isA<DioException>()
                .having(
                  (error) => error.type,
                  'type',
                  DioExceptionType.badResponse,
                )
                .having(
                  (error) => error.response?.statusCode,
                  'statusCode',
                  HttpStatus.internalServerError,
                ),
          ),
        );
      },
    );
  });
}

Dio _dioWithResponse(ResponseBody response) => Dio()
  ..httpClientAdapter = _StaticResponseAdapter(response)
  ..interceptors.add(AccountManager());

final class _StaticResponseAdapter implements HttpClientAdapter {
  _StaticResponseAdapter(this.response);

  final ResponseBody response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => response;

  @override
  void close({bool force = false}) {}
}
