// WBI signing for REST API requests.
// See https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md
import 'dart:async';
import 'dart:convert';

import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/pilimax/forks/http/init.dart';
import 'package:PiliMax/pilimax/http/web_request_headers.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

typedef WbiKeyFetcher = Future<String> Function();
typedef WbiCacheReader = Object? Function();
typedef WbiKeyWriter = Future<void> Function(String key);
typedef WbiTimestampWriter = Future<void> Function(int timestamp);
typedef WbiClock = DateTime Function();

final class WbiKeyManager {
  WbiKeyManager({
    required this.readCachedKey,
    required this.readCachedTimestamp,
    required this.fetchKey,
    required this.writeCachedKey,
    required this.writeCachedTimestamp,
    WbiClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final WbiCacheReader readCachedKey;
  final WbiCacheReader readCachedTimestamp;
  final WbiKeyFetcher fetchKey;
  final WbiKeyWriter writeCachedKey;
  final WbiTimestampWriter writeCachedTimestamp;
  final WbiClock _clock;

  Future<String>? _inFlight;

  Future<String> getKey({bool forceRefresh = false}) async {
    final now = _clock();
    final cachedValue = readCachedKey();
    final cachedKey = WbiSign.isValidKey(cachedValue)
        ? cachedValue! as String
        : null;

    if (!forceRefresh &&
        cachedKey != null &&
        WbiSign.isFreshTimestamp(readCachedTimestamp(), now)) {
      return cachedKey;
    }

    try {
      return await _refreshKey();
    } catch (_) {
      if (!forceRefresh && cachedKey != null) {
        return cachedKey;
      }
      rethrow;
    }
  }

  Future<String> _refreshKey() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<String> operation;
    operation = _fetchAndCacheKey().whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    });
    _inFlight = operation;
    return operation;
  }

  Future<String> _fetchAndCacheKey() async {
    final key = await fetchKey();
    if (!WbiSign.isValidKey(key)) {
      throw const FormatException('Invalid WBI mixin key');
    }

    await writeCachedKey(key);
    await writeCachedTimestamp(_clock().millisecondsSinceEpoch);
    return key;
  }
}

abstract final class WbiSign {
  static Box get _localCache => GStorage.localCache;
  static final RegExp _characterFilter = RegExp(r"[!\'\(\)\*]");
  static final RegExp _keyPattern = RegExp(r'^[0-9a-fA-F]{32}$');
  static final RegExp _sourceKeyPattern = RegExp(r'^[0-9a-fA-F]{64}$');
  static const _mixinKeyEncodingTable = <int>[
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
  ];

  static final WbiKeyManager _keyManager = WbiKeyManager(
    readCachedKey: () => _localCache.get(LocalCacheKey.mixinKey),
    readCachedTimestamp: () => _localCache.get(LocalCacheKey.timeStamp),
    fetchKey: _fetchWbiKey,
    writeCachedKey: (key) => _localCache.put(LocalCacheKey.mixinKey, key),
    writeCachedTimestamp: (timestamp) =>
        _localCache.put(LocalCacheKey.timeStamp, timestamp),
  );

  static bool isValidKey(Object? value) =>
      value is String && _keyPattern.hasMatch(value);

  static bool isFreshTimestamp(Object? value, DateTime now) {
    if (value is! int || value <= 0 || value > now.millisecondsSinceEpoch) {
      return false;
    }

    try {
      final cachedAt = DateTime.fromMillisecondsSinceEpoch(value);
      return cachedAt.year == now.year &&
          cachedAt.month == now.month &&
          cachedAt.day == now.day;
    } on ArgumentError {
      return false;
    }
  }

  static String getMixinKey(String sourceKeys) {
    if (!_sourceKeyPattern.hasMatch(sourceKeys)) {
      throw const FormatException('Invalid WBI source keys');
    }
    final codeUnits = sourceKeys.codeUnits;
    final mixinKey = String.fromCharCodes(
      _mixinKeyEncodingTable.map((index) => codeUnits[index]),
    );
    if (!isValidKey(mixinKey)) {
      throw const FormatException('Invalid WBI mixin key');
    }
    return mixinKey;
  }

  static String deriveMixinKey({
    required Object? imgUrl,
    required Object? subUrl,
  }) {
    return getMixinKey(_extractUrlKey(imgUrl) + _extractUrlKey(subUrl));
  }

  static String _extractUrlKey(Object? value) {
    if (value is! String) {
      throw const FormatException('Invalid WBI key URL');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.pathSegments.isEmpty) {
      throw const FormatException('Invalid WBI key URL');
    }

    final fileName = uri.pathSegments.last;
    final extensionIndex = fileName.lastIndexOf('.');
    final key = extensionIndex > 0
        ? fileName.substring(0, extensionIndex)
        : fileName;
    if (!isValidKey(key)) {
      throw const FormatException('Invalid WBI URL key');
    }
    return key;
  }

  static void encWbi(
    Map<String, Object> params,
    String mixinKey, {
    DateTime? now,
  }) {
    if (!isValidKey(mixinKey)) {
      throw const FormatException('Invalid WBI mixin key');
    }

    params
      ..remove('wts')
      ..remove('w_rid')
      ..['wts'] = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;

    final keys = params.keys.toList()..sort();
    final query = keys
        .map(
          (key) =>
              '${Uri.encodeComponent(key)}=${Uri.encodeComponent(params[key].toString().replaceAll(_characterFilter, ''))}',
        )
        .join('&');
    params['w_rid'] = md5.convert(utf8.encode(query + mixinKey)).toString();
  }

  static Future<String> _fetchWbiKey() async {
    final response = await Request().get(
      Api.userInfo,
      options: WebRequestHeaders.browser,
    );
    final body = response.data;
    if (body is! Map) {
      throw const FormatException('Invalid WBI nav response');
    }
    final data = body['data'];
    if (data is! Map) {
      throw const FormatException('Invalid WBI nav data');
    }
    final wbiImage = data['wbi_img'];
    if (wbiImage is! Map) {
      throw const FormatException('Invalid WBI image data');
    }
    return deriveMixinKey(
      imgUrl: wbiImage['img_url'],
      subUrl: wbiImage['sub_url'],
    );
  }

  static Future<String> getWbiKeys({bool forceRefresh = false}) =>
      _keyManager.getKey(forceRefresh: forceRefresh);

  static Future<Map<String, Object>> makSign(
    Map<String, Object> params, {
    bool forceRefresh = false,
  }) async {
    final mixinKey = await getWbiKeys(forceRefresh: forceRefresh);
    encWbi(params, mixinKey);
    return params;
  }
}
