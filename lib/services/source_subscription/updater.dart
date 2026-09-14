import 'dart:async';

import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:PiliPlus/services/source_subscription/store.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

/// 订阅更新器：拉取订阅 URL → 解析清单 → diff 应用到实例库。
class SubscriptionUpdater {
  SubscriptionUpdater._();

  static final SubscriptionUpdater instance = SubscriptionUpdater._();

  final RxBool updating = false.obs;
  Timer? _timer;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'user-agent': 'PiliPlus/SourceSubscription'},
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  /// App 启动后调用：更新过期订阅并启动周期检查。
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      updateAllOutdated();
    });
    updateAllOutdated();
  }

  void dispose() {
    _timer?.cancel();
  }

  Future<void> updateAllOutdated({bool force = false}) async {
    if (updating.value) return;
    final outdated = SourceSubscriptionStore
        .instance.subscriptions
        .value
        .where((s) => force || s.isOutdated)
        .toList();
    if (outdated.isEmpty && !force) return;
    updating.value = true;
    try {
      for (final sub in outdated) {
        await update(sub);
      }
    } finally {
      updating.value = false;
      SourceSubscriptionStore.instance.subscriptions.refresh();
    }
  }

  Future<bool> update(SourceSubscription subscription) async {
    try {
      final res = await _dio.get<String>(subscription.url);
      final body = res.data;
      if (body == null) {
        throw 'empty response';
      }
      final manifest = SubscriptionManifest.parse(body);
      if (manifest == null) {
        throw 'invalid manifest';
      }
      final count = await SourceSubscriptionStore.instance.applyManifest(
        subscription,
        manifest,
      );
      subscription
        ..lastUpdateAt = DateTime.now()
        ..mediaSourceCount = count
        ..lastError = null;
      return true;
    } catch (e) {
      subscription.lastError = e.toString();
      return false;
    }
  }

  /// 添加订阅并立即拉取。
  Future<(bool, String?)> addAndFetch(String url) async {
    final store = SourceSubscriptionStore.instance;
    await store.addSubscription(url);
    final sub = store.subscriptions.value.firstWhereOrNull(
      (s) => s.url == url.trim(),
    );
    if (sub == null) return (false, '订阅已存在或 URL 无效');
    final ok = await update(sub);
    store.subscriptions.refresh();
    return (
      ok,
      ok ? '已添加 ${sub.mediaSourceCount ?? 0} 个数据源' : sub.lastError,
    );
  }
}
