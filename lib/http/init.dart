import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/account_activation_coordinator.dart';
import 'package:PiliMax/http/constants.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/retry_interceptor.dart';
import 'package:PiliMax/http/system_proxy_config.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/accounts/account_manager/account_mgr.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/log_redactor.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:archive/archive.dart';
import 'package:brotli/brotli.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, listEquals;
import 'package:http2/http2.dart' show ClientTransportConnection;

final class _FailClosedProxyAdapter implements HttpClientAdapter {
  const _FailClosedProxyAdapter(this.reason);

  final String reason;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => Future<ResponseBody>.error(
    DioException.connectionError(
      requestOptions: options,
      reason: reason,
      error: StateError(reason),
      stackTrace: StackTrace.current,
    ),
    StackTrace.current,
  );

  @override
  void close({bool force = false}) {}
}

final class _FailClosedProxyConnectionManager implements ConnectionManager {
  const _FailClosedProxyConnectionManager(this.reason);

  final String reason;

  @override
  int get cachedConnectionsCount => 0;

  @override
  Future<ClientTransportConnection> getConnection(
    RequestOptions options,
    List<RedirectRecord> redirects,
  ) => Future<ClientTransportConnection>.error(
    DioException.connectionError(
      requestOptions: options,
      reason: reason,
      error: StateError(reason),
      stackTrace: StackTrace.current,
    ),
    StackTrace.current,
  );

  @override
  void removeConnection(ClientTransportConnection transport) {}

  @override
  void close({bool force = false}) {}
}

class Request {
  static const _gzipDecoder = GZipDecoder();
  static const _brotliDecoder = BrotliDecoder();

  static final Request _instance = Request._internal();
  static late AccountManager accountManager;
  static Future<void>? _cookieSetupFuture;
  static bool _cookieSetupComplete = false;
  static bool _accountManagerInstalled = false;
  static final _enableHttp2 = Pref.enableHttp2;
  static final AccountActivationCoordinator<Account> _accountActivation =
      AccountActivationCoordinator<Account>();
  static late final Dio dio;
  static Dio? _http11Dio;
  static Dio get http11Dio =>
      _http11Dio ??= _enableHttp2 ? _cloneHttp11Dio() : dio;
  factory Request() => _instance;

  /// 设置cookie
  static Future<void> setCookie() {
    if (_cookieSetupComplete) return Future<void>.value();
    final pending = _cookieSetupFuture;
    if (pending != null) return pending;
    final future = _setCookie();
    _cookieSetupFuture = future;
    return future.whenComplete(() {
      if (identical(_cookieSetupFuture, future)) {
        _cookieSetupFuture = null;
      }
    });
  }

  static Future<void> _setCookie() async {
    if (!_accountManagerInstalled) {
      accountManager = AccountManager();
      dio.interceptors.add(accountManager);
      _accountManagerInstalled = true;
    }

    await Accounts.init();
    await Accounts.restoreAccountModes();
    _cookieSetupComplete = true;

    _runStartupTask(
      'Request.activateAccounts',
      Accounts.activateAccountModes,
    );
    _runStartupTask('Request.setWebCookie', () async {
      await LoginUtils.setWebCookie();
    });

    if (Accounts.main.isLogin) {
      final coin = Pref.userInfoCache?.money;
      if (coin == null) {
        _runStartupTask('Request.setCoin', setCoin);
      } else {
        GlobalData().coins = coin;
      }
    }
  }

  static void _runStartupTask(
    String operation,
    Future<void> Function() task,
  ) {
    unawaited(
      Future<void>.sync(task).catchError((Object error, StackTrace stackTrace) {
        _reportOperationFailure(operation, error, stackTrace);
      }),
    );
  }

  static Future<void> setCoin() async {
    final res = await UserHttp.getCoin();
    if (res case Success(:final response)) {
      GlobalData().coins = response;
    }
  }

  static Future<void> buvidActive(Account account) =>
      _accountActivation.activate(
        key: account,
        isActivated: () => account.activated,
        request: () => _activateBuvid(account),
        setActivated: (value) => account.activated = value,
        onError: (error, stackTrace) => _reportOperationFailure(
          'Request.buvidActive',
          error,
          stackTrace,
        ),
      );

  static Future<void> _activateBuvid(Account account) async {
    // final html = await Request().get(Api.dynamicSpmPrefix,
    //     options: Options(extra: {'account': account}));
    // final String spmPrefix = _spmPrefixExp.firstMatch(html.data)!.group(1)!;
    final String randPngEnd = base64.encode([
      ...Iterable<int>.generate(
        32,
        (_) => Utils.random.nextInt(256),
      ),
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      ...Iterable<int>.generate(
        4,
        (_) => Utils.random.nextInt(256),
      ),
    ]);

    final jsonData = json.encode({
      '3064': 1,
      '39c8': '333.1387.fp.risk',
      '3c43': {
        'adca': 'Linux',
        'bfe9': randPngEnd.substring(randPngEnd.length - 50),
      },
    });

    final response = await Request().post(
      Api.activateBuvidApi,
      data: {'payload': jsonData},
      options: Options(
        extra: {'account': account},
        contentType: Headers.jsonContentType,
      ),
    );

    if (!_isSuccessfulBuvidActivation(response)) {
      final data = response.data;
      final code = data is Map ? data['code'] : null;
      throw StateError(
        'Buvid activation rejected '
        '(status=${response.statusCode}, code=$code)',
      );
    }
  }

  static bool _isSuccessfulBuvidActivation(Response response) {
    final statusCode = response.statusCode;
    final data = response.data;
    return statusCode != null &&
        statusCode >= 200 &&
        statusCode < 300 &&
        data is Map &&
        data['code'] == 0;
  }

  static Dio _cloneHttp11Dio() {
    final h11 = dio.clone(
      httpClientAdapter:
          (dio.httpClientAdapter as Http2Adapter).fallbackAdapter,
    );
    final interceptors = h11.interceptors;
    for (var i = 0; i < interceptors.length; i++) {
      final elem = interceptors[i];
      if (elem is RetryInterceptor) {
        interceptors[i] = elem.copyWith(client: h11);
        break;
      }
    }
    return h11;
  }

  static Timer? _networkChangeDebounce;

  static void _onConnectivityChanged(List<ConnectivityResult> result) {
    if (listEquals(result, const [ConnectivityResult.none])) {
      return;
    }
    _networkChangeDebounce?.cancel();
    _networkChangeDebounce = Timer(
      const Duration(milliseconds: 500),
      _resetAdaptersForNetworkChange,
    );
  }

  static void _watchConnectivity() {
    Connectivity().onConnectivityChanged.skip(1).listen(_onConnectivityChanged);
  }

  static (HttpClientAdapter, ConnectionManager?) _createPool() {
    final proxy = SystemProxyConfig.resolve(
      enabled: Pref.enableSystemProxy,
      host: Pref.systemProxyHost,
      port: Pref.systemProxyPort,
    );
    if (proxy.isInvalid) {
      final reason = '系统代理配置无效：${proxy.validationMessage}。请修正代理设置或关闭代理。';
      return (
        _FailClosedProxyAdapter(reason),
        _enableHttp2 ? _FailClosedProxyConnectionManager(reason) : null,
      );
    }

    final allowBadCertificates = Pref.badCertificateCallback;
    final http11Adapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()
          ..idleTimeout = const Duration(seconds: 15)
          ..autoUncompress = false; // Http2Adapter没有自动解压, 统一行为
        if (proxy.isValid) {
          client.findProxy = (_) => proxy.httpProxyDirective;
        }
        if (allowBadCertificates) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      },
    );

    final connectionManager = _enableHttp2
        ? ConnectionManager(
            idleTimeout: const Duration(seconds: 15),
            onClientCreate: proxy.isValid || allowBadCertificates
                ? (_, config) => config
                    ..proxy = proxy.isValid ? proxy.proxyUri : null
                    ..onBadCertificate = allowBadCertificates
                        ? (_) => true
                        : null
                : null,
          )
        : null;
    return (http11Adapter, connectionManager);
  }

  static void reloadNetworkConfiguration() {
    Request();
    _resetAdaptersForNetworkChange();
  }

  @pragma('vm:notify-debugger-on-exception')
  static void _resetAdaptersForNetworkChange() {
    try {
      final (h11, connectionManager) = _createPool();
      if (connectionManager != null) {
        (dio.httpClientAdapter as Http2Adapter)
          ..connectionManager.close(force: true)
          ..connectionManager = connectionManager
          ..fallbackAdapter.close(force: true)
          ..fallbackAdapter = h11;
        _http11Dio?.httpClientAdapter = h11;
      } else {
        dio
          ..httpClientAdapter.close(force: true)
          ..httpClientAdapter = h11;
      }
    } catch (error, stackTrace) {
      _reportOperationFailure(
        'Request.resetAdaptersForNetworkChange',
        error,
        stackTrace,
      );
    }
  }

  /*
   * config it and create
   */
  Request._internal() {
    //BaseOptions、Options、RequestOptions 都可以配置参数，优先级别依次递增，且可以根据优先级别覆盖参数
    BaseOptions options = BaseOptions(
      //请求基地址,可以包含子路径
      baseUrl: HttpString.apiBaseUrl,
      //连接服务器超时时间，单位是毫秒.
      connectTimeout: const Duration(milliseconds: 10000),
      //响应流上前后两次接受到数据的间隔，单位为毫秒。
      receiveTimeout: const Duration(milliseconds: 10000),
      //Http请求头.
      headers: {
        'user-agent': 'Dart/3.6 (dart:io)', // Http2Adapter不会自动添加标头
        if (!_enableHttp2) 'connection': 'keep-alive',
        'accept-encoding': 'br,gzip',
      },
      responseDecoder: _responseDecoder, // Http2Adapter没有自动解压
      persistentConnection: true,
    );

    final (h11, connectionManager) = _createPool();

    dio = Dio(options)
      ..httpClientAdapter = _enableHttp2
          ? Http2Adapter(connectionManager, fallbackAdapter: h11)
          : h11;

    // 先于其他Interceptor
    if (Pref.retryCount != 0) {
      dio.interceptors.add(
        RetryInterceptor(dio, Pref.retryCount, Pref.retryDelay),
      );
    }

    // 日志拦截器 输出请求、响应内容
    if (kDebugMode && Pref.enableNetworkLog) {
      dio.interceptors.add(
        LogInterceptor(
          request: false,
          requestHeader: false,
          responseHeader: false,
          logPrint: (value) => debugPrint(
            LogRedactor.redactText(value.toString()),
          ),
        ),
      );
    }

    dio
      ..transformer = BackgroundTransformer()
      ..options.validateStatus = (int? status) {
        return status != null && status >= 200 && status < 300;
      };

    if (Platform.isIOS) _watchConnectivity();
  }

  /*
   * get请求
   */
  Future<Response> get<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.get<T>(
        url,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e, s) {
      return _handleDioException(
        e,
        s,
        operation: 'Request.get',
      );
    }
  }

  /*
   * post请求
   */
  Future<Response> post<T>(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    // if (kDebugMode) debugPrint('post-data: $data');
    try {
      return await dio.post<T>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e, s) {
      return _handleDioException(
        e,
        s,
        operation: 'Request.post',
        showToast: true,
      );
    }
  }

  /*
   * 下载文件
   */
  Future<Response> downloadFile(
    String urlPath,
    String savePath, {
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.download(
        urlPath,
        savePath,
        cancelToken: cancelToken,
        // onReceiveProgress: (int count, int total) {
        // 进度
        // if (kDebugMode) debugPrint("$count $total");
        // },
      );
      // if (kDebugMode) debugPrint('downloadFile success: ${response.data}');
    } on DioException catch (e, s) {
      // if (kDebugMode) debugPrint('downloadFile error: $e');
      return _handleDioException(
        e,
        s,
        operation: 'Request.downloadFile',
      );
    }
  }

  static Future<Response> _handleDioException(
    DioException error,
    StackTrace stackTrace, {
    required String operation,
    bool showToast = false,
  }) async {
    if (showToast) {
      try {
        AccountManager.toast(error);
      } catch (toastError, toastStackTrace) {
        _reportOperationFailure(
          '$operation.toast',
          toastError,
          toastStackTrace,
        );
      }
    }
    try {
      Utils.reportError(error, stackTrace, operation);
    } catch (reportError) {
      if (kDebugMode) {
        debugPrint(
          '$operation reporting failed (${reportError.runtimeType})',
        );
      }
    }

    String message;
    try {
      message = await AccountManager.dioError(error);
    } catch (messageError, messageStackTrace) {
      _reportOperationFailure(
        '$operation.describeError',
        messageError,
        messageStackTrace,
      );
      message = '网络请求失败';
    }
    return Response(
      data: {'message': message},
      statusCode: error.response?.statusCode ?? -1,
      requestOptions: error.requestOptions,
    );
  }

  static void _reportOperationFailure(
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

  static List<int> responseBytesDecoder(
    List<int> responseBytes,
    Map<String, List<String>> headers,
  ) => switch (headers['content-encoding']?.firstOrNull) {
    'gzip' => _gzipDecoder.decodeBytes(responseBytes),
    'br' => _brotliDecoder.convert(responseBytes),
    _ => responseBytes,
  };

  static String _responseDecoder(
    List<int> responseBytes,
    RequestOptions options,
    ResponseBody responseBody,
  ) => utf8.decode(
    responseBytesDecoder(responseBytes, responseBody.headers),
    allowMalformed: true,
  );
}
