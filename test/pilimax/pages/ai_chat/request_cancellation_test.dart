import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pilimax/forks/http/init.dart' as http;
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/pilimax/pages/ai_chat/controller.dart';
import 'package:PiliMax/pilimax/services/ai_chat/ai_chat_service.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _SubtitleVideoController extends GetxController
    implements VideoDetailController {
  @override
  final subtitles = <Subtitle>[
    Subtitle(lan: 'zh', subtitleUrl: '//subtitle.example.invalid/body'),
  ].obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SubtitleAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final body = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    started.complete();
    return body.future;
  }

  @override
  void close({bool force = false}) {}
}

class _Exchange {
  _Exchange(this.request, this.body) {
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.bufferOutput = false;
  }

  final HttpRequest request;
  final Map<String, dynamic> body;

  Future<void> data(Object value) async {
    request.response.write('data: ${jsonEncode(value)}\n\n');
    await request.response.flush();
  }

  Future<void> content(String value, {String? reasoning}) => data({
    'choices': [
      {
        'delta': {
          'content': value,
          'reasoning_content': ?reasoning,
        },
      },
    ],
  });

  Future<void> finish() async {
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  }

  Future<void> finishAfterCancellation() async {
    try {
      await content('迟到内容');
      await finish();
    } on IOException {
      // 正常情况下客户端已关闭连接；模拟迟到服务器仍然尝试发送。
    }
  }
}

class _Server {
  _Server(this.server) {
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      final exchange = _Exchange(request, body as Map<String, dynamic>);
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(exchange);
      } else {
        _pending.add(exchange);
      }
    });
  }

  final HttpServer server;
  final _pending = <_Exchange>[];
  final _waiters = <Completer<_Exchange>>[];

  String get url => 'http://127.0.0.1:${server.port}/v1';

  Future<_Exchange> next() {
    if (_pending.isNotEmpty) return Future.value(_pending.removeAt(0));
    final waiter = Completer<_Exchange>();
    _waiters.add(waiter);
    return waiter.future.timeout(const Duration(seconds: 5));
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('请求状态未在期限内到达');
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box<dynamic> settings;
  late _Server server;
  late AiChatController controller;
  late HttpOverrides? previousOverrides;

  setUpAll(() async {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _RealHttpOverrides();
    directory = await Directory.systemTemp.createTemp(
      'pilimax-ai-cancel-test-',
    );
    Hive.init(directory.path);
    settings = await Hive.openBox<dynamic>('setting');
    GStorage.setting = settings;
  });

  setUp(() async {
    await settings.clear();
    server = _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    await settings.putAll({
      SettingBoxKey.aiApiUrl: server.url,
      SettingBoxKey.aiModel: 'test-model',
      SettingBoxKey.aiApiKey: 'test-api-secret',
      SettingBoxKey.enableLog: false,
      SettingBoxKey.retryCount: 0,
    });
    // 仅测试不依赖视频信息的 follow-up；无需创建播放器或注册视频页。
    controller = AiChatController(heroTag: 'ai-cancellation-test');
  });

  tearDown(() async {
    controller.onDelete();
    await server.server.close(force: true);
  });

  tearDownAll(() async {
    await settings.close();
    await directory.delete(recursive: true);
    HttpOverrides.global = previousOverrides;
  });

  test('停止保留部分正文，旧 finally 不结束立即重发的新请求', () async {
    final first = controller.sendFollowUp('第一问');
    final oldExchange = await server.next();
    await oldExchange.content('已有正文');
    await _until(() => controller.messages.last.content == '已有正文');
    final oldResponse = controller.messages.last;

    controller.cancelRequest();
    expect(controller.isRequesting.value, isFalse);
    expect(oldResponse.isStreaming, isFalse);
    final second = controller.sendFollowUp('第二问');
    expect(controller.isRequesting.value, isTrue);
    final currentExchange = await server.next();
    await oldExchange.finishAfterCancellation();
    await first;

    expect(controller.isRequesting.value, isTrue);
    expect(oldResponse.content, '已有正文');
    expect(controller.messages.last.isStreaming, isTrue);
    await currentExchange.content('新回答');
    await currentExchange.finish();
    await second;
    expect(controller.messages.last.content, '新回答');
    expect(controller.isRequesting.value, isFalse);
  });

  test('停止保留纯思考并冻结耗时，空助手占位会移除', () async {
    final first = controller.sendFollowUp('思考');
    final exchange = await server.next();
    await exchange.content('', reasoning: '已有推理');
    await _until(() => controller.messages.last.hasReasoning);
    final response = controller.messages.last;
    controller.cancelRequest();
    await first;
    expect(controller.messages, contains(response));
    expect(response.isStreaming, isFalse);
    expect(response.reasoningDurationSeconds, isNotNull);

    final second = controller.sendFollowUp('尚未返回内容');
    await server.next();
    final empty = controller.messages.last;
    controller.cancelRequest();
    await second;
    expect(controller.messages, isNot(contains(empty)));
    expect(controller.messages.last.role, 'user');
  });

  test('重置阻止旧请求回写，随后可正常发送', () async {
    final first = controller.sendFollowUp('旧问题');
    final oldExchange = await server.next();
    controller.clearMessages();
    expect(controller.messages, isEmpty);
    expect(controller.hasVideoContext.value, isFalse);
    expect(controller.isRequesting.value, isFalse);
    final second = controller.sendFollowUp('重置后的问题');
    final exchange = await server.next();
    await oldExchange.finishAfterCancellation();
    await first;
    expect(controller.messages.map((message) => message.content), [
      '重置后的问题',
      '',
    ]);
    expect(controller.isRequesting.value, isTrue);
    await exchange.content('重置后的回答');
    await exchange.finish();
    await second;
    expect(controller.messages.last.content, '重置后的回答');
  });

  test('销毁 controller 取消请求且禁止再发', () async {
    final pending = controller.sendFollowUp('离开视频页');
    final exchange = await server.next();
    controller.onDelete();
    await exchange.finishAfterCancellation();
    await pending;
    final count = controller.messages.length;
    await controller.sendFollowUp('不会发送');
    expect(controller.isClosed, isTrue);
    expect(controller.messages.length, count);
    expect(controller.isRequesting.value, isFalse);
  });

  test('停止不冲刷半截 think 标签，旧流不产生额外正文', () async {
    final token = CancelToken();
    final received = <AiStreamDelta>[];
    final result =
        AiChatService.streamChat(
          messages: const [
            {'role': 'user', 'content': 'test'},
          ],
          cancelToken: token,
        ).forEach(received.add).catchError((Object error) {
          expect(
            error,
            isA<DioException>().having(CancelToken.isCancel, '取消', true),
          );
        });
    final exchange = await server.next();
    await exchange.content('正文<th');
    await _until(() => received.isNotEmpty);
    token.cancel('stop');
    await result;
    expect(received.map((delta) => delta.contentDelta).join(), '正文');
  });

  test('字幕加载进入忙状态，重置后的迟到字幕不能恢复旧上下文', () async {
    const tag = 'ai-cancellation-test';
    Get.put<VideoDetailController>(_SubtitleVideoController(), tag: tag);
    addTearDown(() => Get.delete<VideoDetailController>(tag: tag));
    controller.onInit();
    http.Request();
    final adapter = _SubtitleAdapter();
    final originalAdapter = http.Request.dio.httpClientAdapter;
    http.Request.dio.httpClientAdapter = adapter;
    addTearDown(() => http.Request.dio.httpClientAdapter = originalAdapter);

    final loading = controller.loadVideoContext();
    await adapter.started.future;
    expect(controller.isRequesting.value, isTrue);
    await controller.sendFollowUp('载入期间不可发出');
    expect(controller.messages, isEmpty);

    controller.clearMessages();
    final resend = controller.sendFollowUp('重置后立即发出');
    final exchange = await server.next();
    adapter.body.complete(
      ResponseBody.fromString(
        jsonEncode({
          'body': [
            {'from': 0, 'content': '旧字幕'},
          ],
        }),
        HttpStatus.ok,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    await loading;
    expect(controller.hasVideoContext.value, isFalse);
    expect(controller.messages.any((message) => message.isDivider), isFalse);
    expect(controller.isRequesting.value, isTrue);
    await exchange.content('新回答');
    await exchange.finish();
    await resend;
    expect(controller.messages.last.content, '新回答');
  });

  test('endpoint 保留 query，SSE 错误仍可见且对 query/API key 脱敏', () async {
    Pref.aiApiUrl = '${server.url}?credential=query-secret#fragment';
    final result = AiChatService.streamChat(
      messages: const [
        {'role': 'user', 'content': 'test'},
      ],
      cancelToken: CancelToken(),
    ).toList();
    final expectation = expectLater(
      result,
      throwsA(
        isA<AiApiException>()
            .having(
              (error) => error.url,
              '安全地址',
              '${server.url}/chat/completions',
            )
            .having((error) => error.detail, '错误内容', contains('服务器返回错误'))
            .having(
              (error) => error.detail,
              'query 脱敏',
              isNot(contains('query-secret')),
            )
            .having(
              (error) => error.detail,
              'key 脱敏',
              isNot(contains('test-api-secret')),
            ),
      ),
    );
    final exchange = await server.next();
    expect(exchange.request.uri.path, '/v1/chat/completions');
    expect(exchange.request.uri.queryParameters['credential'], 'query-secret');
    expect(exchange.body['model'], 'test-model');
    await exchange.data({
      'error': {'message': 'query-secret test-api-secret'},
    });
    await exchange.request.response.close();
    await expectation;
  });

  test('非法 JSON 仍按我方严格解析报错', () async {
    final result = AiChatService.streamChat(
      messages: const [
        {'role': 'user', 'content': 'test'},
      ],
      cancelToken: CancelToken(),
    ).toList();
    final expectation = expectLater(
      result,
      throwsA(
        isA<AiApiException>().having(
          (error) => error.detail,
          '格式错误',
          contains('流式响应格式错误'),
        ),
      ),
    );
    final exchange = await server.next();
    exchange.request.response.write('data: {invalid\n\n');
    await exchange.request.response.close();
    await expectation;
  });

  test('只有 DONE 的空 SSE 仍按我方策略报错', () async {
    final result = AiChatService.streamChat(
      messages: const [
        {'role': 'user', 'content': 'test'},
      ],
      cancelToken: CancelToken(),
    ).toList();
    final expectation = expectLater(
      result,
      throwsA(
        isA<AiApiException>().having(
          (error) => error.detail,
          '空内容',
          contains('未包含有效内容'),
        ),
      ),
    );
    final exchange = await server.next();
    await exchange.finish();
    await expectation;
  });

  test('字幕主动取消保留取消异常，不转为空数据或进入通用报错处理', () async {
    final token = CancelToken()..cancel('停止字幕');
    await expectLater(
      VideoHttp.fetchSubtitleBody(
        '//example.invalid/subtitle',
        cancelToken: token,
      ),
      throwsA(isA<DioException>().having(CancelToken.isCancel, '取消', true)),
    );
  });
}
