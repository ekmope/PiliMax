import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/models/common/video/source_type.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:get/get.dart';

abstract final class RouteRestoreService {
  static const _version = 1;
  static const _validDuration = Duration(hours: 24);
  static const _lifecycleChannel = MethodChannel(
    'com.PiliMax.android/route_restore_lifecycle',
  );
  static const _restorableRoutes = {
    '/',
    '/videoV',
    '/liveRoom',
    '/member',
    '/searchResult',
    '/fav',
    '/favDetail',
    '/history',
    '/later',
    '/download',
    '/dynamics',
  };
  static const _mainNavigationNames = {'home', 'dynamics', 'mine'};
  static const _homeTabNames = {
    'live',
    'rcmd',
    'hot',
    'rank',
    'bangumi',
    'cinema',
  };

  static _RouteRestorePhase _phase = _RouteRestorePhase.startup;
  static RestorableRoute? _latestRoute;
  static MainRestoreState? _latestMainState;
  static Future<void> _storageQueue = Future<void>.value();
  static Future<bool>? _startupRestoreFuture;

  static const _nativeDecisionRetryDelays = [
    Duration(milliseconds: 80),
    Duration(milliseconds: 160),
    Duration(milliseconds: 280),
    Duration(milliseconds: 480),
  ];

  static bool get _enabled =>
      Platform.isAndroid && Pref.enableAndroidRouteRestore;

  static void onRouteChanged(Routing? routing) {
    if (!_enabled || _phase != _RouteRestorePhase.ready || routing == null) {
      return;
    }
    if (routing.route is! GetPageRoute) return;
    final route = _normalizeRoute(routing.current);
    if (route.isEmpty || !route.startsWith('/')) return;
    if (route == '/') {
      if (_latestMainState case final mainState?) {
        final restorable = RestorableRoute(
          route: route,
          mainState: mainState,
        );
        _latestRoute = restorable;
        unawaited(_save(restorable));
      }
      return;
    }
    if (!_restorableRoutes.contains(route)) return;

    final routeState = _buildRoute(route);
    if (routeState == null) {
      unawaited(clear());
      return;
    }
    final restorable = _withMainState(routeState);
    _latestRoute = restorable;
    unawaited(_save(restorable));
  }

  static void captureCurrentRoute() {
    if (!_enabled || _phase != _RouteRestorePhase.ready) return;
    final route = _normalizeRoute(Get.currentRoute);
    if (route.isEmpty || route == '/' || !_restorableRoutes.contains(route)) {
      return;
    }

    final routeState = _buildRoute(route);
    if (routeState == null) {
      unawaited(clear());
      return;
    }
    final restorable = _withMainState(routeState);
    _latestRoute = restorable;
    unawaited(_save(restorable));
  }

  static Future<void> updateMainState({
    required String navigation,
    String? homeTab,
  }) {
    if (!_enabled) return Future<void>.value();
    final mainState = _parseMainState(navigation, homeTab);
    if (mainState == null) return Future<void>.value();
    _latestMainState = mainState;
    if (_phase != _RouteRestorePhase.ready ||
        _normalizeRoute(Get.currentRoute) != '/') {
      return Future<void>.value();
    }
    final route = RestorableRoute(route: '/', mainState: mainState);
    _latestRoute = route;
    return _save(route);
  }

  static Future<void> saveLatestRoute() async {
    final latestRoute = _latestRoute;
    if (!_enabled || latestRoute == null) return;
    await _save(latestRoute);
  }

  static Future<void> clear() {
    _latestRoute = null;
    _latestMainState = null;
    return _enqueueStorage(
      () => GStorage.localCache.deleteAll([
        LocalCacheKey.lastAndroidRouteRestoreState,
        LocalCacheKey.lastAndroidRouteRestoreTime,
      ]),
    );
  }

  static Future<void> markIntentionalExit() async {
    await _markNativeLifecycleEvent('markIntentionalExit');
    await _ignoreStorageErrors(clear());
  }

  static Future<void> handleTaskRemoved() async {
    await _markNativeLifecycleEvent('markTaskRemoved');
    await _ignoreStorageErrors(clear());
  }

  static Future<void> saveVideoRoute(Map<dynamic, dynamic> arguments) {
    if (!_enabled || !_isCurrentVideoRoute(arguments)) {
      return Future<void>.value();
    }
    final storableArguments = _videoArguments(arguments);
    if (storableArguments == null) {
      return Future<void>.value();
    }
    final route = RestorableRoute(
      route: '/videoV',
      arguments: storableArguments,
      mainState: _latestMainState,
    );
    _latestRoute = route;
    return _save(route);
  }

  static Future<bool> restoreIfNeeded({
    required void Function(MainRestoreState state) restoreMainState,
  }) {
    if (_startupRestoreFuture case final future?) {
      return future;
    }
    if (_phase != _RouteRestorePhase.startup) {
      return Future<bool>.value(true);
    }
    return _startupRestoreFuture = _restoreIfNeeded(
      restoreMainState: restoreMainState,
    );
  }

  /// Completes after the one-time Android route-restoration decision.
  ///
  /// Startup overlays use this to avoid racing the restored destination. The
  /// bounded asynchronous wait also covers the first frame before MainPage has
  /// called [restoreIfNeeded]; it never blocks the Android main thread.
  static Future<void> waitForStartupRestore() async {
    if (!_enabled || _phase == _RouteRestorePhase.ready) return;
    for (
      var attempt = 0;
      attempt < 125 && _startupRestoreFuture == null;
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (_startupRestoreFuture case final future?) {
      await future;
    }
  }

  static Future<bool> _restoreIfNeeded({
    required void Function(MainRestoreState state) restoreMainState,
  }) async {
    _phase = _RouteRestorePhase.checking;
    if (!_enabled) {
      _phase = _RouteRestorePhase.ready;
      return true;
    }

    try {
      final decision = await _getNativeRestoreDecision();
      switch (decision) {
        case _NativeRestoreDecision.restore:
          break;
        case _NativeRestoreDecision.reject:
          return _rejectRestoreState();
        case _NativeRestoreDecision.unavailable:
          _phase = _RouteRestorePhase.ready;
          return false;
      }
      if (Get.currentRoute != '/') {
        _phase = _RouteRestorePhase.ready;
        return true;
      }

      final raw = GStorage.localCache.get(
        LocalCacheKey.lastAndroidRouteRestoreState,
      );
      if (raw is! String || raw.isEmpty) {
        _phase = _RouteRestorePhase.ready;
        return true;
      }

      final dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return _rejectRestoreState();
      }
      if (decoded is! Map) {
        return _rejectRestoreState();
      }

      final state = Map<String, dynamic>.from(decoded);
      if (state['version'] != _version) {
        return _rejectRestoreState();
      }

      final savedAt = _asInt(state['time']);
      if (savedAt == null ||
          DateTime.now().millisecondsSinceEpoch - savedAt >
              _validDuration.inMilliseconds) {
        return _rejectRestoreState();
      }

      final route = state['route'];
      final params = state['parameters'];
      final args = state['arguments'];
      if (route is! String || !_restorableRoutes.contains(route)) {
        return _rejectRestoreState();
      }

      final arguments = _restoreArguments(route, args);
      final parameters = params is Map
          ? params.map((key, value) => MapEntry('$key', '$value'))
          : null;
      final restorable = RestorableRoute(
        route: route,
        arguments: arguments,
        parameters: parameters,
        mainState: _parseMainState(
          state['mainNavigation'],
          state['homeTab'],
        ),
      );
      if (!_isValid(restorable)) {
        return _rejectRestoreState();
      }

      if (restorable.mainState case final mainState?) {
        _latestMainState = mainState;
        restoreMainState(mainState);
      }

      final storedRoute = RestorableRoute(
        route: restorable.route,
        arguments: _storableArguments(restorable.route, restorable.arguments),
        parameters: restorable.parameters,
        mainState: _latestMainState,
      );
      _latestRoute = storedRoute;
      if (route == '/') {
        _phase = _RouteRestorePhase.ready;
        await _ignoreStorageErrors(_save(storedRoute));
        return true;
      }

      _phase = _RouteRestorePhase.restoring;
      Future<void>? navigation;
      try {
        navigation = Get.toNamed<void>(
          restorable.route,
          arguments: restorable.arguments,
          parameters: restorable.parameters,
          preventDuplicates: false,
        );
      } finally {
        _phase = _RouteRestorePhase.ready;
      }
      if (navigation == null) {
        return false;
      }
      unawaited(navigation);
      await _ignoreStorageErrors(_save(storedRoute));
      return true;
    } catch (_) {
      _phase = _RouteRestorePhase.ready;
      return false;
    }
  }

  static Future<_NativeRestoreDecision> _getNativeRestoreDecision() async {
    for (var attempt = 0; ; attempt++) {
      final decision = await _queryNativeRestoreDecision();
      if (decision != _NativeRestoreDecision.unavailable ||
          attempt == _nativeDecisionRetryDelays.length) {
        return decision;
      }
      await Future<void>.delayed(_nativeDecisionRetryDelays[attempt]);
    }
  }

  static Future<_NativeRestoreDecision> _queryNativeRestoreDecision() async {
    if (!Platform.isAndroid) return _NativeRestoreDecision.reject;
    try {
      final decision = await _lifecycleChannel.invokeMethod<String>(
        'getRestoreDecision',
      );
      return switch (decision) {
        'restore' => _NativeRestoreDecision.restore,
        'reject' => _NativeRestoreDecision.reject,
        _ => _NativeRestoreDecision.unavailable,
      };
    } catch (_) {
      return _NativeRestoreDecision.unavailable;
    }
  }

  static Future<bool> _rejectRestoreState() async {
    _phase = _RouteRestorePhase.ready;
    await _ignoreStorageErrors(clear());
    return true;
  }

  static Future<void> _markNativeLifecycleEvent(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _lifecycleChannel.invokeMethod<void>(method);
    } catch (_) {}
  }

  static String _normalizeRoute(String? route) => route?.split('?').first ?? '';

  static dynamic _restoreArguments(String route, dynamic args) {
    if (route == '/videoV') {
      return _videoArgumentsForRestore(args);
    }
    if (args is Map) {
      return Map<String, dynamic>.from(args);
    }
    return args;
  }

  static dynamic _storableArguments(String route, dynamic args) {
    if (route == '/videoV') {
      return _videoArguments(args);
    }
    if (args is Map) {
      return Map<String, dynamic>.from(args);
    }
    return args;
  }

  static Future<void> _save(RestorableRoute route) => _enqueueStorage(() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return GStorage.localCache.putAll({
      LocalCacheKey.lastAndroidRouteRestoreState: jsonEncode({
        'version': _version,
        'time': now,
        'route': route.route,
        if (route.arguments != null) 'arguments': route.arguments,
        if (route.parameters != null) 'parameters': route.parameters,
        if (route.mainState case final mainState?) ...{
          'mainNavigation': mainState.navigation,
          if (mainState.homeTab != null) 'homeTab': mainState.homeTab,
        },
      }),
      LocalCacheKey.lastAndroidRouteRestoreTime: now,
    });
  });

  static Future<void> _enqueueStorage(
    Future<void> Function() operation,
  ) {
    final next = _storageQueue.then((_) => operation());
    _storageQueue = next.then<void>(
      (_) {},
      onError: (_, _) {},
    );
    return next;
  }

  static Future<void> _ignoreStorageErrors(Future<void> operation) =>
      operation.then<void>((_) {}, onError: (_, _) {});

  static RestorableRoute? _buildRoute(String route) {
    final args = Get.arguments;
    final parameters = Map<String, String>.from(Get.parameters);

    switch (route) {
      case '/videoV':
        final arguments = _videoArguments(args);
        return arguments == null
            ? null
            : RestorableRoute(route: route, arguments: arguments);
      case '/liveRoom':
        final roomId = _intFromArgs(args, ['roomId', 'id']) ?? _asInt(args);
        return roomId == null || roomId <= 0
            ? null
            : RestorableRoute(route: route, arguments: roomId);
      case '/member':
        final mid =
            _asInt(parameters['mid']) ?? _intFromArgs(args, ['mid', 'uid']);
        return mid == null || mid <= 0
            ? null
            : RestorableRoute(route: route, parameters: {'mid': '$mid'});
      case '/searchResult':
        final keyword = parameters['keyword'];
        if (keyword == null || keyword.isEmpty) return null;
        return RestorableRoute(
          route: route,
          arguments: const {'initIndex': 0},
          parameters: {'keyword': keyword},
        );
      case '/fav':
        return RestorableRoute(
          route: route,
          arguments: args is int ? args.clamp(0, 3).toInt() : 0,
        );
      case '/favDetail':
        final mediaId = parameters['mediaId'];
        final mediaIdValue = _asInt(mediaId);
        if (mediaIdValue == null) return null;
        final mediaIdParam = '$mediaIdValue';
        return RestorableRoute(
          route: route,
          parameters: {
            'mediaId': mediaIdParam,
            'heroTag': parameters['heroTag'] ?? Utils.makeHeroTag(mediaIdParam),
          },
        );
      case '/history':
      case '/later':
      case '/download':
      case '/dynamics':
        return RestorableRoute(route: route);
      default:
        return null;
    }
  }

  static RestorableRoute _withMainState(RestorableRoute route) =>
      RestorableRoute(
        route: route.route,
        arguments: route.arguments,
        parameters: route.parameters,
        mainState: _latestMainState,
      );

  static MainRestoreState? _parseMainState(
    dynamic navigation,
    dynamic homeTab,
  ) {
    if (navigation is! String || !_mainNavigationNames.contains(navigation)) {
      return null;
    }
    final validHomeTab = homeTab is String && _homeTabNames.contains(homeTab)
        ? homeTab
        : null;
    return MainRestoreState(
      navigation: navigation,
      homeTab: validHomeTab,
    );
  }

  static Map<String, dynamic>? _videoArguments(dynamic args) {
    if (args is! Map) return null;
    final sourceAid = _asInt(args['aid']);
    final sourceBvid = _asString(args['bvid']);
    final cid = _asInt(args['cid']);
    if (cid == null || cid <= 0) return null;
    final (aid, bvid) = _normalizeVideoIds(sourceAid, sourceBvid);
    if (aid == null || bvid == null) return null;

    return {
      'aid': aid,
      'bvid': bvid,
      'cid': cid,
      'seasonId': ?_asInt(args['seasonId']),
      'epId': ?_asInt(args['epId']),
      'pgcType': ?_asInt(args['pgcType']),
      'cover': ?_asString(args['cover']),
      'title': ?_asString(args['title']),
      'progress': ?_asInt(args['progress']),
      'videoType': _videoTypeName(args['videoType']),
      'sourceType': SourceType.normal.name,
      'isVertical': _asBool(args['isVertical']),
      'heroTag': Utils.makeHeroTag(cid),
    };
  }

  static bool _isCurrentVideoRoute(Map<dynamic, dynamic> arguments) {
    return _normalizeRoute(Get.currentRoute) == '/videoV' &&
        identical(Get.arguments, arguments);
  }

  static Map<String, dynamic>? _videoArgumentsForRestore(dynamic args) {
    final arguments = _videoArguments(args);
    if (arguments == null) return null;
    return {
      ...arguments,
      'videoType': _videoTypeFromName(arguments['videoType']),
      'sourceType': _sourceTypeFromName(arguments['sourceType']),
    };
  }

  static bool _isValid(RestorableRoute route) {
    switch (route.route) {
      case '/':
        return route.mainState != null;
      case '/videoV':
        return _videoArgumentsForRestore(route.arguments) != null;
      case '/liveRoom':
        final args = route.arguments;
        final roomId = _asInt(args) ?? _intFromArgs(args, ['roomId', 'id']);
        return roomId != null && roomId > 0;
      case '/member':
        final mid = _asInt(route.parameters?['mid']);
        return mid != null && mid > 0;
      case '/searchResult':
        return route.parameters?['keyword']?.isNotEmpty == true;
      case '/favDetail':
        final mediaId = _asInt(route.parameters?['mediaId']);
        return mediaId != null && mediaId > 0;
      default:
        return _restorableRoutes.contains(route.route);
    }
  }

  static (int?, String?) _normalizeVideoIds(int? aid, String? bvid) {
    if (aid != null && aid > 0) {
      if (bvid != null) {
        try {
          IdUtils.bv2av(bvid);
          return (aid, bvid);
        } catch (_) {
          return (aid, IdUtils.av2bv(aid));
        }
      }
      return (
        aid,
        IdUtils.av2bv(aid),
      );
    }

    if (bvid == null) {
      return (null, null);
    }
    try {
      return (IdUtils.bv2av(bvid), bvid);
    } catch (_) {
      return (null, null);
    }
  }

  static int? _intFromArgs(dynamic args, List<String> keys) {
    if (args is! Map) return null;
    for (final key in keys) {
      if (_asInt(args[key]) case final value?) return value;
    }
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _asString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static bool _asBool(dynamic value) => value is bool && value;

  static String _videoTypeName(dynamic value) => switch (value) {
    VideoType() => value.name,
    String() when VideoType.values.any((item) => item.name == value) => value,
    _ => VideoType.ugc.name,
  };

  static VideoType _videoTypeFromName(dynamic value) =>
      VideoType.values.firstWhere(
        (item) => item.name == value,
        orElse: () => VideoType.ugc,
      );

  static SourceType _sourceTypeFromName(dynamic value) =>
      SourceType.values.firstWhere(
        (item) => item.name == value,
        orElse: () => SourceType.normal,
      );
}

enum _RouteRestorePhase { startup, checking, restoring, ready }

enum _NativeRestoreDecision { restore, reject, unavailable }

class MainRestoreState {
  const MainRestoreState({
    required this.navigation,
    this.homeTab,
  });

  final String navigation;
  final String? homeTab;
}

class RestorableRoute {
  const RestorableRoute({
    required this.route,
    this.arguments,
    this.parameters,
    this.mainState,
  });

  final String route;
  final dynamic arguments;
  final Map<String, String>? parameters;
  final MainRestoreState? mainState;
}
