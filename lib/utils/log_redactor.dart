abstract final class LogRedactor {
  static const redacted = '[REDACTED]';

  static final RegExp _sensitiveKey = RegExp(
    r'^(authorization|proxy-authorization|cookie|set-cookie|x-api-key|x-auth-token|x-bili-(?:device|metadata|fawkes-req)-bin|x-bili-(?:aurora-eid|mid|gaia-vtoken)|gaia[_-]?vtoken|sessdata|bili_jct|buvid|buvid3|buvid4|csrf|csrf_token|tmp_token|token|device_token|access[_-]?(?:key|token)|accesskey|auth[_-]?token|session[_-]?token|refresh[_-]?token|refreshtoken|qrcode[_-]?key|captcha[_-]?key|verify[_-]?key|verify[_-]?code|sms[_-]?code|recaptcha[_-]?token|api[_-]?key|private[_-]?key|secret[_-]?key|client[_-]?secret|id[_-]?token|jwt|secret|password|passwd|pwd|keypassword|storepassword)$',
    caseSensitive: false,
  );

  static final RegExp _queryParam = RegExp(
    r'\b(SESSDATA|bili_jct|buvid|buvid3|buvid4|gaia_vtoken|gaiaVtoken|gaia-vtoken|csrf|csrf_token|tmp_token|token|device_token|access_key|accessKey|access_token|accessToken|auth_token|authToken|session_token|sessionToken|refresh_token|refreshToken|qrcode_key|captcha_key|verify_key|verify_code|recaptcha_token|api_key|apiKey|private_key|privateKey|secret_key|secretKey|client_secret|clientSecret|id_token|idToken|jwt|code|password|passwd|pwd)=([^&\s;,]+)',
    caseSensitive: false,
  );
  static final RegExp _header = RegExp(
    r'\b(authorization|proxy-authorization|cookie|set-cookie|x-api-key|x-auth-token)\s*[:=]\s*([^\r\n]+)',
    caseSensitive: false,
  );
  static final RegExp _jsonString = RegExp(
    r'("?(?:SESSDATA|bili_jct|buvid|buvid3|buvid4|gaia_vtoken|gaiaVtoken|gaia-vtoken|csrf|csrf_token|tmp_token|token|device_token|access_key|accessKey|access_token|accessToken|auth_token|authToken|session_token|sessionToken|refresh_token|refreshToken|qrcode_key|captcha_key|verify_key|verify_code|recaptcha_token|api_key|apiKey|private_key|privateKey|secret_key|secretKey|client_secret|clientSecret|id_token|idToken|jwt|password|passwd|pwd|authorization|proxy-authorization|cookie|x-api-key|x-auth-token)"?\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );
  static final RegExp _structuredValue = RegExp(
    r'''(["']?(?:SESSDATA|bili_jct|buvid|buvid3|buvid4|gaia_vtoken|gaiaVtoken|gaia-vtoken|csrf|csrf_token|tmp_token|token|device_token|access_key|accessKey|access_token|accessToken|auth_token|authToken|session_token|sessionToken|refresh_token|refreshToken|qrcode_key|captcha_key|verify_key|verify_code|sms_code|recaptcha_token|api_key|apiKey|private_key|privateKey|secret_key|secretKey|client_secret|clientSecret|id_token|idToken|jwt|password|passwd|pwd|authorization|proxy-authorization|cookie|x-api-key|x-auth-token)["']?\s*:\s*)(?:"[^"]*"|'[^']*'|[^,}\]\r\n]+)''',
    caseSensitive: false,
  );
  static final RegExp _shortSecretCode = RegExp(
    r'''\b(code|verify_code|sms_code)\s*[:=]\s*["']?(\d{6,8})''',
    caseSensitive: false,
  );
  static final RegExp _biliIdentityField = RegExp(
    r'''(["']?(?:x-bili-(?:device|metadata|fawkes-req)-bin|x-bili-(?:aurora-eid|mid|gaia-vtoken))["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^,}\]\r\n]+)''',
    caseSensitive: false,
  );
  static final RegExp _quotedAbsolutePath = RegExp(
    r'''(["'])(?:(?:[A-Za-z]:[\\/]|\\\\[^\\/\r\n]+[\\/][^\\/\r\n]+[\\/]?)[^"'\r\n]*|/(?!/)[^"'\r\n]*)\1''',
    caseSensitive: false,
  );
  static final RegExp _windowsAbsolutePath = RegExp(
    r'''(^|[\s=:\[({,"'])(?:[A-Za-z]:[\\/]|\\\\[^\\/\r\n]+[\\/][^\\/\r\n]+[\\/]?)[^\r\n,;)\]}"']*''',
    multiLine: true,
  );
  static final RegExp _unixAbsolutePath = RegExp(
    r'''(^|[\s=:\[({,"'])/(?!/)[^\r\n,;)\]}"']*''',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _contentUri = RegExp(
    r'\bcontent://[^\s]+',
    caseSensitive: false,
  );
  static final RegExp _fileUri = RegExp(
    r'\bfile://[^\s]+',
    caseSensitive: false,
  );
  static final RegExp _httpUrl = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  );

  static Object? redact(Object? value, {Object? key}) {
    if (key != null && _sensitiveKey.hasMatch(key.toString())) {
      return redacted;
    }
    return switch (value) {
      String() => redactText(value),
      Map() => {
        for (final entry in value.entries)
          entry.key: redact(entry.value, key: entry.key),
      },
      Iterable() => [for (final item in value) redact(item)],
      _ => value,
    };
  }

  static String redactText(String value) {
    return value
        .replaceAllMapped(_httpUrl, (match) => _redactHttpUrl(match.group(0)!))
        .replaceAllMapped(_queryParam, (match) => '${match.group(1)}=$redacted')
        .replaceAllMapped(
          _jsonString,
          (match) => '${match.group(1)}"$redacted"',
        )
        .replaceAllMapped(
          _structuredValue,
          (match) => '${match.group(1)}"$redacted"',
        )
        .replaceAllMapped(_header, (match) => '${match.group(1)}: $redacted')
        .replaceAllMapped(
          _shortSecretCode,
          (match) => '${match.group(1)}=$redacted',
        )
        .replaceAllMapped(
          _biliIdentityField,
          (match) => '${match.group(1)}"$redacted"',
        )
        .replaceAllMapped(
          _quotedAbsolutePath,
          (match) => '${match.group(1)}[local-path]${match.group(1)}',
        )
        .replaceAllMapped(
          _windowsAbsolutePath,
          (match) => '${match.group(1)}[local-path]',
        )
        .replaceAllMapped(
          _unixAbsolutePath,
          (match) => '${match.group(1)}[local-path]',
        )
        .replaceAll(_contentUri, '[content-uri]')
        .replaceAll(_fileUri, '[file-uri]');
  }

  static String _redactHttpUrl(String value) {
    final queryIndex = value.indexOf('?');
    final fragmentIndex = value.indexOf('#');
    var suffixIndex = queryIndex;
    if (suffixIndex == -1 ||
        (fragmentIndex != -1 && fragmentIndex < suffixIndex)) {
      suffixIndex = fragmentIndex;
    }
    final withoutSuffix = suffixIndex == -1
        ? value
        : value.substring(0, suffixIndex);
    final uri = Uri.tryParse(withoutSuffix);
    if (uri == null || !uri.hasAuthority) return value;
    final sanitized = uri.replace(userInfo: '').toString();
    return suffixIndex == -1 ? sanitized : '$sanitized?$redacted';
  }
}
