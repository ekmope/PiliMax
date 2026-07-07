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
import 'package:get/get.dart';

abstract final class RouteRestoreService {
  static const _version = 1;
  static const _validDuration = Duration(hours: 24);
  static const _restorableRoutes = {
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

  static bool _hasPerformedRestore = false;
  static bool _isRestoring = false;
  static RestorableRoute? _latestRoute;

  static bool get _enabled =>
      Platform.isAndroid && Pref.enableAndroidRouteRestore;

  static void onRouteChanged(Routing? routing) {
    if (!_enabled || _isRestoring || routing == null) return;
    if (routing.route is! GetPageRoute) return;
    final route = _normalizeRoute(routing.current);
    if (route.isEmpty || !route.startsWith('/')) return;
    if (route == '/') {
      unawaited(clear());
      return;
    }
    if (!_restorableRoutes.contains(route)) return;

    final restorable = _buildRoute(route);
    if (restorable == null) return;
    _latestRoute = restorable;
    unawaited(_save(restorable));
  }

  static Future<void> saveLatestRoute() async {
    if (!_enabled || _latestRoute == null) return;
    await _save(_latestRoute!);
  }

  static Future<void> clear() async {
    await Future.wait([
      GStorage.localCache.delete(LocalCacheKey.lastAndroidRouteRestoreState),
      GStorage.localCache.delete(LocalCacheKey.lastAndroidRouteRestoreTime),
    ]);
    _latestRoute = null;
  }

  static Future<void> restoreIfNeeded() async {
    if (!_enabled || _hasPerformedRestore) return;
    _hasPerformedRestore = true;

    try {
      if (Get.currentRoute != '/') return;

      final raw = GStorage.localCache.get(
        LocalCacheKey.lastAndroidRouteRestoreState,
      );
      if (raw is! String || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return;
      }

      final state = Map<String, dynamic>.from(decoded);
      if (state['version'] != _version) {
        await clear();
        return;
      }

      final savedAt = _asInt(state['time']);
      if (savedAt == null ||
          DateTime.now().millisecondsSinceEpoch - savedAt >
              _validDuration.inMilliseconds) {
        await clear();
        return;
      }

      final route = state['route'];
      final params = state['parameters'];
      final args = state['arguments'];
      if (route is! String || !_restorableRoutes.contains(route)) {
        await clear();
        return;
      }

      final arguments = _restoreArguments(route, args);
      final parameters = params is Map
          ? params.map((key, value) => MapEntry('$key', '$value'))
          : null;
      final restorable = RestorableRoute(
        route: route,
        arguments: arguments,
        parameters: parameters,
      );
      if (!_isValid(restorable)) {
        await clear();
        return;
      }

      _isRestoring = true;
      try {
        await Get.toNamed(
          restorable.route,
          arguments: restorable.arguments,
          parameters: restorable.parameters,
          preventDuplicates: false,
        );
        _latestRoute = RestorableRoute(
          route: restorable.route,
          arguments: _storableArguments(restorable.route, args),
          parameters: restorable.parameters,
        );
      } finally {
        _isRestoring = false;
      }
    } catch (_) {
      await clear();
    }
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

  static Future<void> _save(RestorableRoute route) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await GStorage.localCache.put(
      LocalCacheKey.lastAndroidRouteRestoreState,
      jsonEncode({
        'version': _version,
        'time': now,
        'route': route.route,
        if (route.arguments != null) 'arguments': route.arguments,
        if (route.parameters != null) 'parameters': route.parameters,
      }),
    );
    await GStorage.localCache.put(
      LocalCacheKey.lastAndroidRouteRestoreTime,
      now,
    );
  }

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
            'heroTag':
                parameters['heroTag'] ?? Utils.makeHeroTag(mediaIdParam),
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

  static String _videoTypeName(dynamic value) =>
      switch (value) {
        VideoType() => value.name,
        String() when VideoType.values.any((item) => item.name == value) =>
          value,
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

class RestorableRoute {
  const RestorableRoute({
    required this.route,
    this.arguments,
    this.parameters,
  });

  final String route;
  final dynamic arguments;
  final Map<String, String>? parameters;
}
