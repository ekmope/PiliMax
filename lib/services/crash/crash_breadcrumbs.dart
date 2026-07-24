import 'dart:collection';

import 'package:PiliMax/utils/log_redactor.dart';
import 'package:flutter/widgets.dart';

abstract final class CrashBreadcrumbs {
  static const _maxEvents = 40;
  static final Queue<String> _events = Queue<String>();

  static void record(String event) {
    final sanitized = LogRedactor.redactText(event).trim();
    if (sanitized.isEmpty) return;
    if (_events.length >= _maxEvents) {
      _events.removeFirst();
    }
    final entry = '${_formatTime(DateTime.now())}  ${_truncate(sanitized)}';
    _events.addLast(entry);
  }

  static List<String> snapshot() => List.unmodifiable(_events);

  static String _truncate(String value) {
    if (value.length <= 180) return value;
    return value.substring(0, 180);
  }

  static String _formatTime(DateTime time) {
    return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}:'
        '${_twoDigits(time.second)}.${_threeDigits(time.millisecond)}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _threeDigits(int value) => value.toString().padLeft(3, '0');
}

class CrashBreadcrumbNavigatorObserver extends NavigatorObserver {
  static String currentRoute = '';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = _routeName(route);
    CrashBreadcrumbs.record('Route push $currentRoute');
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    currentRoute = _routeName(previousRoute);
    CrashBreadcrumbs.record('Route pop ${_routeName(route)}');
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    currentRoute = _routeName(newRoute);
    CrashBreadcrumbs.record(
      'Route replace ${_routeName(oldRoute)} -> ${_routeName(newRoute)}',
    );
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  String _routeName(Route<dynamic>? route) {
    return route?.settings.name?.isNotEmpty == true
        ? route!.settings.name!
        : route?.runtimeType.toString() ?? 'unknown';
  }
}
