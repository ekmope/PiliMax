abstract final class CrashReportFilter {
  static bool shouldIgnore(Object error, [StackTrace? stackTrace]) {
    if (error is String && !_hasUsefulStack(stackTrace)) return true;

    final message = _safeText(error).trim().toLowerCase();
    if (message.isEmpty) return false;

    final knownDiagnostic =
        _sslSeekFailure.hasMatch(message) ||
        _ignoredMessageFragments.any(message.contains);
    if (!knownDiagnostic) return false;
    if (error is! String && _hasApplicationStack(stackTrace)) return false;
    return true;
  }

  static bool _hasUsefulStack(StackTrace? stackTrace) =>
      _safeText(stackTrace).trim().isNotEmpty;

  static bool _hasApplicationStack(StackTrace? stackTrace) =>
      _safeText(stackTrace).contains('package:PiliMax/');

  static String _safeText(Object? value) {
    if (value == null) return '';
    try {
      return value.toString();
    } catch (_) {
      return '';
    }
  }

  static final _sslSeekFailure = RegExp(r'\bssl\b.{0,32}\bseek failed\b');

  static const _ignoredMessageFragments = <String>[
    'ssl seek failed',
    'failed to open https://',
    'can not open external file https://',
    'seek failed (to ',
    'tcp: connection to tcp://',
    'tcp: failed to resolve hostname ',
    'tcp: ffurl_read returned ',
    'tcp: ffurl_write returned ',
    'tls: mbedtls_ssl_',
    'https: stream ends prematurely',
    'http: stream ends prematurely',
    'amediacodec:',
    'missing picture in access unit',
    'invalid nal unit size',
    'unsupported format for accessing property',
  ];
}
