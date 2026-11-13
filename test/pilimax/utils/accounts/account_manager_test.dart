import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/pilimax/utils/accounts/anonymous_buvid_coordinator.dart';
import 'package:PiliMax/utils/accounts/account_manager/account_mgr.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
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

    test('prepares anonymous web cookies before sending the request', () async {
      await anonymous.delete();
      final grpcBuvid = anonymous.buvid;
      final started = Completer<void>();
      final release = Completer<void>();
      final adapter = _DeferredResponseAdapter();
      final dio = Dio()
        ..httpClientAdapter = adapter
        ..interceptors.add(
          AccountManager(
            prepareAnonymous: (account) {
              return account.prepareWebBuvid(() async {
                started.complete();
                await release.future;
                return AnonymousBuvidCookies.fromResponse({
                  'code': 0,
                  'data': {'b_3': 'server-b3', 'b_4': 'server-b4'},
                });
              });
            },
          ),
        );
      final request = dio.get<String>(
        'https://api.bilibili.com/test',
        options: Options(extra: {'account': anonymous}),
      );
      await started.future;
      expect(adapter.options.isCompleted, isFalse);
      release.complete();
      final options = await adapter.options.future;
      expect(
        options.headers[HttpHeaders.cookieHeader],
        contains('buvid3=server-b3'),
      );
      expect(
        options.headers[HttpHeaders.cookieHeader],
        contains('buvid4=server-b4'),
      );
      expect(options.headers[HttpHeaders.cookieHeader], contains('b_nut='));
      expect(anonymous.buvid, grpcBuvid);
      expect(anonymous.activated, isFalse);
      adapter.response.complete(ResponseBody.fromString('ok', HttpStatus.ok));
      await request;
      dio.close();
    });

    test(
      'a response from a cleared anonymous session cannot restore cookies',
      () async {
        await anonymous.delete();
        final adapter = _DeferredResponseAdapter();
        final dio = Dio()
          ..httpClientAdapter = adapter
          ..interceptors.add(AccountManager());
        final request = dio.get<String>(
          'https://api.bilibili.com/test',
          options: Options(extra: {'account': anonymous}),
        );
        await adapter.options.future;
        await anonymous.delete();
        adapter.response.complete(
          ResponseBody.fromString(
            'old response',
            HttpStatus.ok,
            headers: {
              HttpHeaders.setCookieHeader: [
                'buvid3=stale; Domain=.bilibili.com; Path=/',
              ],
            },
          ),
        );
        await request;
        expect(anonymous.cookieJar.toJson()['buvid3'], isNot('stale'));
        dio.close();
      },
    );

    test('NoAccount requests bypass anonymous preparation', () async {
      var preparations = 0;
      final dio = Dio()
        ..httpClientAdapter = _StaticResponseAdapter(
          ResponseBody.fromString('ok', HttpStatus.ok),
        )
        ..interceptors.add(
          AccountManager(
            prepareAnonymous: (_) async {
              preparations++;
            },
          ),
        );
      await dio.get<String>(
        'https://api.bilibili.com/x/frontend/finger/spi',
        options: Options(extra: {'account': const NoAccount()}),
      );
      expect(preparations, 0);
      dio.close();
    });

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

final class _DeferredResponseAdapter implements HttpClientAdapter {
  final options = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    this.options.complete(options);
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}
