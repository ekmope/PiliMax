import 'package:flutter/widgets.dart';

/// Mirrors the root Navigator stack so PiP can remove nested player routes
/// without relying on route-name prefixes or triggering didPopNext.
class PipRouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final index = _stack.indexOf(oldRoute);
      if (index >= 0) {
        if (newRoute != null) {
          _stack[index] = newRoute;
        } else {
          _stack.removeAt(index);
        }
        return;
      }
    }
    if (newRoute != null) {
      _stack.add(newRoute);
    }
  }

  /// Returns the consecutive player routes directly below [anchor], from
  /// newest to oldest. The first non-matching route stops the search.
  List<Route<dynamic>> routesBelowWhile(
    Route<dynamic> anchor,
    bool Function(Route<dynamic> route) test,
  ) {
    final result = <Route<dynamic>>[];
    for (var index = _stack.indexOf(anchor) - 1; index >= 0; index--) {
      final route = _stack[index];
      if (!test(route)) {
        break;
      }
      result.add(route);
    }
    return result;
  }
}

final pipRouteStackObserver = PipRouteStackObserver();
