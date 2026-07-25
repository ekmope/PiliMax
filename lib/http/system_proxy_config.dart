enum SystemProxyConfigIssue { emptyHost, invalidHost, invalidPort }

final class SystemProxyConfig {
  const SystemProxyConfig._({
    required this.requested,
    required this.host,
    required this.port,
    required this.issue,
  });

  factory SystemProxyConfig.resolve({
    required bool enabled,
    required String host,
    required String port,
  }) {
    if (!enabled) {
      return const SystemProxyConfig._(
        requested: false,
        host: '',
        port: null,
        issue: null,
      );
    }

    var normalizedHost = host.trim();
    if (normalizedHost.isEmpty) {
      return const SystemProxyConfig._(
        requested: true,
        host: '',
        port: null,
        issue: SystemProxyConfigIssue.emptyHost,
      );
    }

    final startsWithBracket = normalizedHost.startsWith('[');
    final endsWithBracket = normalizedHost.endsWith(']');
    if (startsWithBracket != endsWithBracket) {
      return SystemProxyConfig._(
        requested: true,
        host: normalizedHost,
        port: null,
        issue: SystemProxyConfigIssue.invalidHost,
      );
    }
    if (startsWithBracket) {
      normalizedHost = normalizedHost.substring(1, normalizedHost.length - 1);
      if (!normalizedHost.contains(':')) {
        return SystemProxyConfig._(
          requested: true,
          host: normalizedHost,
          port: null,
          issue: SystemProxyConfigIssue.invalidHost,
        );
      }
    }
    if (!_isValidHost(normalizedHost)) {
      return SystemProxyConfig._(
        requested: true,
        host: normalizedHost,
        port: null,
        issue: SystemProxyConfigIssue.invalidHost,
      );
    }

    final normalizedPort = int.tryParse(port.trim());
    if (normalizedPort == null ||
        normalizedPort < 1 ||
        normalizedPort > 65535) {
      return SystemProxyConfig._(
        requested: true,
        host: normalizedHost,
        port: null,
        issue: SystemProxyConfigIssue.invalidPort,
      );
    }

    return SystemProxyConfig._(
      requested: true,
      host: normalizedHost,
      port: normalizedPort,
      issue: null,
    );
  }

  final bool requested;
  final String host;
  final int? port;
  final SystemProxyConfigIssue? issue;

  bool get isDisabled => !requested;
  bool get isValid => requested && issue == null;
  bool get isInvalid => requested && issue != null;

  String get validationMessage => switch (issue) {
    SystemProxyConfigIssue.emptyHost => '代理主机不能为空',
    SystemProxyConfigIssue.invalidHost => '代理主机格式无效',
    SystemProxyConfigIssue.invalidPort => '代理端口必须是 1 至 65535 的整数',
    null => '',
  };

  String get httpProxyDirective {
    _checkValid();
    final authority = host.contains(':') ? '[$host]:$port' : '$host:$port';
    return 'PROXY $authority';
  }

  Uri get proxyUri {
    _checkValid();
    return Uri(scheme: 'http', host: host, port: port);
  }

  void _checkValid() {
    if (!isValid) {
      throw StateError('A valid system proxy configuration is required.');
    }
  }

  static bool _isValidHost(String host) {
    if (host.isEmpty || RegExp(r'[\s/@?#]').hasMatch(host)) return false;
    if (host.contains(':')) {
      try {
        Uri.parseIPv6Address(host);
        return true;
      } on FormatException {
        return false;
      }
    }
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(host);
  }
}
