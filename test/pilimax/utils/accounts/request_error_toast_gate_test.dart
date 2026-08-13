import 'package:PiliMax/pilimax/utils/accounts/account_manager/request_error_toast_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestErrorToastGate', () {
    late DateTime now;
    late RequestErrorToastGate gate;

    setUp(() {
      now = DateTime.utc(2026);
      gate = RequestErrorToastGate(
        clock: () => now,
        maxRecentEntries: 2,
        maxConcurrent: 2,
      );
    });

    test('allows one in-flight toast per endpoint', () {
      expect(gate.tryAcquire('GET api.example.test/x'), isTrue);
      expect(gate.tryAcquire('GET api.example.test/x'), isFalse);

      gate.release('GET api.example.test/x');
      expect(gate.tryAcquire('GET api.example.test/x'), isFalse);

      now = now.add(const Duration(seconds: 3));
      expect(gate.tryAcquire('GET api.example.test/x'), isTrue);
    });

    test('limits concurrent and retained endpoint entries', () {
      expect(gate.tryAcquire('one'), isTrue);
      expect(gate.tryAcquire('two'), isTrue);
      expect(gate.tryAcquire('three'), isFalse);
      gate
        ..release('one')
        ..release('two');

      now = now.add(const Duration(seconds: 3));
      expect(gate.tryAcquire('three'), isTrue);
      gate.release('three');
      expect(gate.tryAcquire('one'), isTrue);
    });

    test('discards a cooldown baseline after the clock moves backwards', () {
      expect(gate.tryAcquire('endpoint'), isTrue);
      gate.release('endpoint');

      now = now.subtract(const Duration(minutes: 1));

      expect(gate.tryAcquire('endpoint'), isTrue);
    });
  });

  group('requestErrorEndpoint', () {
    test('contains only method, host, explicit port and path', () {
      final options = RequestOptions(
        path:
            'https://person:secret@example.test:8443/path/video'
            '?access_key=secret&normal=value#fragment',
        method: 'post',
      );

      final endpoint = requestErrorEndpoint(options);

      expect(endpoint, 'POST example.test:8443/path/video');
      expect(endpoint, isNot(contains('person')));
      expect(endpoint, isNot(contains('secret')));
      expect(endpoint, isNot(contains('normal')));
      expect(endpoint, isNot(contains('https')));
    });
  });

  group('safeLocalNetworkErrorMessage', () {
    test('allows only fixed local proxy configuration messages', () {
      const safeMessage = '系统代理配置无效：代理端口必须是 1 至 65535 的整数。请修正代理设置或关闭代理。';

      expect(
        safeLocalNetworkErrorMessage(StateError(safeMessage)),
        safeMessage,
      );
      expect(
        safeLocalNetworkErrorMessage(
          StateError('系统代理配置无效：access_key=secret。请修正代理设置或关闭代理。'),
        ),
        isNull,
      );
      expect(safeLocalNetworkErrorMessage(Exception(safeMessage)), isNull);
    });
  });
}
