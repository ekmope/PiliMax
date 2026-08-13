import 'dart:typed_data';

import 'package:PiliMax/grpc/grpc_req.dart';
import 'package:PiliMax/http/retry_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primaryThenHttp11 permits at most one protocol fallback', () async {
    final attempts = <bool>[];

    final response = await GrpcReq.sendWithTransportPolicy(
      makeRequest: ({required useHttp11}) async {
        attempts.add(useHttp11);
        if (!useHttp11) {
          throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/play-view'),
            reason: 'http2 unavailable',
          );
        }
        return _response();
      },
      transportPolicy: GrpcTransportPolicy.primaryThenHttp11,
      protocolFallbackAvailable: true,
      shouldFallback: (_) => false,
    );

    expect(response.statusCode, 200);
    expect(attempts, <bool>[false, true]);
  });

  test('does not perform a third attempt after fallback fails', () async {
    final attempts = <bool>[];

    await expectLater(
      GrpcReq.sendWithTransportPolicy(
        makeRequest: ({required useHttp11}) {
          attempts.add(useHttp11);
          return Future<Response<dynamic>>.error(
            DioException.connectionError(
              requestOptions: RequestOptions(path: '/play-view'),
              reason: 'offline',
            ),
          );
        },
        transportPolicy: GrpcTransportPolicy.primaryThenHttp11,
        protocolFallbackAvailable: true,
        shouldFallback: (_) => false,
      ),
      throwsA(isA<DioException>()),
    );
    expect(attempts, <bool>[false, true]);
  });

  test('skip flag bypasses the global retry interceptor', () async {
    final adapter = _FailingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(RetryInterceptor(dio, 2, 0));

    await expectLater(
      dio.get<void>(
        'https://example.invalid',
        options: Options(
          extra: {
            RetryInterceptor.skipTransportRetryExtraKey: true,
          },
        ),
      ),
      throwsA(isA<DioException>()),
    );
    expect(adapter.attempts, 1);
  });
}

Response<dynamic> _response() => Response<dynamic>(
  requestOptions: RequestOptions(path: '/play-view'),
  statusCode: 200,
);

final class _FailingAdapter implements HttpClientAdapter {
  int attempts = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    attempts++;
    return Future<ResponseBody>.error(
      DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}
