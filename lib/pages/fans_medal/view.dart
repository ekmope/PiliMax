import 'dart:async';

import 'package:PiliMax/common/widgets/loading_widget/loading_widget.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/config.dart';
import 'package:PiliMax/pages/fans_medal/controller.dart';
import 'package:PiliMax/pages/live_room/fans_medal/view.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FansMedalPage extends StatefulWidget {
  const FansMedalPage({super.key});

  @override
  State<FansMedalPage> createState() => _FansMedalPageState();
}

class _FansMedalPageState extends State<FansMedalPage> {
  final _controller = FansMedalController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.reload());
    _scroll.addListener(_loadMore);
  }

  void _loadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 200) {
      unawaited(_controller.load());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('粉丝勋章'),
      actions: [
        IconButton(
          tooltip: '展示设置',
          onPressed: () => showFansMedalSettings(context),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: _controller.reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Obx(() {
      if (Get.isRegistered<AccountService>()) {
        Get.find<AccountService>().isLogin.value;
      }
      if (!_controller.isCurrent) {
        return const Center(child: Text('账号已切换，请重新打开勋章管理'));
      }
      final items = _controller.items.toList();
      final loading = _controller.loading.value;
      final error = _controller.error.value;
      final hasMore = _controller.hasMore.value;
      final acting = _controller.acting.value;
      final total = _controller.total.value;
      if (items.isEmpty && loading) return const Center(child: m3eLoading);
      if (items.isEmpty && error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error),
              TextButton(
                onPressed: _controller.reload,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      }
      if (items.isEmpty) return const Center(child: Text('还没有粉丝勋章'));
      // Fill a short viewport without relying on a scroll event. The controller
      // stops repeated/empty pages before scheduling another request.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _scroll.hasClients &&
            _scroll.position.maxScrollExtent <= 0) {
          _loadMore();
        }
      });
      return RefreshIndicator(
        onRefresh: _controller.reload,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          itemCount: items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(total == null ? '我的勋章' : '共 $total 枚'),
              );
            }
            if (index == items.length + 1) {
              return hasMore && loading
                  ? const SizedBox(height: 48, child: m3eLoading)
                  : const SizedBox(height: 16);
            }
            final item = items[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FansMedalTile(
                item: item,
                acting: acting || loading,
                onTap: () => _controller.toggle(item),
              ),
            );
          },
        ),
      );
    }),
  );
}

Future<void> showFansMedalSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _FansMedalSettings(),
);

class _FansMedalSettings extends StatefulWidget {
  const _FansMedalSettings();

  @override
  State<_FansMedalSettings> createState() => _FansMedalSettingsState();
}

class _FansMedalSettingsState extends State<_FansMedalSettings> {
  final _controller = FansMedalController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.loadConfig());
  }

  @override
  void dispose() {
    _controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('粉丝勋章展示设置'),
    content: SizedBox(
      width: 420,
      child: Obx(() {
        if (Get.isRegistered<AccountService>()) {
          Get.find<AccountService>().isLogin.value;
        }
        if (!_controller.isCurrent) return const Text('账号已切换，请重新打开设置');
        final config = _controller.config.value;
        final loading = _controller.configLoading.value;
        final error = _controller.configError.value;
        if (config == null && loading) {
          return const SizedBox(height: 100, child: m3eLoading);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Text(error),
              TextButton(
                onPressed: _controller.loadConfig,
                child: const Text('重试'),
              ),
            ],
            SwitchListTile(
              title: const Text('关闭个人空间勋章展示'),
              value: config?.closeSpaceMedal ?? false,
              onChanged: loading || config?.closeSpaceMedal == null
                  ? null
                  : (value) => _controller.setConfig(
                      FansMedalConfig.closeSpaceMedalKey,
                      value,
                    ),
            ),
            SwitchListTile(
              title: const Text('只展示当前佩戴的勋章'),
              value: config?.onlyShowWearing ?? false,
              onChanged: loading || config?.onlyShowWearing == null
                  ? null
                  : (value) => _controller.setConfig(
                      FansMedalConfig.onlyShowWearingKey,
                      value,
                    ),
            ),
          ],
        );
      }),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}
