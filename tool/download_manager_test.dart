import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/services/download/download_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _testEtag = '"pilimax-v1"';

void main() {
  late Directory tempDir;
  late _QueueHttpClientAdapter adapter;
  late Dio dio;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pilimax-download-test-');
    adapter = _QueueHttpClientAdapter();
    dio = Dio()..httpClientAdapter = adapter;
  });

  tearDown(() async {
    dio.close(force: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'an unvalidated partial file is replaced instead of resumed',
    () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
      await file.writeAsBytes([1, 2, 3]);
      adapter.enqueue(
        _response(
          HttpStatus.ok,
          [1, 2, 3, 4, 5],
          headers: {
            'content-length': ['5'],
          },
        ),
      );

      final result = await _runDownload(dio, file);

      expect(result.error, isNull);
      expect(result.manager.status, DownloadStatus.completed);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.headers.containsKey('range'), isFalse);
      expect(adapter.requests.single.headers.containsKey('if-range'), isFalse);
      expect(adapter.requests.single.headers['accept-encoding'], 'identity');
    },
  );

  test('HTTP 206 can validate length from Content-Range alone', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await _writeValidatedPartial(file, [1, 2, 3]);
    adapter.enqueue(
      _response(
        HttpStatus.partialContent,
        [4, 5],
        headers: {
          'content-range': ['bytes 3-4/5'],
          'etag': [_testEtag],
        },
      ),
    );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(result.manager.status, DownloadStatus.completed);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.headers['if-range'], _testEtag);
    expect(_resumeMetadataFile(file).existsSync(), isFalse);
  });

  test('a changed resource validator forces a full restart', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await _writeValidatedPartial(file, [1, 2, 3]);
    adapter
      ..enqueue(
        _response(
          HttpStatus.partialContent,
          [8, 9],
          headers: {
            'content-range': ['bytes 3-4/5'],
            'etag': ['"pilimax-v2"'],
          },
        ),
      )
      ..enqueue(
        _response(
          HttpStatus.ok,
          [6, 7, 8, 9, 10],
          headers: {
            'content-length': ['5'],
            'etag': ['"pilimax-v2"'],
          },
        ),
      );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(await file.readAsBytes(), [6, 7, 8, 9, 10]);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.headers['range'], 'bytes=3-');
    expect(adapter.requests.first.headers['if-range'], _testEtag);
    expect(adapter.requests.last.headers.containsKey('range'), isFalse);
    expect(_resumeMetadataFile(file).existsSync(), isFalse);
  });

  test('HTTP 200 on If-Range replaces the old validated prefix', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await _writeValidatedPartial(file, [1, 2, 3]);
    adapter.enqueue(
      _response(
        HttpStatus.ok,
        [6, 7, 8, 9, 10],
        headers: {
          'content-length': ['5'],
          'etag': ['"pilimax-v2"'],
        },
      ),
    );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(await file.readAsBytes(), [6, 7, 8, 9, 10]);
    expect(adapter.requests.single.headers['range'], 'bytes=3-');
    expect(adapter.requests.single.headers['if-range'], _testEtag);
    expect(_resumeMetadataFile(file).existsSync(), isFalse);
  });

  test('Last-Modified can safely validate a resumed response', () async {
    const lastModified = 'Wed, 21 Oct 2015 07:28:00 GMT';
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await file.writeAsBytes([1, 2, 3]);
    await _resumeMetadataFile(file).writeAsString(
      jsonEncode({'header': 'last-modified', 'value': lastModified}),
      flush: true,
    );
    adapter.enqueue(
      _response(
        HttpStatus.partialContent,
        [4, 5],
        headers: {
          'content-range': ['bytes 3-4/5'],
          'last-modified': [lastModified],
        },
      ),
    );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(adapter.requests.single.headers['if-range'], lastModified);
    expect(_resumeMetadataFile(file).existsSync(), isFalse);
  });

  test('malformed or incomplete HTTP 206 ranges are never appended', () async {
    final invalidHeaders = <Map<String, List<String>>>[
      {
        'content-length': ['2'],
        'etag': [_testEtag],
      },
      {
        'content-range': ['bytes 3-4/*'],
        'content-length': ['2'],
        'etag': [_testEtag],
      },
      {
        'content-range': ['bytes 3-3/5'],
        'content-length': ['1'],
        'etag': [_testEtag],
      },
      {
        'content-range': ['bytes 3-5/5'],
        'content-length': ['3'],
        'etag': [_testEtag],
      },
      {
        'content-range': ['bytes 3-4/5'],
        'content-length': ['1'],
        'etag': [_testEtag],
      },
    ];

    for (var index = 0; index < invalidHeaders.length; index++) {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}invalid-range-$index.m4s',
      );
      await _writeValidatedPartial(file, [1, 2, 3]);
      final requestCount = adapter.requests.length;
      adapter
        ..enqueue(
          _response(
            HttpStatus.partialContent,
            [4, 5],
            headers: invalidHeaders[index],
          ),
        )
        ..enqueue(
          _response(
            HttpStatus.ok,
            [1, 2, 3, 4, 5],
            headers: {
              'content-length': ['5'],
            },
          ),
        );

      final result = await _runDownload(dio, file);

      expect(result.error, isNull, reason: 'case $index');
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(adapter.requests.length - requestCount, 2);
    }
  });

  test(
    'HTTP 200 without Content-Length fails after one resume retry',
    () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
      await _writeValidatedPartial(file, [1, 2, 3]);
      var closedResponses = 0;
      adapter
        ..enqueue(
          _response(
            HttpStatus.ok,
            [1, 2, 3, 4, 5],
            onClose: () => closedResponses++,
          ),
        )
        ..enqueue(
          _response(
            HttpStatus.ok,
            [1, 2, 3, 4, 5],
            onClose: () => closedResponses++,
          ),
        );

      final result = await _runDownload(dio, file);

      expect(result.error.toString(), contains('Content-Length'));
      expect(result.manager.status, DownloadStatus.failDownload);
      expect(file.existsSync(), isFalse);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.headers['range'], 'bytes=3-');
      expect(adapter.requests.last.headers.containsKey('range'), isFalse);
      expect(closedResponses, 2);
    },
  );

  test('encoded resume response is discarded before a full retry', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await _writeValidatedPartial(file, [1, 2, 3]);
    adapter
      ..enqueue(
        _response(
          HttpStatus.ok,
          [9, 9, 9, 9, 9],
          headers: {
            'content-length': ['5'],
            'content-encoding': ['gzip'],
          },
        ),
      )
      ..enqueue(
        _response(
          HttpStatus.ok,
          [1, 2, 3, 4, 5],
          headers: {
            'content-length': ['5'],
          },
        ),
      );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(adapter.requests, hasLength(2));
  });

  test('unsupported transfer compression is rejected before writing', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    adapter.enqueue(
      _response(
        HttpStatus.ok,
        [9, 9, 9, 9, 9],
        headers: {
          'content-length': ['5'],
          'transfer-encoding': ['gzip, chunked'],
        },
      ),
    );

    final result = await _runDownload(dio, file);

    expect(result.error.toString(), contains('transfer encoding'));
    expect(result.manager.status, DownloadStatus.failDownload);
    expect(file.existsSync(), isFalse);
    expect(adapter.requests, hasLength(1));
  });

  test(
    'HTTP 416 completes only when local length equals remote length',
    () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
      await _writeValidatedPartial(file, [1, 2, 3, 4, 5]);
      adapter.enqueue(
        _response(
          HttpStatus.requestedRangeNotSatisfiable,
          const [],
          headers: {
            'content-range': ['bytes */5'],
            'etag': [_testEtag],
          },
        ),
      );

      final result = await _runDownload(dio, file);

      expect(result.error, isNull);
      expect(result.manager.status, DownloadStatus.completed);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(adapter.requests, hasLength(1));
    },
  );

  test(
    'malformed HTTP 416 ranges reset instead of trusting the file',
    () async {
      final invalidHeaders = <Map<String, List<String>>>[
        {
          'etag': [_testEtag],
        },
        {
          'content-range': ['bytes 0-2/5'],
          'etag': [_testEtag],
        },
        {
          'content-range': ['bytes */0'],
          'etag': [_testEtag],
        },
        {
          'content-range': ['items */5'],
          'etag': [_testEtag],
        },
      ];

      for (var index = 0; index < invalidHeaders.length; index++) {
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}invalid-416-$index.m4s',
        );
        await _writeValidatedPartial(file, [9, 9, 9]);
        final requestCount = adapter.requests.length;
        adapter
          ..enqueue(
            _response(
              HttpStatus.requestedRangeNotSatisfiable,
              const [],
              headers: invalidHeaders[index],
            ),
          )
          ..enqueue(
            _response(
              HttpStatus.ok,
              [1, 2, 3, 4, 5],
              headers: {
                'content-length': ['5'],
              },
            ),
          );

        final result = await _runDownload(dio, file);

        expect(result.error, isNull, reason: 'case $index');
        expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
        expect(adapter.requests.length - requestCount, 2);
      }
    },
  );

  test('mismatched HTTP 416 resets and retries once from byte zero', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    await _writeValidatedPartial(file, [1, 2, 3, 4, 5, 6]);
    adapter
      ..enqueue(
        _response(
          HttpStatus.requestedRangeNotSatisfiable,
          const [],
          headers: {
            'content-range': ['bytes */5'],
            'etag': [_testEtag],
          },
        ),
      )
      ..enqueue(
        _response(
          HttpStatus.ok,
          [1, 2, 3, 4, 5],
          headers: {
            'content-length': ['5'],
          },
        ),
      );

    final result = await _runDownload(dio, file);

    expect(result.error, isNull);
    expect(result.manager.status, DownloadStatus.completed);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.headers['range'], 'bytes=6-');
    expect(adapter.requests.last.headers.containsKey('range'), isFalse);
  });

  test(
    'invalid resumed response retries once and never keeps a bad file',
    () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
      await _writeValidatedPartial(file, [1, 2, 3]);
      adapter
        ..enqueue(
          _response(
            HttpStatus.partialContent,
            [4, 5],
            headers: {
              'content-range': ['bytes 2-4/5'],
              'content-length': ['2'],
              'etag': [_testEtag],
            },
          ),
        )
        ..enqueue(
          _response(
            HttpStatus.ok,
            [1, 2, 3, 4],
            headers: {
              'content-length': ['5'],
            },
          ),
        );

      final result = await _runDownload(dio, file);

      expect(result.error, isNotNull);
      expect(result.error.toString(), contains('length mismatch'));
      expect(result.manager.status, DownloadStatus.failDownload);
      expect(file.existsSync(), isFalse);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.headers['range'], 'bytes=3-');
      expect(adapter.requests.last.headers.containsKey('range'), isFalse);
    },
  );

  test(
    'network interruption keeps only the validated resumable prefix',
    () async {
      final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
      final interruptedBody = StreamController<Uint8List>();
      adapter.enqueue(
        _streamResponse(
          HttpStatus.ok,
          interruptedBody.stream,
          headers: {
            'content-length': ['5'],
            'etag': [_testEtag],
          },
        ),
      );

      final interrupted = _startDownload(dio, file);
      await _waitUntil(() => adapter.requests.length == 1);
      interruptedBody
        ..add(Uint8List.fromList([1, 2, 3]))
        ..addError(const SocketException('connection interrupted'));
      await interruptedBody.close();
      final interruptedError = await interrupted.done;
      await interrupted.manager.task;

      expect(interruptedError, isNotNull);
      expect(interrupted.manager.status, DownloadStatus.failDownload);
      expect(await file.readAsBytes(), [1, 2, 3]);
      expect(_resumeMetadataFile(file).existsSync(), isTrue);

      adapter.enqueue(
        _response(
          HttpStatus.partialContent,
          [4, 5],
          headers: {
            'content-range': ['bytes 3-4/5'],
            'content-length': ['2'],
            'etag': [_testEtag],
          },
        ),
      );
      final resumed = await _runDownload(dio, file);

      expect(resumed.error, isNull);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(adapter.requests.last.headers['range'], 'bytes=3-');
      expect(adapter.requests.last.headers['if-range'], _testEtag);
      expect(_resumeMetadataFile(file).existsSync(), isFalse);
    },
  );

  test('concurrent managers serialize writes to the same target', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    final firstBody = StreamController<Uint8List>();
    adapter
      ..enqueue(
        _streamResponse(
          HttpStatus.ok,
          firstBody.stream,
          headers: {
            'content-length': ['5'],
          },
        ),
      )
      ..enqueue(
        _response(
          HttpStatus.ok,
          [1, 2, 3, 4, 5],
          headers: {
            'content-length': ['5'],
          },
        ),
      );

    final first = _startDownload(dio, file);
    await _waitUntil(() => adapter.requests.length == 1);
    final second = _startDownload(dio, file);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.requests, hasLength(1));

    firstBody.add(Uint8List.fromList([1, 2, 3, 4, 5]));
    await firstBody.close();
    final firstError = await first.done;
    final secondError = await second.done;
    await Future.wait([first.manager.task, second.manager.task]);

    expect(firstError, isNull);
    expect(secondError, isNull);
    expect(first.manager.status, DownloadStatus.completed);
    expect(second.manager.status, DownloadStatus.completed);
    expect(await file.readAsBytes(), [1, 2, 3, 4, 5]);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.headers.containsKey('range'), isFalse);
  });

  test('onDone callback is invoked only once even when it throws', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}video.m4s');
    adapter.enqueue(
      _response(
        HttpStatus.ok,
        [1, 2, 3],
        headers: {
          'content-length': ['3'],
        },
      ),
    );
    var callbackCount = 0;
    final manager = DownloadManager.withDio(
      url: 'https://download.test/video.m4s',
      path: file.path,
      onReceiveProgress: null,
      onDone: ([error]) {
        callbackCount++;
        throw StateError('callback failed');
      },
      dio: dio,
    );

    await expectLater(manager.task, throwsA(isA<StateError>()));

    expect(callbackCount, 1);
    expect(manager.status, DownloadStatus.completed);
    expect(await file.readAsBytes(), [1, 2, 3]);
  });
}

File _resumeMetadataFile(File file) => File('${file.path}.pilimax-resume.json');

Future<void> _writeValidatedPartial(
  File file,
  List<int> bytes, {
  String etag = _testEtag,
}) async {
  await file.writeAsBytes(bytes);
  await _resumeMetadataFile(file).writeAsString(
    jsonEncode({'header': 'etag', 'value': etag}),
    flush: true,
  );
}

Future<({DownloadManager manager, Object? error})> _runDownload(
  Dio dio,
  File file,
) async {
  final running = _startDownload(dio, file);
  final error = await running.done.timeout(const Duration(seconds: 5));
  await running.manager.task;
  return (manager: running.manager, error: error);
}

({DownloadManager manager, Future<Object?> done}) _startDownload(
  Dio dio,
  File file,
) {
  final done = Completer<Object?>();
  final manager = DownloadManager.withDio(
    url: 'https://download.test/video.m4s',
    path: file.path,
    onReceiveProgress: null,
    onDone: ([error]) {
      if (!done.isCompleted) {
        done.complete(error);
      }
    },
    dio: dio,
  );
  return (manager: manager, done: done.future);
}

ResponseBody _response(
  int statusCode,
  List<int> bytes, {
  Map<String, List<String>> headers = const {},
  void Function()? onClose,
}) => _streamResponse(
  statusCode,
  Stream.value(Uint8List.fromList(bytes)),
  headers: headers,
  onClose: onClose,
);

ResponseBody _streamResponse(
  int statusCode,
  Stream<Uint8List> stream, {
  Map<String, List<String>> headers = const {},
  void Function()? onClose,
}) => ResponseBody(
  stream,
  statusCode,
  headers: headers,
  onClose: onClose,
);

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not reached');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _QueueHttpClientAdapter implements HttpClientAdapter {
  final _responses = <ResponseBody>[];
  final requests = <RequestOptions>[];

  void enqueue(ResponseBody response) => _responses.add(response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) {
      throw StateError('No queued response for ${options.uri}.');
    }
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}
