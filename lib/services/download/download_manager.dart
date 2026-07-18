import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

class DownloadManager {
  static final Map<String, _DownloadPathLock> _pathLocks = {};

  final String url;
  final String path;
  final void Function(int, int)? onReceiveProgress;
  final void Function([Object? error]) onDone;
  final Dio? _dio;

  DownloadStatus _status = DownloadStatus.downloading;

  DownloadStatus get status => _status;
  final _cancelToken = CancelToken();
  late Future<void> task;

  DownloadManager({
    required String url,
    required String path,
    required void Function(int, int)? onReceiveProgress,
    required void Function([Object? error]) onDone,
  }) : this._(
         url: url,
         path: path,
         onReceiveProgress: onReceiveProgress,
         onDone: onDone,
         dio: null,
       );

  /// Uses an explicit client, primarily for isolated download testing.
  DownloadManager.withDio({
    required String url,
    required String path,
    required void Function(int, int)? onReceiveProgress,
    required void Function([Object? error]) onDone,
    required Dio dio,
  }) : this._(
         url: url,
         path: path,
         onReceiveProgress: onReceiveProgress,
         onDone: onDone,
         dio: dio,
       );

  DownloadManager._({
    required this.url,
    required this.path,
    required this.onReceiveProgress,
    required this.onDone,
    required this._dio,
  }) {
    task = _start();
  }

  Dio get _httpClient => _dio ?? Request.http11Dio;

  Future<void> _start() async {
    Object? completionError;
    try {
      await _withTargetLock(() async {
        if (_cancelToken.isCancelled || _status != DownloadStatus.downloading) {
          throw const _DownloadCancelledException();
        }
        final file = File(path);
        var initialOffset = file.existsSync() ? await file.length() : 0;
        _DownloadValidator? resumeValidator;
        if (initialOffset > 0) {
          resumeValidator = await _readResumeValidator();
          if (resumeValidator == null) {
            // A byte count alone cannot prove that an old partial file belongs
            // to the current CDN representation.
            await _discardInvalidFile(file);
            initialOffset = 0;
          }
        } else {
          await _deleteResumeMetadata(ignoreErrors: true);
        }
        await _download(file, initialOffset, resumeValidator);
      });
      if (_status != DownloadStatus.downloading) {
        completionError = const _DownloadCancelledException();
      } else {
        _status = DownloadStatus.completed;
      }
    } catch (e) {
      if (_status == DownloadStatus.downloading) {
        _status = DownloadStatus.failDownload;
      }
      completionError = e;
    }
    if (completionError == null) {
      onDone();
    } else {
      onDone(completionError);
    }
  }

  Future<void> _withTargetLock(Future<void> Function() action) async {
    var lockKey = p.normalize(p.absolute(path));
    if (Platform.isWindows) {
      lockKey = lockKey.toLowerCase();
    }
    final pathLock = _pathLocks.putIfAbsent(lockKey, _DownloadPathLock.new);
    pathLock.users++;
    try {
      await pathLock.lock.synchronized(action);
    } finally {
      pathLock.users--;
      if (pathLock.users == 0 && identical(_pathLocks[lockKey], pathLock)) {
        _pathLocks.remove(lockKey);
      }
    }
  }

  Future<void> _download(
    File file,
    int initialOffset,
    _DownloadValidator? initialValidator,
  ) async {
    var offset = initialOffset;
    var resumeValidator = initialValidator;
    var retriedFromStart = false;

    while (true) {
      try {
        await _downloadAttempt(file, offset, resumeValidator);
        return;
      } on _DownloadIntegrityException catch (e) {
        final canRetryFromStart =
            e.retryFromStart &&
            initialOffset > 0 &&
            !retriedFromStart &&
            !_cancelToken.isCancelled;

        await _discardInvalidFile(file);
        if (!canRetryFromStart) {
          rethrow;
        }

        retriedFromStart = true;
        offset = 0;
        resumeValidator = null;
      }
    }
  }

  Future<void> _downloadAttempt(
    File file,
    int requestedOffset,
    _DownloadValidator? resumeValidator,
  ) async {
    final isResumeRequest = requestedOffset > 0;
    if (isResumeRequest && resumeValidator == null) {
      throw const _DownloadIntegrityException(
        'A resume request requires a persisted resource validator.',
        retryFromStart: true,
      );
    }
    final headers = <String, String>{
      // Byte ranges and response lengths must describe the bytes written to
      // disk, so transparent content encoding is deliberately disabled.
      'accept-encoding': 'identity',
      if (isResumeRequest) 'range': 'bytes=$requestedOffset-',
      if (isResumeRequest) 'if-range': resumeValidator!.value,
    };

    final Response<ResponseBody> response = await _httpClient.get<ResponseBody>(
      url.http2https,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        validateStatus: (status) =>
            status == HttpStatus.ok ||
            status == HttpStatus.partialContent ||
            status == HttpStatus.requestedRangeNotSatisfiable,
      ),
      cancelToken: _cancelToken,
    );

    final body = response.data;
    if (body == null) {
      throw _DownloadIntegrityException(
        'Download response did not contain a body.',
        retryFromStart: isResumeRequest,
      );
    }

    try {
      final plan = _responsePlan(
        response: response,
        requestedOffset: requestedOffset,
        resumeValidator: resumeValidator,
      );
      if (plan.alreadyComplete) {
        _reportInitialProgress(requestedOffset, plan.expectedTotalLength);
        await _deleteResumeMetadata(ignoreErrors: true);
        return;
      }
      if (isResumeRequest && plan.writeOffset == 0) {
        // If If-Range selected a new representation, remove the old prefix
        // before publishing the new validator. A crash between those steps
        // can then only leave an empty/unvalidated file, never an old prefix
        // paired with the new representation's validator.
        await _discardInvalidFile(file);
      }
      try {
        await _replaceResumeMetadata(plan.validator);
      } on FileSystemException {
        await _discardInvalidFile(file);
        rethrow;
      }
      await _writeResponse(file: file, body: body, plan: plan);
      await _deleteResumeMetadata(ignoreErrors: true);
    } on _DownloadIntegrityException catch (e) {
      if (isResumeRequest && !e.retryFromStart) {
        throw _DownloadIntegrityException(e.message, retryFromStart: true);
      }
      rethrow;
    } finally {
      await _cancelResponseStream(body);
    }
  }

  _DownloadResponsePlan _responsePlan({
    required Response<ResponseBody> response,
    required int requestedOffset,
    required _DownloadValidator? resumeValidator,
  }) {
    final status = response.statusCode;
    final isResumeRequest = requestedOffset > 0;
    switch (status) {
      case HttpStatus.ok:
        _validateResponseEncoding(response.headers);
        final contentLength = _positiveContentLength(response.headers);
        if (contentLength == null) {
          throw _DownloadIntegrityException(
            'HTTP 200 response has no valid Content-Length.',
            retryFromStart: isResumeRequest,
          );
        }
        // A server may ignore Range and return the complete representation.
        // In that case the existing partial file must be replaced, not
        // appended to.
        return _DownloadResponsePlan.write(
          writeOffset: 0,
          expectedBodyLength: contentLength,
          expectedTotalLength: contentLength,
          validator: _responseValidator(response.headers),
        );

      case HttpStatus.partialContent:
        _validateResponseEncoding(response.headers);
        if (isResumeRequest &&
            !_responseMatchesValidator(response.headers, resumeValidator!)) {
          throw const _DownloadIntegrityException(
            'HTTP 206 response does not match the persisted resource validator.',
            retryFromStart: true,
          );
        }
        final contentRange = _parseSatisfiedContentRange(response.headers);
        if (contentRange == null ||
            contentRange.start != requestedOffset ||
            contentRange.end != contentRange.total - 1) {
          throw _DownloadIntegrityException(
            'HTTP 206 response has an inconsistent Content-Range.',
            retryFromStart: isResumeRequest,
          );
        }

        final expectedBodyLength = contentRange.end - contentRange.start + 1;
        final declaredBodyLength = _optionalContentLength(response.headers);
        if (declaredBodyLength != null &&
            declaredBodyLength != expectedBodyLength) {
          throw _DownloadIntegrityException(
            'HTTP 206 Content-Length does not match Content-Range.',
            retryFromStart: isResumeRequest,
          );
        }

        return _DownloadResponsePlan.write(
          writeOffset: requestedOffset,
          expectedBodyLength: expectedBodyLength,
          expectedTotalLength: contentRange.total,
          validator: resumeValidator ?? _responseValidator(response.headers),
        );

      case HttpStatus.requestedRangeNotSatisfiable:
        final totalLength = _parseUnsatisfiedContentRange(response.headers);
        if (isResumeRequest &&
            _responseMatchesValidator(response.headers, resumeValidator!) &&
            totalLength != null &&
            totalLength == requestedOffset) {
          return _DownloadResponsePlan.alreadyComplete(totalLength);
        }
        throw _DownloadIntegrityException(
          'HTTP 416 response does not prove that the local file is complete.',
          retryFromStart: isResumeRequest,
        );

      default:
        throw _DownloadIntegrityException(
          'Unexpected download response status: $status.',
          retryFromStart: isResumeRequest,
        );
    }
  }

  Future<void> _writeResponse({
    required File file,
    required ResponseBody body,
    required _DownloadResponsePlan plan,
  }) async {
    if (plan.writeOffset > 0) {
      final actualOffset = file.existsSync() ? await file.length() : 0;
      if (actualOffset != plan.writeOffset) {
        throw const _DownloadIntegrityException(
          'The local file changed while the download was being resumed.',
          retryFromStart: true,
        );
      }
    }

    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    _reportInitialProgress(plan.writeOffset, plan.expectedTotalLength);

    final sink = file.openWrite(
      mode: plan.writeOffset == 0
          ? FileMode.writeOnly
          : FileMode.writeOnlyAppend,
    );
    var sinkClosed = false;
    var bodyBytes = 0;
    var received = plan.writeOffset;
    int? lastProgressSecond;

    try {
      await for (final chunk in body.stream) {
        if (bodyBytes + chunk.length > plan.expectedBodyLength) {
          throw _DownloadIntegrityException(
            'Download body is longer than declared by the server.',
            retryFromStart: plan.writeOffset > 0,
          );
        }
        sink.add(chunk);
        bodyBytes += chunk.length;
        received += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (lastProgressSecond != now) {
          lastProgressSecond = now;
          onReceiveProgress?.call(received, plan.expectedTotalLength);
        }
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
    } catch (error, stackTrace) {
      Object? closeError;
      StackTrace? closeStackTrace;
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (error, stackTrace) {
          closeError = error;
          closeStackTrace = stackTrace;
        }
      }
      if (error is FileSystemException || closeError is FileSystemException) {
        await _discardInvalidFile(file);
        if (closeError case final FileSystemException closeError) {
          Error.throwWithStackTrace(
            closeError,
            closeStackTrace ?? stackTrace,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (bodyBytes != plan.expectedBodyLength) {
      throw _DownloadIntegrityException(
        'Download body length mismatch: expected '
        '${plan.expectedBodyLength}, received $bodyBytes.',
        retryFromStart: plan.writeOffset > 0,
      );
    }

    final int finalLength;
    try {
      finalLength = await file.length();
    } on FileSystemException {
      await _discardInvalidFile(file);
      rethrow;
    }
    if (finalLength != plan.expectedTotalLength) {
      throw _DownloadIntegrityException(
        'Downloaded file length mismatch: expected '
        '${plan.expectedTotalLength}, found $finalLength.',
        retryFromStart: plan.writeOffset > 0,
      );
    }
    onReceiveProgress?.call(finalLength, plan.expectedTotalLength);
  }

  void _reportInitialProgress(int offset, int total) {
    // Existing callers use a zero progress notification to persist totalBytes.
    onReceiveProgress?.call(0, total);
    if (offset > 0) {
      onReceiveProgress?.call(offset, total);
    }
  }

  Future<void> _discardInvalidFile(File file) async {
    try {
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // If deletion is unavailable, truncation still guarantees that
          // invalid bytes cannot be mistaken for a resumable download.
          await file.writeAsBytes(const <int>[], flush: true);
        }
      }
    } finally {
      await _deleteResumeMetadata(ignoreErrors: true);
    }
  }

  Future<void> _cancelResponseStream(ResponseBody body) async {
    try {
      await body.stream.listen((_) {}).cancel();
    } catch (_) {
      // A fully consumed single-subscription stream cannot be listened to
      // again. In that case its transport resources are already released.
    }
    try {
      // ResponseBody exposes close for adapter-owned resources, but Dio marks
      // it internal because normal callers do not handle raw response bodies.
      // ignore: invalid_use_of_internal_member
      body.close();
    } catch (_) {}
  }

  void _validateResponseEncoding(Headers headers) {
    final encoding = _singleHeaderValue(headers, 'content-encoding');
    if (encoding != null && encoding.toLowerCase() != 'identity') {
      throw _DownloadIntegrityException(
        'Encoded download responses are not supported: $encoding.',
      );
    }
    final transferEncoding = _singleHeaderValue(headers, 'transfer-encoding');
    if (transferEncoding == null) {
      return;
    }
    final unsupported = transferEncoding
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value != 'identity' && value != 'chunked')
        .toList(growable: false);
    if (unsupported.isNotEmpty) {
      throw _DownloadIntegrityException(
        'Unsupported transfer encoding: ${unsupported.join(', ')}.',
      );
    }
  }

  File get _resumeMetadataFile => File('$path.pilimax-resume.json');

  Future<_DownloadValidator?> _readResumeValidator() async {
    final file = _resumeMetadataFile;
    if (!file.existsSync()) {
      return null;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) {
        return null;
      }
      return _DownloadValidator.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _replaceResumeMetadata(
    _DownloadValidator? validator,
  ) async {
    await _deleteResumeMetadata();
    if (validator == null) {
      return;
    }
    final file = _resumeMetadataFile;
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(validator.toJson()), flush: true);
  }

  Future<void> _deleteResumeMetadata({bool ignoreErrors = false}) async {
    final file = _resumeMetadataFile;
    if (!file.existsSync()) {
      return;
    }
    try {
      await file.delete();
    } catch (_) {
      if (!ignoreErrors) {
        rethrow;
      }
    }
  }

  _DownloadValidator? _responseValidator(Headers headers) {
    final etag = _singleHeaderValue(headers, 'etag');
    if (etag != null &&
        etag.isNotEmpty &&
        !etag.toLowerCase().startsWith('w/')) {
      return _DownloadValidator.etag(etag);
    }

    final lastModified = _singleHeaderValue(headers, 'last-modified');
    if (lastModified == null || lastModified.isEmpty) {
      return null;
    }
    try {
      HttpDate.parse(lastModified);
      return _DownloadValidator.lastModified(lastModified);
    } on FormatException {
      return null;
    }
  }

  bool _responseMatchesValidator(
    Headers headers,
    _DownloadValidator validator,
  ) => _singleHeaderValue(headers, validator.headerName) == validator.value;

  int? _positiveContentLength(Headers headers) {
    final value = _optionalContentLength(headers);
    return value != null && value > 0 ? value : null;
  }

  int? _optionalContentLength(Headers headers) {
    final raw = _singleHeaderValue(headers, Headers.contentLengthHeader);
    if (raw == null) {
      return null;
    }
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw const _DownloadIntegrityException(
        'Response has an invalid Content-Length header.',
      );
    }
    return value;
  }

  _SatisfiedContentRange? _parseSatisfiedContentRange(Headers headers) {
    final raw = _singleHeaderValue(headers, 'content-range');
    if (raw == null) {
      return null;
    }
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        start < 0 ||
        end < start ||
        total <= end) {
      return null;
    }
    return _SatisfiedContentRange(start: start, end: end, total: total);
  }

  int? _parseUnsatisfiedContentRange(Headers headers) {
    final raw = _singleHeaderValue(headers, 'content-range');
    if (raw == null) {
      return null;
    }
    final match = RegExp(
      r'^bytes\s+\*/(\d+)$',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }
    final total = int.tryParse(match.group(1)!);
    return total != null && total > 0 ? total : null;
  }

  String? _singleHeaderValue(Headers headers, String name) {
    final values = headers[name];
    if (values == null) {
      return null;
    }
    if (values.length != 1) {
      throw _DownloadIntegrityException(
        'Response has multiple $name header values.',
      );
    }
    return values.single.trim();
  }

  Future<void> cancel({required bool isDelete}) {
    if (!isDelete && _status == DownloadStatus.downloading) {
      _status = DownloadStatus.pause;
    }
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    return task;
  }
}

class _DownloadResponsePlan {
  const _DownloadResponsePlan.write({
    required this.writeOffset,
    required this.expectedBodyLength,
    required this.expectedTotalLength,
    required this.validator,
  }) : alreadyComplete = false;

  const _DownloadResponsePlan.alreadyComplete(this.expectedTotalLength)
    : writeOffset = 0,
      expectedBodyLength = 0,
      validator = null,
      alreadyComplete = true;

  final int writeOffset;
  final int expectedBodyLength;
  final int expectedTotalLength;
  final _DownloadValidator? validator;
  final bool alreadyComplete;
}

class _DownloadValidator {
  const _DownloadValidator._(this.headerName, this.value);

  factory _DownloadValidator.etag(String value) =>
      _DownloadValidator._('etag', value);

  factory _DownloadValidator.lastModified(String value) =>
      _DownloadValidator._('last-modified', value);

  static _DownloadValidator? fromJson(Map<String, dynamic> json) {
    final headerName = json['header']?.toString().toLowerCase();
    final value = json['value']?.toString();
    if (value == null || value.isEmpty) {
      return null;
    }
    switch (headerName) {
      case 'etag':
        return value.toLowerCase().startsWith('w/')
            ? null
            : _DownloadValidator.etag(value);
      case 'last-modified':
        try {
          HttpDate.parse(value);
          return _DownloadValidator.lastModified(value);
        } on FormatException {
          return null;
        }
      default:
        return null;
    }
  }

  final String headerName;
  final String value;

  Map<String, String> toJson() => {'header': headerName, 'value': value};
}

class _SatisfiedContentRange {
  const _SatisfiedContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}

class _DownloadIntegrityException implements Exception {
  const _DownloadIntegrityException(
    this.message, {
    this.retryFromStart = false,
  });

  final String message;
  final bool retryFromStart;

  @override
  String toString() => 'Download integrity error: $message';
}

class _DownloadCancelledException implements Exception {
  const _DownloadCancelledException();

  @override
  String toString() => 'Download cancelled.';
}

class _DownloadPathLock {
  final Lock lock = Lock();
  int users = 0;
}
