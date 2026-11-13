import 'package:PiliMax/utils/redirect_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes only the path of query and fragment short links', () {
    final uri = redirectRequestUri('https://b23.tv/a?t=60#position');
    expect(uri.toString(), 'https://b23.tv/a/?t=60#position');
    expect(uri.queryParameters['t'], '60');
  });

  test('relative redirect uses the actual request directory', () {
    final request = redirectRequestUri('https://example.com/path');
    expect(request.resolve('next').toString(), 'https://example.com/path/next');
    expect(
      request.resolve('../video?a=1').toString(),
      'https://example.com/video?a=1',
    );
  });

  test('already normalized and escaped paths keep their data', () {
    expect(
      redirectRequestUri('https://example.com/a%2Fb/?q=a%2Fb').toString(),
      'https://example.com/a%2Fb/?q=a%2Fb',
    );
    expect(
      redirectRequestUri('https://example.com/a%2Fb?q=a%2Fb').toString(),
      'https://example.com/a%2Fb/?q=a%2Fb',
    );
  });

  test('accepts pasted scheme-less short links and rejects search text', () {
    expect(
      redirectRequestUri('b23.tv/AbC1234?t=60#position').toString(),
      'https://b23.tv/AbC1234/?t=60#position',
    );
    expect(
      redirectRequestUri('//b23.tv/AbC1234').toString(),
      'https://b23.tv/AbC1234/',
    );
    expect(
      () => redirectRequestUri('ordinary search text'),
      throwsFormatException,
    );
    expect(
      () => redirectRequestUri('javascript:alert(1)'),
      throwsFormatException,
    );
  });
}
