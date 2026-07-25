// edit from package:dio_cookie_manager
import 'dart:async';
import 'dart:io';

import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/constants.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_manager/app_request_signer.dart';
import 'package:PiliMax/utils/accounts/account_manager/request_error_toast_gate.dart';
import 'package:PiliMax/utils/accounts/api_type.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

final _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

class AccountManager extends Interceptor {
  AccountManager();

  static final _toastGate = RequestErrorToastGate();

  String blockServer = Pref.blockServer;

  static String getCookies(List<Cookie> cookies) {
    // Sort cookies by path (longer path first).
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) {
        return 0;
      } else if (a.path == null) {
        return -1;
      } else if (b.path == null) {
        return 1;
      } else {
        return b.path!.length.compareTo(a.path!.length);
      }
    });
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final path = options.path;

    late final Account account = options.extra['account'] ?? _findAccount(path);

    if (account is NoAccount || _skipCookie(path)) return handler.next(options);

    if (!account.isLogin && path == Api.heartBeat) {
      return handler.reject(
        DioException.requestCancelled(requestOptions: options, reason: null),
        false,
      );
    }

    final isApp = path.startsWith(HttpString.appBaseUrl);

    if (isApp && options.responseType == ResponseType.bytes) {
      options.headers.addAll(account.grpcHeaders);
      return handler.next(options);
    }

    options.headers
      ..addAll(account.headers)
      ..['referer'] ??= HttpString.baseUrl;

    // app端不需要管理cookie
    if (isApp) {
      try {
        AppRequestSigner.sign(options, accessKey: account.accessKey);
      } catch (error, stackTrace) {
        const operation = 'AccountManager.signAppRequest';
        _reportFailure(operation, error, stackTrace);
        return handler.reject(
          _safeDioException(options, operation, error, stackTrace),
          true,
        );
      }
      return handler.next(options);
    }

    unawaited(_loadCookiesAndContinue(account, options, handler));
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final path = options.path;
    if (options.extra['account'] is NoAccount ||
        path.startsWith(HttpString.appBaseUrl) ||
        _skipCookie(path)) {
      return handler.next(response);
    }

    unawaited(_saveResponseCookiesAndContinue(response, handler));
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.responseType == ResponseType.stream) {
      return handler.next(err);
    }
    if (err.requestOptions.method != 'POST') {
      toast(err);
    }
    final response = err.response;
    if (response == null || !_shouldManageCookies(response.requestOptions)) {
      return handler.next(err);
    }

    unawaited(_saveErrorCookiesAndContinue(response, err, handler));
  }

  static void toast(DioException err) {
    const List<String> skipShow = [
      'heartbeat',
      'history/report',
      'roomEntryAction',
      'seg.so',
      'online/total',
      'github',
      'hdslb.com',
      'biliimg.com',
      'site/getCoin',
    ];
    if (err.type == DioExceptionType.cancel) return;

    final endpoint = requestErrorEndpoint(err.requestOptions);
    if (kDebugMode) {
      debugPrint(
        '🌹🌹ApiInterceptor: $endpoint (${err.type.name})',
      );
    }
    final normalizedEndpoint = endpoint.toLowerCase();
    if (skipShow.any(
          (value) => normalizedEndpoint.contains(value.toLowerCase()),
        ) ||
        (normalizedEndpoint.contains('skipsegments') &&
            err.requestOptions.method.toUpperCase() == 'GET')) {
      return;
    }
    final gateKey = '${err.type.name}:$endpoint';
    if (!_toastGate.tryAcquire(gateKey)) return;
    unawaited(_showToast(err, endpoint, gateKey));
  }

  Future<void> _saveCookies(Response response) async {
    final Account account =
        response.requestOptions.extra['account'] ??
        _findAccount(response.requestOptions.path);
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) {
      return;
    }
    final cookies = <Cookie>[];
    var didReportParseFailure = false;
    for (final header in setCookies) {
      for (final value in header.split(_setCookieReg)) {
        if (value.isEmpty) continue;
        try {
          cookies.add(Cookie.fromSetCookieValue(value));
        } catch (error, stackTrace) {
          if (!didReportParseFailure) {
            didReportParseFailure = true;
            _reportFailure(
              'AccountManager.parseSetCookie',
              error,
              stackTrace,
            );
          }
        }
      }
    }
    if (cookies.isEmpty) return;

    final statusCode = response.statusCode ?? 0;
    final locations = response.headers[HttpHeaders.locationHeader] ?? const [];
    final isRedirectRequest = statusCode >= 300 && statusCode < 400;
    var didSave = false;
    try {
      final originalUri = response.requestOptions.uri;
      final realUri = originalUri.resolveUri(response.realUri);
      await account.cookieJar.saveFromResponse(realUri, cookies);
      didSave = true;
    } catch (error, stackTrace) {
      _reportFailure(
        'AccountManager.saveResponseCookies',
        error,
        stackTrace,
      );
    }
    if (isRedirectRequest && locations.isNotEmpty) {
      final originalUri = response.realUri;
      var didReportRedirectFailure = false;
      for (final location in locations) {
        try {
          await account.cookieJar.saveFromResponse(
            originalUri.resolve(location),
            cookies,
          );
          didSave = true;
        } catch (error, stackTrace) {
          if (!didReportRedirectFailure) {
            didReportRedirectFailure = true;
            _reportFailure(
              'AccountManager.saveRedirectCookies',
              error,
              stackTrace,
            );
          }
        }
      }
    }
    if (didSave) await account.onChange();
  }

  Future<void> _loadCookiesAndContinue(
    Account account,
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final cookies = await account.cookieJar.loadForRequest(options.uri);
      final previousCookies =
          options.headers[HttpHeaders.cookieHeader] as String?;
      final newCookies = getCookies([
        ...?previousCookies
            ?.split(';')
            .where((value) => value.isNotEmpty)
            .map(Cookie.fromSetCookieValue),
        ...cookies,
      ]);
      options.headers[HttpHeaders.cookieHeader] = newCookies;
    } catch (error, stackTrace) {
      const operation = 'AccountManager.loadRequestCookies';
      _reportFailure(operation, error, stackTrace);
      handler.reject(
        _safeDioException(options, operation, error, stackTrace),
        true,
      );
      return;
    }
    handler.next(options);
  }

  Future<void> _saveResponseCookiesAndContinue(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await _saveCookies(response);
    } catch (error, stackTrace) {
      _reportFailure(
        'AccountManager.handleResponseCookies',
        error,
        stackTrace,
      );
    }
    handler.next(response);
  }

  Future<void> _saveErrorCookiesAndContinue(
    Response response,
    DioException originalError,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      await _saveCookies(response);
    } catch (error, stackTrace) {
      _reportFailure(
        'AccountManager.handleErrorCookies',
        error,
        stackTrace,
      );
    }
    handler.next(originalError);
  }

  static Future<void> _showToast(
    DioException error,
    String endpoint,
    String gateKey,
  ) async {
    try {
      final message = await dioError(error);
      await SmartDialog.showToast('$message $endpoint');
    } catch (toastError, stackTrace) {
      _reportFailure(
        'AccountManager.showNetworkErrorToast',
        toastError,
        stackTrace,
      );
    } finally {
      _toastGate.release(gateKey);
    }
  }

  static DioException _safeDioException(
    RequestOptions options,
    String operation,
    Object error,
    StackTrace stackTrace,
  ) => DioException(
    requestOptions: options,
    error: StateError('$operation failed (${error.runtimeType})'),
    stackTrace: stackTrace,
  );

  static void _reportFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      Utils.reportError(
        StateError('$operation failed (${error.runtimeType})'),
        stackTrace,
        operation,
      );
    } catch (reportError) {
      if (kDebugMode) {
        debugPrint(
          '$operation reporting failed (${reportError.runtimeType})',
        );
      }
    }
  }

  bool _skipCookie(String path) {
    return path.startsWith(blockServer) ||
        path.contains('hdslb.com') ||
        path.contains('biliimg.com');
  }

  bool _shouldManageCookies(RequestOptions options) =>
      options.extra['account'] is! NoAccount &&
      !options.path.startsWith(HttpString.appBaseUrl) &&
      !_skipCookie(options.path);

  Account _findAccount(String path) => ApiType.loginApi.contains(path)
      ? AnonymousAccount()
      : Accounts.get(
          AccountType.values.firstWhere(
            (i) => ApiType.apiTypeSet[i]?.contains(path) == true,
            orElse: () => AccountType.main,
          ),
        );

  static Future<String> dioError(DioException error) async {
    final safeLocalMessage = safeLocalNetworkErrorMessage(error.error);
    if (safeLocalMessage != null) return safeLocalMessage;

    switch (error.type) {
      case .badCertificate:
        return '证书有误！';
      case .badResponse:
        return '服务器异常，请稍后重试！';
      case .cancel:
        return '请求已被取消，请重新请求';
      case .connectionError:
        return '连接错误，请检查网络设置';
      case .connectionTimeout:
        return '网络连接超时，请检查网络设置';
      case .receiveTimeout:
        return '响应超时，请稍后重试！';
      case .sendTimeout:
        return '发送请求超时，请检查网络设置';
      case .transformTimeout:
        return '转换响应数据超时！';
      case .unknown:
        String desc;
        try {
          desc = PlatformUtils.isMobile
              ? (await Connectivity().checkConnectivity()).first.desc
              : '';
        } catch (error, stackTrace) {
          _reportFailure(
            'AccountManager.checkConnectivity',
            error,
            stackTrace,
          );
          desc = '';
        }
        return '$desc网络异常';
    }
  }
}

extension _ConnectivityResultExt on ConnectivityResult {
  String get desc => const ['蓝牙', 'Wi-Fi', '局域', '流量', '无', '代理', '其他'][index];
}
