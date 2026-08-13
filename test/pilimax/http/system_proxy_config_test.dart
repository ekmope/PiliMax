import 'package:PiliMax/pilimax/http/system_proxy_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemProxyConfig', () {
    test('keeps a disabled proxy distinct from an invalid proxy', () {
      final config = SystemProxyConfig.resolve(
        enabled: false,
        host: '',
        port: '',
      );

      expect(config.isDisabled, isTrue);
      expect(config.isInvalid, isFalse);
    });

    test('normalizes a valid host and port', () {
      final config = SystemProxyConfig.resolve(
        enabled: true,
        host: ' 127.0.0.1 ',
        port: ' 7890 ',
      );

      expect(config.isValid, isTrue);
      expect(config.host, '127.0.0.1');
      expect(config.port, 7890);
      expect(config.httpProxyDirective, 'PROXY 127.0.0.1:7890');
      expect(config.proxyUri, Uri.parse('http://127.0.0.1:7890'));
    });

    test('accepts port boundaries', () {
      for (final port in ['1', '65535']) {
        expect(
          SystemProxyConfig.resolve(
            enabled: true,
            host: 'localhost',
            port: port,
          ).isValid,
          isTrue,
        );
      }
    });

    test('rejects missing and out-of-range ports', () {
      for (final port in ['', 'abc', '0', '-1', '65536']) {
        final config = SystemProxyConfig.resolve(
          enabled: true,
          host: 'localhost',
          port: port,
        );

        expect(config.isInvalid, isTrue, reason: 'port=$port');
        expect(config.issue, SystemProxyConfigIssue.invalidPort);
      }
    });

    test('rejects missing hosts and hosts containing a scheme or path', () {
      expect(
        SystemProxyConfig.resolve(
          enabled: true,
          host: '   ',
          port: '7890',
        ).issue,
        SystemProxyConfigIssue.emptyHost,
      );
      for (final host in [
        'http://localhost',
        'localhost/proxy',
        'localhost:7890',
        '[localhost]',
        '[::1',
      ]) {
        expect(
          SystemProxyConfig.resolve(
            enabled: true,
            host: host,
            port: '7890',
          ).issue,
          SystemProxyConfigIssue.invalidHost,
        );
      }
    });

    test('normalizes bracketed IPv6 for both adapters', () {
      final config = SystemProxyConfig.resolve(
        enabled: true,
        host: '[::1]',
        port: '7890',
      );

      expect(config.isValid, isTrue);
      expect(config.host, '::1');
      expect(config.httpProxyDirective, 'PROXY [::1]:7890');
      expect(config.proxyUri, Uri.parse('http://[::1]:7890'));
    });
  });
}
