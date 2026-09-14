import 'package:flutter/material.dart';
import 'package:PiliPlus/player_core/core_player.dart';

/// 统一播放器渲染视图
class CoreVideoView extends StatelessWidget {
  final CorePlayer player;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CoreVideoView({
    super.key,
    required this.player,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      child: StreamBuilder<CorePlayerState>(
        stream: player.stateStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return errorWidget ?? _buildErrorWidget(context);
          }

          if (!snapshot.hasData) {
            return placeholder ?? _buildPlaceholderWidget();
          }

          return player.buildView(fit: fit);
        },
      ),
    );
  }

  Widget _buildPlaceholderWidget() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _buildErrorWidget(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            '播放器初始化失败',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            '请检查设备是否支持所选播放器',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              // 可以添加重试逻辑
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}