import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

/// 源订阅与数据源实例的持久化（appSupport 目录 JSON 文件，与流量统计同模式）。
class SourceSubscriptionStore {
  SourceSubscriptionStore._() {
    _load();
  }

  static final SourceSubscriptionStore instance = SourceSubscriptionStore._();

  final RxList<SourceSubscription> subscriptions = RxList();
  final RxList<SourceInstance> instances = RxList();

  File get _subscriptionsFile => File(
    path.join(GStorage.appSupportDirPath, 'source_subscriptions.json'),
  );

  File get _instancesFile => File(
    path.join(GStorage.appSupportDirPath, 'source_instances.json'),
  );

  void _load() {
    try {
      final raw = _subscriptionsFile.readAsStringSync();
      final list = jsonDecode(raw) as List;
      subscriptions.value = [
        for (final e in list.whereType<Map>())
          SourceSubscription.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {}
    try {
      final raw = _instancesFile.readAsStringSync();
      final list = jsonDecode(raw) as List;
      instances.value = [
        for (final e in list.whereType<Map>())
          SourceInstance.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {}
    subscriptions.refresh();
    instances.refresh();
  }

  Future<void> _saveSubscriptions() => GStorage.writeJsonFile(
    _subscriptionsFile,
    [for (final s in subscriptions) s.toJson()],
  );

  Future<void> _saveInstances() => GStorage.writeJsonFile(
    _instancesFile,
    [for (final i in instances) i.toJson()],
  );

  Future<void> addSubscription(String url) async {
    if (url.trim().isEmpty) return;
    if (subscriptions.any((s) => s.url == url.trim())) return;
    subscriptions.add(
      SourceSubscription(
        subscriptionId: DateTime.now().microsecondsSinceEpoch.toString(),
        url: url.trim(),
      ),
    );
    await _saveSubscriptions();
    subscriptions.refresh();
  }

  Future<void> removeSubscription(String subscriptionId) async {
    subscriptions.removeWhere((s) => s.subscriptionId == subscriptionId);
    // 级联删除该订阅创建的所有实例
    instances.removeWhere((i) => i.subscriptionId == subscriptionId);
    await _saveSubscriptions();
    await _saveInstances();
    subscriptions.refresh();
    instances.refresh();
  }

  /// 按名称 diff 订阅清单：增/删/改 + 顺序跟随远程。
  Future<int> applyManifest(
    SourceSubscription subscription,
    SubscriptionManifest manifest,
  ) async {
    final imported = <String, ExportedMediaSourceData>{
      for (final m in manifest.mediaSources)
        if ((m.arguments['name'] as String?)?.isNotEmpty ?? false)
          m.arguments['name'] as String: m,
    };
    if (imported.isEmpty) return 0;

    final owned = instances
        .where((i) => i.subscriptionId == subscription.subscriptionId)
        .toList();

    // 删除：订阅内本地有、远程没有
    final removed = owned.where((i) => !imported.containsKey(i.name)).toList();
    if (removed.isNotEmpty) {
      instances.removeWhere(removed.contains);
    }

    // 新增/更新 + 按远程顺序重排
    int order = 0;
    final updated = <SourceInstance>[];
    for (final entry in imported.entries) {
      order++;
      final existing = owned.firstWhereOrNull((i) => i.name == entry.key);
      if (existing != null) {
        existing
          ..arguments = entry.value.arguments
          ..sortOrder = order;
        updated.add(existing);
      } else {
        final inst = SourceInstance.fromExported(
          entry.value,
          instanceId:
              '${subscription.subscriptionId}:${entry.key}',
          sortOrder: order,
          subscriptionId: subscription.subscriptionId,
        );
        instances.add(inst);
        updated.add(inst);
      }
    }
    await _saveInstances();
    instances.refresh();
    return updated.length;
  }

  Future<void> setInstanceEnabled(SourceInstance instance, bool enabled) async {
    instance.isEnabled = enabled;
    await _saveInstances();
    instances.refresh();
  }

  Future<void> removeInstance(SourceInstance instance) async {
    instances.removeWhere((i) => i.instanceId == instance.instanceId);
    await _saveInstances();
    instances.refresh();
  }

  List<SourceInstance> get enabledInstances =>
      instances.where((i) => i.isEnabled).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}
