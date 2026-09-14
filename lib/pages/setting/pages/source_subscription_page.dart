import 'package:PiliPlus/services/source_subscription/models.dart';
import 'package:PiliPlus/services/source_subscription/store.dart';
import 'package:PiliPlus/services/source_subscription/updater.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 源订阅管理页：添加/刷新/删除订阅，管理数据源实例。
class SourceSubscriptionPage extends StatefulWidget {
  const SourceSubscriptionPage({super.key});

  @override
  State<SourceSubscriptionPage> createState() => _SourceSubscriptionPageState();
}

class _SourceSubscriptionPageState extends State<SourceSubscriptionPage> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final store = SourceSubscriptionStore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('源订阅')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: _showAddDialog,
      ),
      body: Obx(
        () => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('刷新全部订阅'),
              subtitle: Obx(
                () => Text(
                  SubscriptionUpdater.instance.updating.value ? '更新中…' : '点击立即更新所有订阅',
                ),
              ),
              onTap: () async {
                await SubscriptionUpdater.instance.updateAllOutdated(
                  force: true,
                );
                SmartDialog.showToast('订阅更新完成');
              },
            ),
            const Divider(height: 1),
            if (store.subscriptions.isEmpty)
              Padding(
                padding: const .all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.subscriptions_outlined,
                      size: 48,
                      color: colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '暂无订阅\n点击 + 添加 animeko 兼容的订阅地址',
                      textAlign: .center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            for (final sub in store.subscriptions) _buildSubscriptionTile(sub),
            const Divider(height: 1),
            Padding(
              padding: const .only(left: 16, top: 12, bottom: 4),
              child: Text(
                '数据源（${store.instances.length}）',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final inst in store.instances) _buildInstanceTile(inst),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionTile(SourceSubscription sub) {
    final colorScheme = ColorScheme.of(context);
    return ListTile(
      leading: const Icon(Icons.rss_feed),
      title: Text(
        sub.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: .start,
        children: [
          if (sub.lastUpdateAt != null)
            Text(
              '上次更新 ${DateFormatUtils.dateFormat(sub.lastUpdateAt!.millisecondsSinceEpoch ~/ 1000)}'
              '${sub.mediaSourceCount != null ? ' · ${sub.mediaSourceCount} 个源' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          if (sub.lastError case final err?)
            Text(
              '错误: $err',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.error),
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(sub),
      ),
      onTap: () async {
        final ok = await SubscriptionUpdater.instance.update(sub);
        SourceSubscriptionStore.instance.subscriptions.refresh();
        SmartDialog.showToast(ok ? '已更新' : '更新失败');
      },
    );
  }

  Widget _buildInstanceTile(SourceInstance inst) {
    return Obx(
      () => SwitchListTile(
        secondary: CircleAvatar(child: Text(inst.name[0])),
        title: Text(
          inst.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          inst.subscriptionId != null ? '来自订阅' : '手动添加',
          style: const TextStyle(fontSize: 12),
        ),
        value: inst.isEnabled,
        onChanged: (v) => SourceSubscriptionStore.instance.setInstanceEnabled(
          inst,
          v,
        ),
      ),
    );
  }

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加订阅'),
        content: Column(
          mainAxisSize: .min,
          children: [
            const Text('粘贴 animeko 兼容的订阅地址（JSON 清单）'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'https://...',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;
              Get.back();
              SmartDialog.showLoading(msg: '正在拉取订阅…');
              final (ok, msg) = await SubscriptionUpdater.instance.addAndFetch(
                url,
              );
              SmartDialog.dismiss(status: SmartStatus.loading);
              SmartDialog.showToast(msg ?? (ok ? '成功' : '失败'));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SourceSubscription sub) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除订阅'),
        content: Text('将同时删除该订阅创建的所有数据源：\n${sub.url}'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Get.back();
              await SourceSubscriptionStore.instance.removeSubscription(
                sub.subscriptionId,
              );
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
