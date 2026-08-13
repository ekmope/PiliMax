import 'dart:collection';

import 'package:PiliMax/pilimax/utils/log_redactor.dart';
import 'package:dio/dio.dart';

final class RequestErrorToastGate {
  RequestErrorToastGate({
    this.cooldown = const Duration(seconds: 3),
    this.maxRecentEntries = 64,
    this.maxConcurrent = 8,
    DateTime Function()? clock,
  }) : assert(maxRecentEntries > 0),
       assert(maxConcurrent > 0),
       _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final int maxRecentEntries;
  final int maxConcurrent;
  final DateTime Function() _clock;
  final LinkedHashMap<String, DateTime> _recent = LinkedHashMap();
  final Set<String> _inFlight = <String>{};

  bool tryAcquire(String key) {
    final now = _clock();
    _removeExpired(now);
    if (_inFlight.contains(key) || _inFlight.length >= maxConcurrent) {
      return false;
    }
    final lastShownAt = _recent[key];
    if (lastShownAt != null && now.difference(lastShownAt) < cooldown) {
      return false;
    }
    _inFlight.add(key);
    return true;
  }

  void release(String key) {
    if (!_inFlight.remove(key)) return;
    final now = _clock();
    _removeExpired(now);
    _recent
      ..remove(key)
      ..[key] = now;
    while (_recent.length > maxRecentEntries) {
      _recent.remove(_recent.keys.first);
    }
  }

  void _removeExpired(DateTime now) {
    _recent.removeWhere(
      (_, shownAt) =>
          shownAt.isAfter(now) || now.difference(shownAt) >= cooldown,
    );
  }
}

const _safeProxyConfigurationErrors = <String>{
  '系统代理配置无效：代理主机不能为空。请修正代理设置或关闭代理。',
  '系统代理配置无效：代理主机格式无效。请修正代理设置或关闭代理。',
  '系统代理配置无效：代理端口必须是 1 至 65535 的整数。请修正代理设置或关闭代理。',
};

String? safeLocalNetworkErrorMessage(Object? error) {
  if (error case StateError(:final message)) {
    final value = message.toString();
    if (_safeProxyConfigurationErrors.contains(value)) return value;
  }
  return null;
}

String requestErrorEndpoint(RequestOptions options) {
  final uri = options.uri;
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  final authority = host.isEmpty
      ? ''
      : uri.hasPort
      ? '$host:${uri.port}'
      : host;
  final path = uri.path.isEmpty ? '/' : uri.path;
  final endpoint = authority.isEmpty ? path : '$authority$path';
  return LogRedactor.redactText(
    '${options.method.toUpperCase()} $endpoint',
  );
}
