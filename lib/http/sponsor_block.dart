import 'dart:async';
import 'dart:convert';

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/http/constants.dart';
import 'package:PiliMax/pilimax/forks/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/sponsor_block_api.dart';
import 'package:PiliMax/models/common/sponsor_block/post_segment_model.dart';
import 'package:PiliMax/models/common/sponsor_block/segment_type.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/models_new/sponsor_block/user_info.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

/// https://github.com/hanydd/BilibiliSponsorBlock/wiki/API
abstract final class SponsorBlock {
  static const _segmentCacheTtl = Duration(minutes: 10);
  static const _emptyCacheTtl = Duration(minutes: 3);
  static const _errorCacheTtl = Duration(seconds: 30);
  static const _forcedRefreshCooldown = Duration(minutes: 10);
  static const _segmentConnectTimeout = Duration(seconds: 3);
  static const _segmentReceiveTimeout = Duration(seconds: 6);
  static const _maxConcurrentSegmentRequests = 2;

  static final _segmentCache =
      <(String, String, int), _SponsorBlockCacheEntry>{};
  static final _inFlight =
      <(String, String, int), Future<LoadingState<List<SegmentItemModel>>>>{};
  static final _lastForcedRefresh = <(String, String, int), DateTime>{};
  static final _segmentRequestWaiters = <Completer<void>>[];
  static int _activeSegmentRequests = 0;

  static String get blockServer =>
      normalizeBlockServer(Pref.blockServer) ?? HttpString.sponsorBlockBaseUrl;

  static String? normalizeBlockServer(String value) {
    final input = value.trim();
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/api') {
      path = '';
    } else if (path.endsWith('/api')) {
      path = path.substring(0, path.length - 4);
    }
    return uri.replace(path: path).toString();
  }

  static final options = Options(
    followRedirects: true,
    // https://github.com/hanydd/BilibiliSponsorBlock/wiki/API#1-%E5%85%AC%E7%94%A8%E5%8F%82%E6%95%B0
    headers: kDebugMode
        ? null
        : {
            'origin': Constants.appName,
            'x-ext-version': BuildConfig.versionName,
          },
    validateStatus: (status) => true,
  );

  static Error getErrMsg(Response res) {
    String statusMessage = switch (res.statusCode) {
      200 => '意料之外的响应',
      400 => '参数错误',
      403 => '被自动审核机制拒绝',
      404 => '未找到数据',
      409 => '重复提交',
      429 => '提交太快（触发速率控制）',
      500 => '服务器无法获取信息',
      -1 => res.data['message'].toString(), // DioException
      _ => res.statusMessage ?? res.statusCode.toString(),
    };
    if (res.statusCode != null && res.statusCode != -1) {
      final data = res.data;
      if (res.statusCode == 200 ||
          (data is String && data.isNotEmpty && data.length < 200)) {
        statusMessage = '$statusMessage：$data';
      }
    }
    return Error(statusMessage, code: res.statusCode);
  }

  static String _api(String url) => '$blockServer/api/$url';

  static Future<LoadingState<List<SegmentItemModel>>> getSkipSegments({
    required String bvid,
    required int cid,
    bool forceRefresh = false,
  }) => getSkipSegmentsCached(
    bvid: bvid,
    cid: cid,
    forceRefresh: forceRefresh,
  );

  static Future<LoadingState<List<SegmentItemModel>>> getSkipSegmentsCached({
    required String bvid,
    required int cid,
    bool forceRefresh = false,
  }) async {
    final key = (blockServer, bvid, cid);
    final now = DateTime.now();
    final cached = _segmentCache[key];
    final forcedAt = _lastForcedRefresh[key];
    final forcedRecently =
        forcedAt != null && now.difference(forcedAt) < _forcedRefreshCooldown;

    if (!forceRefresh && cached != null && !cached.isExpired(now)) {
      return cached.result;
    }
    if (forceRefresh && forcedRecently) {
      return cached?.result ??
          const Error('SponsorBlock 请求冷却中，请稍后重试', code: 429);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final useForcedRefresh = forceRefresh && !forcedRecently;
    if (useForcedRefresh) {
      _lastForcedRefresh[key] = now;
    }
    final request = _fetchSkipSegments(
      bvid: bvid,
      cid: cid,
      forceRefresh: useForcedRefresh,
    );
    _inFlight[key] = request;
    try {
      final result = await request;
      final ttl = switch (result) {
        Success<List<SegmentItemModel>>(:final response)
            when response.isEmpty =>
          _emptyCacheTtl,
        Success<List<SegmentItemModel>>() => _segmentCacheTtl,
        Error(:final code) when code == 404 => _emptyCacheTtl,
        Error(:final code) when code == 429 => _forcedRefreshCooldown,
        Error() => _errorCacheTtl,
        _ => null,
      };
      if (ttl != null) {
        _segmentCache[key] = _SponsorBlockCacheEntry(
          result,
          DateTime.now(),
          ttl,
        );
      }
      return result;
    } finally {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    }
  }

  static Future<LoadingState<List<SegmentItemModel>>> _fetchSkipSegments({
    required String bvid,
    required int cid,
    required bool forceRefresh,
  }) async {
    final result = await _withSegmentRequestSlot(
      () => _fetchSkipSegmentsOnce(
        bvid: bvid,
        cid: cid,
        forceRefresh: forceRefresh,
      ),
    );
    if (result case Error(:final code)
        when code != null && code >= 500 && code < 600) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return _withSegmentRequestSlot(
        () => _fetchSkipSegmentsOnce(
          bvid: bvid,
          cid: cid,
          forceRefresh: false,
        ),
      );
    }
    return result;
  }

  static Future<T> _withSegmentRequestSlot<T>(
    Future<T> Function() action,
  ) async {
    if (_activeSegmentRequests >= _maxConcurrentSegmentRequests) {
      final waiter = Completer<void>();
      _segmentRequestWaiters.add(waiter);
      await waiter.future;
    }
    _activeSegmentRequests++;
    try {
      return await action();
    } finally {
      _activeSegmentRequests--;
      if (_segmentRequestWaiters.isNotEmpty) {
        _segmentRequestWaiters.removeAt(0).complete();
      }
    }
  }

  static Future<LoadingState<List<SegmentItemModel>>> _fetchSkipSegmentsOnce({
    required String bvid,
    required int cid,
    required bool forceRefresh,
  }) async {
    final requestHeaders = <String, dynamic>{
      if (!kDebugMode) ...{
        'origin': Constants.appName,
        'x-ext-version': BuildConfig.versionName,
      },
      if (forceRefresh) 'x-skip-cache': '1',
    };
    final requestOptions = Options(
      followRedirects: true,
      // SponsorBlock is independent from video playback. Keep its transport
      // budget bounded so a slow endpoint cannot occupy the player request.
      connectTimeout: _segmentConnectTimeout,
      receiveTimeout: _segmentReceiveTimeout,
      headers: requestHeaders.isEmpty ? null : requestHeaders,
      validateStatus: (status) => true,
    );

    Response res;
    try {
      res = await Request().get(
        _api(SponsorBlockApi.skipSegments),
        queryParameters: {'videoID': bvid, 'cid': cid},
        options: requestOptions,
      );
    } catch (error) {
      return Error('SponsorBlock 请求失败：${error.runtimeType}', code: -2);
    }

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        final parsed = <SegmentItemModel>[];
        for (final item in list) {
          if (item case final Map<String, dynamic> data) {
            try {
              final category = data['category'];
              final segment = data['segment'];
              final uuid = data['UUID'];
              if (category is! String ||
                  uuid is! String ||
                  segment is! List ||
                  segment.length < 2 ||
                  segment.any((value) => value is! num) ||
                  !SegmentType.values.any((type) => type.name == category)) {
                continue;
              }
              parsed.add(SegmentItemModel.fromJson(data));
            } catch (_) {
              // Skip malformed entries without discarding valid segments.
            }
          }
        }
        if (list.isNotEmpty && parsed.isEmpty) {
          return const Error('SponsorBlock 数据解析失败', code: -2);
        }
        return Success(parsed);
      }
      return const Error('SponsorBlock 返回格式错误', code: -2);
    }

    return getErrMsg(res);
  }

  static void invalidateSegments({String? bvid, int? cid}) {
    if (bvid == null || cid == null) {
      _segmentCache.clear();
      _lastForcedRefresh.clear();
      return;
    }
    final key = (blockServer, bvid, cid);
    _segmentCache.remove(key);
    _lastForcedRefresh.remove(key);
  }

  static Future<LoadingState<void>> voteOnSponsorTime({
    required String uuid,
    int? type,
    SegmentType? category,
  }) async {
    assert((type == null) != (category == null));
    final res = await Request().post(
      _api(SponsorBlockApi.voteOnSponsorTime),
      queryParameters: {
        'UUID': uuid,
        'type': ?type,
        'category': ?category?.name,
        'userID': Pref.blockUserID,
      },
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> viewedVideoSponsorTime(String uuid) async {
    final res = await Request().post(
      _api(SponsorBlockApi.viewedVideoSponsorTime),
      data: {'UUID': uuid},
      options: options,
    );
    return res.statusCode == 200 ? const Success(null) : getErrMsg(res);
  }

  static Future<LoadingState<void>> uptimeStatus() async {
    final res = await Request().get(
      _api(SponsorBlockApi.uptimeStatus),
      options: options,
    );
    if (res.statusCode == 200 &&
        res.data is String &&
        Utils.isStringNumeric(res.data)) {
      return const Success(null);
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<UserInfo>> userInfo(
    List<String> query, {
    String? userId,
  }) async {
    final res = await Request().get(
      _api(SponsorBlockApi.userInfo),
      queryParameters: {
        'userID': userId ?? Pref.blockUserID,
        'values': jsonEncode(query),
      },
      options: options,
    );
    if (res.statusCode == 200) {
      return Success(UserInfo.fromJson(res.data));
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<List<SegmentItemModel>>> postSkipSegments({
    required String bvid,
    required int cid,
    required double videoDuration,
    required List<PostSegmentModel> segments,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.skipSegments),
      data: {
        'videoID': bvid,
        'cid': cid.toString(),
        'userID': Pref.blockUserID,
        'userAgent': kDebugMode
            ? Constants.userAgent
            : '${Constants.appName}/${BuildConfig.versionName}',
        'videoDuration': videoDuration,
        'segments': segments
            .map(
              (item) => {
                'segment': [item.segment.first, item.segment.second],
                'category': item.category.name,
                'actionType': item.actionType.name,
              },
            )
            .toList(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final List list) {
        invalidateSegments(bvid: bvid, cid: cid);
        return Success(list.map((i) => SegmentItemModel.fromJson(i)).toList());
      }
    }
    return getErrMsg(res);
  }

  /// {
  ///   "bvID": string,     // B站视频BVID
  ///   "cid": string,      // 视频CID
  ///   "ytbID": string,    // YouTube视频ID
  ///   "UUID": string,     // 绑定记录的UUID（不是视频中片段的UUID，是绑定记录本身的UUID）
  ///   "votes": int,       // 绑定记录的投票数
  ///   "locked": int,      // 绑定记录是否锁定
  /// }
  /// TODO: show port video info dialog
  static Future<LoadingState<String>> getPortVideo({
    required String bvid,
    required int cid,
  }) async {
    final res = await Request().get(
      _api(SponsorBlockApi.portVideo),
      queryParameters: {
        'videoID': bvid,
        'cid': cid.toString(),
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final Map<String, dynamic> data) {
        if (data['ytbID'] case String ytbId) {
          return Success(ytbId);
        }
      }
    }
    return getErrMsg(res);
  }

  static Future<LoadingState<String>> postPortVideo({
    required String bvid,
    required int cid,
    required String ytbId,
    required int videoDuration,
  }) async {
    final res = await Request().post(
      _api(SponsorBlockApi.portVideo),
      data: {
        'bvID': bvid,
        'cid': cid.toString(),
        'ytbID': ytbId,
        'userID': Pref.blockUserID,
        'biliDuration': videoDuration,
      },
      options: options,
    );

    if (res.statusCode == 200) {
      if (res.data case final Map<String, dynamic> data) {
        if (data['UUID'] case String uuid) {
          return Success(uuid);
        }
      }
    }
    return getErrMsg(res);
  }
}

class _SponsorBlockCacheEntry {
  final LoadingState<List<SegmentItemModel>> result;
  final DateTime fetchedAt;
  final Duration ttl;

  const _SponsorBlockCacheEntry(this.result, this.fetchedAt, this.ttl);

  bool isExpired(DateTime now) => now.difference(fetchedAt) >= ttl;
}
