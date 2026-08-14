import 'dart:convert';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/reply.dart';
import 'package:PiliMax/models_new/emote/package.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier;

class ReplyEmoteFallback {
  const ReplyEmoteFallback({required this.url, required this.size});

  final String url;
  final double size;

  Map<String, dynamic> toJson() => {'url': url, 'size': size};

  factory ReplyEmoteFallback.fromJson(Map<String, dynamic> json) =>
      ReplyEmoteFallback(
        url: json['url'] as String,
        size: (json['size'] as num).toDouble(),
      );
}

/// 评论区表情兜底表。
///
/// 评论的 `Content.emotes` 正常情况下携带本条评论用到的表情；但翻译结果、
/// 分页接口和部分业务会缺失该映射，导致 `[微笑]` 之类文本原样显示。
/// 这里异步拉取官方小表情面板并缓存，供渲染时按 `[文本]` 回退取图。
abstract final class ReplyEmoteResolver {
  static final ValueNotifier<Map<String, ReplyEmoteFallback>> _notifier =
      ValueNotifier<Map<String, ReplyEmoteFallback>>(const {});

  static ValueListenable<Map<String, ReplyEmoteFallback>> get listenable =>
      _notifier;

  static Map<String, ReplyEmoteFallback> get cache => _notifier.value;

  static bool _loading = false;

  static ReplyEmoteFallback? lookup(String token) => _notifier.value[token];

  /// 幂等：第一次调用后只加载一次。
  static void ensureLoaded() {
    if (_loading) {
      return;
    }
    _loading = true;
    _load();
  }

  static Future<void> _load() async {
    try {
      final cached = GStorage.localCache.get(LocalCacheKey.replyEmoteFallback);
      if (cached is String && cached.isNotEmpty) {
        _applyMap(jsonDecode(cached));
      }
    } catch (_) {
      // 缓存损坏时忽略，直接走网络刷新。
    }
    try {
      final result = await ReplyHttp.getEmoteList(business: 'reply');
      if (result case Success(:final response)) {
        final map = <String, ReplyEmoteFallback>{};
        for (final package in response ?? const <Package>[]) {
          for (final emote in package.emote ?? const []) {
            final text = emote.text;
            final url = emote.url;
            if (text == null || text.isEmpty || url == null) {
              continue;
            }
            // meta.size 1 为小表情，其余按大表情缩放，与评论渲染一致。
            final size = (emote.meta?.size == 1 ? 1.0 : 2.0) * 20.0;
            map['[$text]'] = ReplyEmoteFallback(url: url, size: size);
          }
        }
        if (map.isNotEmpty) {
          _applyMap(map);
          await GStorage.localCache.put(
            LocalCacheKey.replyEmoteFallback,
            jsonEncode({
              for (final entry in map.entries) entry.key: entry.value.toJson(),
            }),
          );
        }
      }
    } catch (_) {
      // 网络失败时保留已缓存的兜底表。
    }
  }

  static void _applyMap(Object? data) {
    final json = data;
    if (json is! Map) {
      return;
    }
    final incoming = <String, ReplyEmoteFallback>{};
    for (final entry in json.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is Map) {
        incoming[key] = ReplyEmoteFallback.fromJson(
          value.cast<String, dynamic>(),
        );
      }
    }
    if (incoming.isNotEmpty) {
      _notifier.value = {..._notifier.value, ...incoming};
    }
  }
}
