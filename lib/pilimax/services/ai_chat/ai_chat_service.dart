import 'dart:async';
import 'dart:convert';

import 'package:PiliMax/services/logger.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

class AiApiException implements Exception {
  final String url;
  final int? statusCode;
  final String detail;

  AiApiException({required this.url, this.statusCode, required this.detail});

  @override
  String toString() =>
      '请求 $url 出错'
      '${statusCode != null ? '（HTTP $statusCode）' : ''}'
      '：$detail';
}

class AiPromptTemplate {
  String name;
  String prompt;

  AiPromptTemplate({required this.name, required this.prompt});

  Map<String, dynamic> toJson() => {'name': name, 'prompt': prompt};

  factory AiPromptTemplate.fromJson(Map<String, dynamic> json) =>
      AiPromptTemplate(name: json['name'] ?? '', prompt: json['prompt'] ?? '');
}

class AiChatService {
  static Options _options({Duration? receiveTimeout}) {
    final apiKey = Pref.aiApiKey;
    return Options(
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 60),
    );
  }

  static String _baseUrl() {
    final url = Pref.aiApiUrl.trim();
    final fragmentIndex = url.indexOf('#');
    return fragmentIndex < 0 ? url : url.substring(0, fragmentIndex);
  }

  static String _endpointUrl(String endpoint) {
    final baseUrl = _baseUrl();
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw _responseError(
        url: baseUrl,
        detail: '接口地址格式无效，请填写包含 http:// 或 https:// 的完整地址',
      );
    }
    final basePath = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return uri.replace(path: '$basePath/$endpoint').toString();
  }

  static String _safeUrl(String url) {
    final queryIndex = url.indexOf('?');
    final fragmentIndex = url.indexOf('#');
    var end = url.length;
    if (queryIndex >= 0 && queryIndex < end) end = queryIndex;
    if (fragmentIndex >= 0 && fragmentIndex < end) end = fragmentIndex;
    var result = url.substring(0, end);
    final uri = Uri.tryParse(result);
    if (uri != null && uri.hasAuthority && uri.userInfo.isNotEmpty) {
      result = uri.replace(userInfo: '').toString();
    }
    return _redactApiKey(result);
  }

  static String _redactApiKey(String value) {
    final apiKey = Pref.aiApiKey;
    if (apiKey.isEmpty) return value;
    return value
        .replaceAll(apiKey, '[redacted]')
        .replaceAll(Uri.encodeQueryComponent(apiKey), '[redacted]');
  }

  static String _safeDetail(String detail, String requestUrl) {
    var result = detail;
    final safeUrl = _safeUrl(requestUrl);
    if (requestUrl != safeUrl) {
      result = result.replaceAll(requestUrl, safeUrl);
    }

    final uri = Uri.tryParse(requestUrl);
    if (uri != null) {
      for (final value in uri.userInfo.split(':')) {
        if (value.isNotEmpty) {
          result = result
              .replaceAll(value, '[redacted]')
              .replaceAll(Uri.encodeQueryComponent(value), '[redacted]');
        }
      }
      for (final values in uri.queryParametersAll.values) {
        for (final value in values) {
          if (value.isNotEmpty) {
            result = result
                .replaceAll(value, '[redacted]')
                .replaceAll(Uri.encodeQueryComponent(value), '[redacted]');
          }
        }
      }
      if (uri.fragment.isNotEmpty) {
        result = result.replaceAll(uri.fragment, '[redacted]');
      }
    }
    return _redactApiKey(result);
  }

  static String _snippet(String value, [int max = 300]) {
    final text = value.trim();
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  static Future<String> _responseText(Response<dynamic>? response) async {
    dynamic data = response?.data;
    if (data is ResponseBody) {
      try {
        data = await utf8.decodeStream(data.stream);
      } catch (_) {
        return '';
      }
    }
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (error != null) return error.toString();
      if (data['message'] != null) return data['message'].toString();
      return jsonEncode(data);
    }
    return data?.toString() ?? '';
  }

  static AiApiException _logged(
    AiApiException exception, [
    StackTrace? stackTrace,
  ]) {
    logger.e('AI 请求失败', error: exception, stackTrace: stackTrace);
    return exception;
  }

  static AiApiException _responseError({
    required String url,
    required String detail,
    int? statusCode,
    StackTrace? stackTrace,
  }) => _logged(
    AiApiException(
      url: _safeUrl(url),
      statusCode: statusCode,
      detail: _safeDetail(detail, url),
    ),
    stackTrace,
  );

  static Future<AiApiException> _requestError(
    String fallbackUrl,
    DioException error,
  ) async {
    final requestUrl = error.requestOptions.uri.toString();
    final url = requestUrl.isEmpty ? fallbackUrl : requestUrl;
    String detail;
    if (error.type == DioExceptionType.badResponse) {
      detail = _snippet(await _responseText(error.response));
      if (detail.isEmpty) detail = '服务器返回错误';
    } else {
      detail = switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => '连接超时',
        DioExceptionType.badCertificate => '证书校验失败',
        DioExceptionType.cancel => '请求已取消',
        _ => '无法连接（${error.message ?? error.error ?? error.type.name}）',
      };
    }
    return _responseError(
      url: url,
      statusCode: error.response?.statusCode,
      detail: detail,
      stackTrace: error.stackTrace,
    );
  }

  /// Fetch model list from {base}/models.
  static Future<List<String>> fetchModels() async {
    final baseUrl = _baseUrl();
    if (baseUrl.isEmpty) throw Exception('请先配置 API 地址');
    final url = _endpointUrl('models');
    final Response<dynamic> response;
    try {
      response = await Dio().get(
        url,
        options: _options(receiveTimeout: const Duration(seconds: 30)),
      );
    } on DioException catch (error) {
      throw await _requestError(url, error);
    }
    final data = response.data;
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map(
            (item) => item is Map ? item['id']?.toString() ?? '' : '',
          )
          .where((id) => id.isNotEmpty)
          .toList();
    }
    throw _responseError(
      url: url,
      statusCode: response.statusCode,
      detail:
          '响应不是模型列表，请检查接口地址与版本路径'
          '${data == null ? '' : '（${_snippet(data.toString(), 200)}）'}',
    );
  }

  /// Stream chat completion from {base}/chat/completions.
  /// Returns a stream of content strings (each token/chunk)
  static Stream<String> streamChat({
    required List<Map<String, String>> messages,
    String? model,
  }) async* {
    final baseUrl = _baseUrl();
    if (baseUrl.isEmpty) throw Exception('请先配置 API 地址');
    final useModel = model ?? Pref.aiModel;
    if (useModel.isEmpty) throw Exception('请先选择模型');

    final url = _endpointUrl('chat/completions');
    final opts = _options(receiveTimeout: const Duration(minutes: 10))
      ..responseType = ResponseType.stream;
    final Response<ResponseBody> response;
    try {
      response = await Dio().post<ResponseBody>(
        url,
        data: jsonEncode({
          'model': useModel,
          'messages': messages,
          'stream': true,
        }),
        options: opts,
      );
    } on DioException catch (error) {
      throw await _requestError(url, error);
    }

    final body = response.data;
    if (body == null) {
      throw _responseError(
        url: url,
        statusCode: response.statusCode,
        detail: '服务器返回了空响应体',
      );
    }

    var sawData = false;
    var sawContent = false;
    final nonSse = StringBuffer();
    try {
      await for (final line
          in body.stream
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.startsWith('data:')) {
          if (!sawData && nonSse.length < 300) nonSse.writeln(trimmed);
          continue;
        }
        sawData = true;
        final data = trimmed.replaceFirst('data:', '').trim();
        if (data == '[DONE]') break;
        if (data.isEmpty) continue;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('SSE data is not a JSON object');
          }
          final json = decoded;
          if (json['error'] case final error?) {
            final detail = error is Map && error['message'] != null
                ? error['message'].toString()
                : error.toString();
            throw _responseError(
              url: url,
              statusCode: response.statusCode,
              detail: '服务器返回错误：${_snippet(detail)}',
            );
          }
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              sawContent = true;
              yield content;
            }
          }
        } on AiApiException {
          rethrow;
        } catch (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('SSE parse error: ${error.runtimeType}');
          }
          throw _responseError(
            url: url,
            statusCode: response.statusCode,
            detail: '流式响应格式错误：${_snippet(data)}',
            stackTrace: stackTrace,
          );
        }
      }
    } on AiApiException {
      rethrow;
    } catch (error, stackTrace) {
      throw _responseError(
        url: url,
        statusCode: response.statusCode,
        detail: '读取流式响应失败：$error',
        stackTrace: stackTrace,
      );
    }

    if (!sawData) {
      final contentType = response.headers.value(Headers.contentTypeHeader);
      throw _responseError(
        url: url,
        statusCode: response.statusCode,
        detail:
            '未返回流式响应，请检查接口地址与版本路径'
            '${contentType == null ? '' : '（content-type: $contentType）'}'
            '${nonSse.isEmpty ? '' : '：${_snippet(nonSse.toString())}'}',
      );
    }
    if (!sawContent) {
      throw _responseError(
        url: url,
        statusCode: response.statusCode,
        detail: '流式响应未包含有效内容',
      );
    }
  }

  // --- Template CRUD ---

  static final List<AiPromptTemplate> defaultTemplates = [
    AiPromptTemplate(
      name: '概貌总结',
      prompt: '请对这个视频内容进行概貌总结。考虑到视频可能较长，请避免过度省略。\n'
          '要求：\n'
          '1. 【核心主旨】用 1-2 句话精准概括视频的核心价值与主题。\n'
          '2. 【高光时刻】列出 3-5 个最具争议、最有趣或最重要的核心观点。\n'
          '3. 【时间线速览】按时间顺序，提供一个简明的目录式大纲，每个条目必须以时间戳 `[mm:ss]` 开头。\n'
          '4. 结构必须极其清晰，便于用户在 10 秒内判断是否值得观看全片。',
    ),
    AiPromptTemplate(
      name: '详细分析',
      prompt: '请对这个视频进行极具深度的拆解分析。请克服长文本的省略倾向，尽可能保留具体细节、案例和逻辑推演。\n'
          '要求：\n'
          '1. 【结构脉络】根据视频的话题转换，将其划分为几个清晰的章节，每个章节必须标明时间跨度（如 `[01:00] - [15:30]`）。\n'
          '2. 【深度提取】在每个章节下，详细阐述其核心观点、使用的论据（如有案例请务必写出）。\n'
          '3. 【内在逻辑】分析各章节之间的关联，说明主讲人是如何一步步推导结论的。\n'
          '4. 【精粹总结】在末尾给出该视频的最终结论或可执行的启示。\n'
          '注意：全程必须高频使用 `[mm:ss]` 时间戳进行锚定，以便我随时点击溯源。',
    ),
  ];

  static List<AiPromptTemplate> getTemplates() {
    final raw = Pref.aiPromptTemplates;
    if (raw.isEmpty) return defaultTemplates;
    try {
      final list = jsonDecode(raw) as List;
      var templates = list
          .map((e) => AiPromptTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
      var changed = false;
      // Remove deprecated templates
      final beforeRemove = templates.length;
      templates.removeWhere((t) => t.name == '准备问答');
      if (templates.length != beforeRemove) changed = true;
      // Sync default templates: add missing, update changed content
      final defaultMap = {for (final t in defaultTemplates) t.name: t};
      for (var i = 0; i < templates.length; i++) {
        final defaultT = defaultMap[templates[i].name];
        if (defaultT != null && templates[i].prompt != defaultT.prompt) {
          templates[i] = defaultT;
          changed = true;
        }
      }
      final existingNames = templates.map((e) => e.name).toSet();
      for (final t in defaultTemplates) {
        if (!existingNames.contains(t.name)) {
          templates.add(t);
          changed = true;
        }
      }
      if (changed) saveTemplates(templates);
      return templates;
    } catch (_) {
      return defaultTemplates;
    }
  }

  static void saveTemplates(List<AiPromptTemplate> templates) {
    Pref.aiPromptTemplates = jsonEncode(templates.map((e) => e.toJson()).toList());
  }
}
