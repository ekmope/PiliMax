import 'dart:convert' show jsonDecode, utf8;

class GeetestValidationException implements Exception {
  const GeetestValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class GeetestSecurity {
  static const int maxLinuxMessageLength = 16 * 1024;
  static const int maxConfigResponseLength = 64 * 1024;
  static const int _minTokenLength = 8;
  static const int _maxTokenLength = 1024;
  static const Set<String> _officialDomains = {
    'geetest.com',
    'geevisit.com',
  };

  static bool isAllowedRemoteUri(Uri? uri) {
    if (uri == null || uri.scheme.toLowerCase() != 'https') {
      return false;
    }
    try {
      if (uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443)) {
        return false;
      }
      final host = uri.host.toLowerCase();
      return _officialDomains.any(
        (domain) => host == domain || host.endsWith('.$domain'),
      );
    } on FormatException {
      return false;
    }
  }

  static bool isValidBootstrapToken(String value) =>
      _isValidToken(value, maxLength: _maxTokenLength);

  static Map<String, String> validateResult(
    Object? value, {
    required String expectedChallenge,
  }) {
    if (value is! Map) {
      throw const GeetestValidationException('极验回调格式无效');
    }
    final challenge = _readToken(value, 'geetest_challenge');
    final validate = _readToken(value, 'geetest_validate');
    final seccode = _readToken(value, 'geetest_seccode');
    if (challenge != expectedChallenge) {
      throw const GeetestValidationException('极验 challenge 不匹配');
    }
    return {
      'geetest_challenge': challenge,
      'geetest_validate': validate,
      'geetest_seccode': seccode,
    };
  }

  static Map<String, String> decodeLinuxResult(
    String json, {
    required String expectedChallenge,
  }) {
    if (json.length > maxLinuxMessageLength ||
        utf8.encode(json).length > maxLinuxMessageLength) {
      throw const GeetestValidationException('极验回调数据过大');
    }
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      throw const GeetestValidationException('极验回调 JSON 无效');
    }
    return validateResult(value, expectedChallenge: expectedChallenge);
  }

  static String _readToken(Map value, String key) {
    final token = value[key];
    if (token is! String || !_isValidToken(token)) {
      throw GeetestValidationException('极验字段 $key 无效');
    }
    return token;
  }

  static bool _isValidToken(
    String value, {
    int maxLength = _maxTokenLength,
  }) {
    if (value.length < _minTokenLength || value.length > maxLength) {
      return false;
    }
    if (value.trim() != value) {
      return false;
    }
    for (final codeUnit in value.codeUnits) {
      if (codeUnit < 0x20 || codeUnit == 0x7f) {
        return false;
      }
    }
    return true;
  }
}
