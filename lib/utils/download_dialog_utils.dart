import 'package:PiliMax/common/widgets/flutter/popup_menu.dart';
import 'package:PiliMax/http/search.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class DownloadDialogUtils {
  static Future<VideoQuality?> showDownloadConfirmDialog(
    BuildContext context, {
    String title = '确认缓存该视频？',
    String content = '将把此视频加入离线下载队列。',
  }) async {
    VideoQuality quality = VideoQuality.fromCode(Pref.defaultVideoQa);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          final textStyle = TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
          );

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(content),
                const SizedBox(height: 16),
                Row(
                  spacing: 16,
                  children: [
                    Text('最高画质', style: textStyle),
                    StaticPopupMenuButton<VideoQuality>(
                      initialValue: quality,
                      onSelected: (value) => setState(() => quality = value),
                      itemBuilder: (context) => VideoQuality.values
                          .map(
                            (e) => PopupMenuItem(value: e, child: Text(e.desc)),
                          )
                          .toList(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              quality.desc,
                              style: const TextStyle(height: 1),
                              strutStyle: const StrutStyle(
                                height: 1,
                                leading: 0,
                              ),
                            ),
                            Icon(
                              size: 18,
                              Icons.keyboard_arrow_down,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder(
                  stream: Connectivity().onConnectivityChanged,
                  builder: (context, snapshot) {
                    if (snapshot.data case final data?) {
                      final network = data.contains(ConnectivityResult.wifi)
                          ? 'WIFI'
                          : '数据';
                      return Text('当前网络：$network', style: textStyle);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('确认'),
              ),
            ],
          );
        },
      ),
    );

    return confirmed == true ? quality : null;
  }

  static Future<void> confirmAndDownloadByIdentifiers(
    BuildContext context, {
    required String? bvid,
    required int totalTimeMilli,
    int? cid,
    int? aid,
    int? part,
    String? title,
    String? cover,
    int? ownerId,
    String? ownerName,
  }) async {
    final quality = await showDownloadConfirmDialog(context);
    if (quality == null) {
      return;
    }

    final validBvid = bvid?.trim();
    if (validBvid == null || validBvid.isEmpty) {
      SmartDialog.showToast('无法解析视频 bvid');
      return;
    }
    if (totalTimeMilli <= 0) {
      SmartDialog.showToast('视频时长错误');
      return;
    }

    try {
      SmartDialog.showLoading(msg: '任务创建中');
      final resolvedCid =
          cid ?? await SearchHttp.ab2c(aid: aid, bvid: validBvid, part: part);
      if (resolvedCid == null) {
        SmartDialog.dismiss();
        SmartDialog.showToast('无法解析播放分片 cid');
        return;
      }

      await Get.find<DownloadService>().downloadByIdentifiers(
        cid: resolvedCid,
        bvid: validBvid,
        totalTimeMilli: totalTimeMilli,
        aid: aid,
        title: title,
        cover: cover,
        ownerId: ownerId,
        ownerName: ownerName,
        quality: quality,
      );
      SmartDialog.dismiss();
      SmartDialog.showToast('已加入下载队列');
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(e.toString());
    }
  }

  static Future<VideoQuality?> confirmDownloadQuality(BuildContext context) {
    return showDownloadConfirmDialog(context);
  }
}
