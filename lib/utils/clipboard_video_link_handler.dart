import 'dart:async' show unawaited;

import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/pgc/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/services/crash/crash_reporter.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/url_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

abstract final class ClipboardVideoLinkHandler {
  static final _urlCandidateRegExp = RegExp(
    r'''(?:(?:https?:)?//)?[a-z0-9.-]+\.(?:com|tv)/[^\s<>"'\u3000，。；！？：、）】}》]*''',
    caseSensitive: false,
  );
  static final _shortCodeRegExp = RegExp(r'^[0-9A-Za-z]+$');
  static const _trailingPunctuation = '.,，。;；!！?？:：、)）]】}》>\'"';
  static const _sameVideoThrottle = Duration(seconds: 3);
  static const _maxCandidateLength = 2048;
  static final _urlPrefixRegExp = RegExp(
    r'^https?://',
    caseSensitive: false,
  );

  static final _lifecycleObserver = _ClipboardLifecycleObserver();
  static bool _initialized = false;
  static bool _isResumed = false;
  static bool _isHandling = false;
  static bool _checkRequested = false;
  static int? _scheduledCheckGeneration;
  static int _generation = 0;
  static int _sessionGeneration = 0;
  static String? _lastProcessedClipboardText;
  static String? _lastHandledVideoKey;
  static DateTime? _lastHandledAt;

  static void init() {
    if (!PlatformUtils.isMobile || _initialized) return;

    _initialized = true;
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isResumed =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _generation++;
    _sessionGeneration++;
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
  }

  static void dispose() {
    if (_initialized && PlatformUtils.isMobile) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    }
    _initialized = false;
    _isResumed = false;
    _isHandling = false;
    _checkRequested = false;
    _scheduledCheckGeneration = null;
    _generation++;
    _sessionGeneration++;
    _lastProcessedClipboardText = null;
    _lastHandledVideoKey = null;
    _lastHandledAt = null;
  }

  static Future<void> checkAndOpen() async {
    if (!_canCheck) return;

    _checkRequested = true;
    await _drainChecks();
  }

  static bool get _canCheck =>
      _initialized &&
      _isResumed &&
      PlatformUtils.isMobile &&
      Pref.autoOpenClipboardVideoLink;

  static Future<void> _drainChecks() async {
    if (_isHandling) return;

    _isHandling = true;
    try {
      while (_checkRequested) {
        _checkRequested = false;
        if (!_canCheck) break;
        await _checkOnce();
      }
    } finally {
      _isHandling = false;
    }
  }

  static Future<void> _checkOnce() async {
    try {
      await CrashReporter.waitForStartupOverlay();
      if (!_canCheck) return;
      final generation = _generation;
      final sessionGeneration = _sessionGeneration;
      final snapshot = _NavigationSnapshot.capture();
      if (!_isNavigationStillValid(snapshot, generation)) return;

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!_isNavigationStillValid(snapshot, generation)) return;

      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        return;
      }

      final extractedLink = extractVideoLink(text);
      if (extractedLink == null ||
          extractedLink == _lastProcessedClipboardText) {
        return;
      }

      final resolvedLink = await resolveVideoUrl(extractedLink);
      if (!_isNavigationStillValid(snapshot, generation) ||
          resolvedLink == null) {
        return;
      }

      final videoKey = canonicalVideoKey(resolvedLink);
      if (videoKey == null) return;

      final context = Get.context;
      if (context == null || !context.mounted) return;

      final now = DateTime.now();
      final lastHandledAt = _lastHandledAt;
      if (_lastHandledVideoKey == videoKey &&
          lastHandledAt != null &&
          now.difference(lastHandledAt) < _sameVideoThrottle) {
        if (sessionGeneration == _sessionGeneration) {
          _markProcessed(extractedLink, videoKey, now);
        }
        return;
      }

      if (snapshot.isVideoRoute && snapshot.videoKey == videoKey) {
        if (sessionGeneration == _sessionGeneration) {
          _markProcessed(extractedLink, videoKey, now);
        }
        return;
      }

      if (snapshot.isVideoRoute) {
        if (!_isNavigationStillValid(snapshot, generation)) return;
        final confirmed = await _confirmOpen(resolvedLink);
        if (!_isNavigationStillValid(snapshot, generation)) {
          return;
        }
        if (confirmed == false) {
          if (sessionGeneration == _sessionGeneration) {
            _markProcessed(extractedLink, videoKey, DateTime.now());
          }
          return;
        }
        if (confirmed != true) return;
      }

      final handled = await PiliScheme.openClipboardVideo(
        resolvedLink,
        off: snapshot.isVideoRoute,
        canNavigate: () => _isNavigationStillValid(snapshot, generation),
      );
      if (handled && _canCheck && sessionGeneration == _sessionGeneration) {
        _markProcessed(extractedLink, videoKey, DateTime.now());
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('check clipboard video link failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  static void _didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized) return;

    _generation++;
    _scheduledCheckGeneration = null;
    if (state != AppLifecycleState.resumed) {
      _isResumed = false;
      _checkRequested = false;
      return;
    }

    _isResumed = true;
    _scheduleResumeCheck();
  }

  static void _scheduleResumeCheck() {
    if (!_initialized || !_isResumed || _scheduledCheckGeneration != null) {
      return;
    }

    final generation = _generation;
    _scheduledCheckGeneration = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scheduledCheckGeneration == generation) {
        _scheduledCheckGeneration = null;
      }
      if (!_initialized ||
          !_isResumed ||
          _generation != generation ||
          !_canCheck) {
        return;
      }
      _checkRequested = true;
      unawaited(_drainChecks());
    });
  }

  @visibleForTesting
  static String? extractVideoLink(String text) {
    for (final match in _urlCandidateRegExp.allMatches(text)) {
      final candidate = _trimLink(match.group(0)!);
      if (candidate.length > _maxCandidateLength) continue;
      final uri = _parseHttpUri(candidate);
      if (uri != null && (_isVideoUri(uri) || _isB23ShortUri(uri))) {
        return candidate;
      }
    }
    return null;
  }

  @visibleForTesting
  static Future<String?> resolveVideoUrl(
    String link, {
    Future<String?> Function(String url)? redirectResolver,
  }) async {
    var uri = _parseHttpUri(_trimLink(link));
    if (uri == null) return null;

    if (_isVideoUri(uri)) return uri.toString();
    if (!_isB23ShortUri(uri)) return null;

    final resolveRedirect = redirectResolver ?? UrlUtils.parseRedirectUrl;
    for (var redirectCount = 0; redirectCount < 3; redirectCount++) {
      final redirectUrl = await resolveRedirect(uri.toString());
      if (redirectUrl == null) return null;

      uri = _parseHttpUri(_trimLink(redirectUrl));
      if (uri == null) return null;
      if (_isVideoUri(uri)) return uri.toString();
      if (!_isB23ShortUri(uri)) return null;
    }
    return null;
  }

  @visibleForTesting
  static String? canonicalVideoKey(String link) {
    final uri = _parseHttpUri(_trimLink(link));
    if (uri == null || !_isVideoUri(uri)) return null;

    final videoId = uri.pathSegments.where((item) => item.isNotEmpty).last;
    final result = IdUtils.matchAvorBv(input: videoId);
    if (result.av case final aid?) return 'aid:$aid';
    if (result.bv case final bvid?) {
      final normalizedBvid = 'BV${bvid.substring(2)}';
      try {
        return 'aid:${IdUtils.bv2av(normalizedBvid)}';
      } catch (_) {
        return 'bvid:$normalizedBvid';
      }
    }
    return null;
  }

  static String _trimLink(String link) {
    while (link.isNotEmpty &&
        _trailingPunctuation.contains(link[link.length - 1])) {
      link = link.substring(0, link.length - 1);
    }
    return link;
  }

  static Uri? _parseHttpUri(String link) {
    final normalized = link.startsWith('//')
        ? 'https:$link'
        : _urlPrefixRegExp.hasMatch(link)
        ? link
        : 'https://$link';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static bool _isVideoUri(Uri uri) {
    if (!_isBilibiliHost(uri.host)) return false;
    final segments = uri.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (segments.length != 2 || segments.first.toLowerCase() != 'video') {
      return false;
    }
    return IdUtils.avRegexExact.hasMatch(segments.last) ||
        IdUtils.bvRegexExact.hasMatch(segments.last);
  }

  static bool _isB23ShortUri(Uri uri) {
    if (!_isB23Host(uri.host)) return false;
    final segments = uri.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return segments.length == 1 && _shortCodeRegExp.hasMatch(segments.single);
  }

  static bool _isBilibiliHost(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'bilibili.com' ||
        normalizedHost == 'www.bilibili.com' ||
        normalizedHost == 'm.bilibili.com';
  }

  static bool _isB23Host(String host) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == 'b23.tv' ||
        normalizedHost == 'www.b23.tv' ||
        normalizedHost == 'share.b23.tv';
  }

  static String get _normalizedCurrentRoute =>
      _normalizeRoute(Get.currentRoute);

  static String _normalizeRoute(String route) => route.split('?').first;

  static bool _isNavigationStillValid(
    _NavigationSnapshot snapshot,
    int generation,
  ) {
    try {
      if (!_canCheck) return false;
      return navigationGuardMatches(
        initialized: _initialized,
        resumed: _isResumed,
        expectedGeneration: generation,
        currentGeneration: _generation,
        expectedRoute: snapshot.route,
        currentRoute: _normalizedCurrentRoute,
        expectedRouteObject: snapshot.routeObject,
        currentRouteObject: Get.routing.route,
        expectedArguments: snapshot.arguments,
        currentArguments: Get.arguments,
        expectedVideoKey: snapshot.videoKey,
        currentVideoKey: snapshot.isVideoRoute ? _currentVideoKey : null,
      );
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static bool navigationGuardMatches({
    required bool initialized,
    required bool resumed,
    required int expectedGeneration,
    required int currentGeneration,
    required String expectedRoute,
    required String currentRoute,
    Object? expectedRouteObject,
    Object? currentRouteObject,
    required Object? expectedArguments,
    required Object? currentArguments,
    String? expectedVideoKey,
    String? currentVideoKey,
  }) {
    if (!initialized ||
        !resumed ||
        expectedGeneration != currentGeneration ||
        _normalizeRoute(expectedRoute) != _normalizeRoute(currentRoute) ||
        ((expectedRouteObject != null || currentRouteObject != null) &&
            !identical(expectedRouteObject, currentRouteObject)) ||
        !identical(expectedArguments, currentArguments)) {
      return false;
    }
    return _normalizeRoute(expectedRoute) != '/videoV' ||
        expectedVideoKey == currentVideoKey;
  }

  static String? get _currentVideoKey {
    final arguments = Get.arguments;
    if (arguments is! Map) return null;

    final heroTag = arguments['heroTag'];
    Object? detailAid;
    String? detailBvid;
    String? ugcBvid;
    String? pgcBvid;
    if (heroTag is String && heroTag.isNotEmpty) {
      try {
        if (Get.isRegistered<VideoDetailController>(tag: heroTag)) {
          final controller = Get.find<VideoDetailController>(tag: heroTag);
          detailAid = controller.aid;
          detailBvid = controller.bvid;
        }
      } catch (_) {}
      try {
        if (Get.isRegistered<UgcIntroController>(tag: heroTag)) {
          ugcBvid = Get.find<UgcIntroController>(tag: heroTag).bvid;
        }
      } catch (_) {}
      try {
        if (Get.isRegistered<PgcIntroController>(tag: heroTag)) {
          pgcBvid = Get.find<PgcIntroController>(tag: heroTag).bvid;
        }
      } catch (_) {}
    }

    return resolveCurrentVideoKey(
      detailAid: detailAid,
      detailBvid: detailBvid,
      ugcBvid: ugcBvid,
      pgcBvid: pgcBvid,
      routeAid: arguments['aid'],
      routeBvid: arguments['bvid'],
    );
  }

  @visibleForTesting
  static String? resolveCurrentVideoKey({
    Object? detailAid,
    String? detailBvid,
    String? ugcBvid,
    String? pgcBvid,
    Object? routeAid,
    Object? routeBvid,
  }) {
    return _videoKeyFromIds(detailAid, detailBvid) ??
        _videoKeyFromIds(null, ugcBvid) ??
        _videoKeyFromIds(null, pgcBvid) ??
        _videoKeyFromIds(routeAid, routeBvid);
  }

  static String? _videoKeyFromIds(Object? aid, Object? bvid) {
    if (bvid is String && bvid.trim().isNotEmpty) {
      try {
        final key = canonicalVideoKey(
          'https://www.bilibili.com/video/${bvid.trim()}',
        );
        if (key != null) return key;
      } catch (_) {}
    }

    final parsedAid = switch (aid) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
    return parsedAid == null ? null : 'aid:$parsedAid';
  }

  @visibleForTesting
  static String? clipboardTextAfterNavigation({
    required String? previousText,
    required String candidateText,
    required bool navigationSucceeded,
  }) {
    return navigationSucceeded ? candidateText : previousText;
  }

  static void _markProcessed(String text, String videoKey, DateTime now) {
    _lastProcessedClipboardText = clipboardTextAfterNavigation(
      previousText: _lastProcessedClipboardText,
      candidateText: text,
      navigationSucceeded: true,
    );
    _lastHandledVideoKey = videoKey;
    _lastHandledAt = now;
  }

  static Future<bool?> _confirmOpen(String link) async {
    final context = Get.context;
    if (context == null || !context.mounted) return null;

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('打开剪贴板视频？'),
        content: Text(
          link,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.outline,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }
}

final class _NavigationSnapshot {
  const _NavigationSnapshot({
    required this.route,
    required this.routeObject,
    required this.arguments,
    required this.videoKey,
  });

  factory _NavigationSnapshot.capture() {
    final route = ClipboardVideoLinkHandler._normalizedCurrentRoute;
    return _NavigationSnapshot(
      route: route,
      routeObject: Get.routing.route,
      arguments: Get.arguments,
      videoKey: route == '/videoV'
          ? ClipboardVideoLinkHandler._currentVideoKey
          : null,
    );
  }

  final String route;
  final Object? routeObject;
  final Object? arguments;
  final String? videoKey;

  bool get isVideoRoute => route == '/videoV';
}

final class _ClipboardLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ClipboardVideoLinkHandler._didChangeAppLifecycleState(state);
  }
}
