import 'package:PiliMax/common/widgets/appbar/appbar.dart';
import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/flutter/pop_scope.dart';
import 'package:PiliMax/common/widgets/loading_widget/http_error.dart';
import 'package:PiliMax/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/pages/common/multi_select/base.dart'
    show BaseMultiSelectMixin;
import 'package:PiliMax/pages/download/controller.dart';
import 'package:PiliMax/pages/download/detail/widgets/item.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:flutter/material.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DownloadDetailPage extends StatefulWidget {
  const DownloadDetailPage({
    super.key,
    required this.pageId,
    required this.title,
    required this.progress,
  });

  final String pageId;
  final String title;
  final ChangeNotifier progress;

  @override
  State<DownloadDetailPage> createState() => _DownloadDetailPageState();
}

class _DownloadDetailPageState extends State<DownloadDetailPage>
    with BaseMultiSelectMixin<BiliDownloadEntryInfo>, GridMixin {
  final _downloadItems = RxList<BiliDownloadEntryInfo>();
  final _controller = Get.find<DownloadPageController>();
  final _downloadService = Get.find<DownloadService>();
  bool _isListening = false;
  @override
  RxList<BiliDownloadEntryInfo> get list => _downloadItems;
  @override
  RxList<BiliDownloadEntryInfo> get state => _downloadItems;

  @override
  void initState() {
    super.initState();
    _loadList();
    _controller.collectionService.flagNotifier.add(_loadList);
    _isListening = true;
  }

  void _stopListening() {
    if (!_isListening) {
      return;
    }
    _controller.collectionService.flagNotifier.remove(_loadList);
    _isListening = false;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  void _loadList() {
    final list = _controller.resolveFolderEntries(widget.pageId)
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    _downloadItems.value = list;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Obx(() {
      final enableMultiSelect = this.enableMultiSelect.value;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) {
            handleSelect();
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: MultiSelectAppBarWidget(
            ctr: this,
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final futures = allChecked
                      .map(
                        (e) => _downloadService.downloadDanmaku(
                          entry: e,
                          isUpdate: true,
                        ),
                      )
                      .toList();
                  handleSelect();
                  final res = await Future.wait(futures);
                  if (res.every((e) => e)) {
                    SmartDialog.showToast('更新成功');
                  } else {
                    SmartDialog.showToast('更新失败');
                  }
                },
                child: Text(
                  '更新',
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
            ],
            child: AppBar(
              title: Text(widget.title),
              actions: [
                IconButton(
                  tooltip: '多选',
                  onPressed: () {
                    if (enableMultiSelect) {
                      handleSelect();
                    } else {
                      this.enableMultiSelect.value = true;
                    }
                  },
                  icon: const Icon(Icons.edit_note),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          body: CustomScrollView(
            slivers: [
              ViewSliverSafeArea(
                sliver: Obx(() {
                  if (_downloadItems.isNotEmpty) {
                    return SliverGrid.builder(
                      gridDelegate: gridDelegate,
                      itemBuilder: (context, index) {
                        final entry = _downloadItems[index];
                        return DetailItem(
                          entry: entry,
                          progress: widget.progress,
                          downloadService: _downloadService,
                          showTitle: false,
                          onDelete: () async {
                            if (_downloadItems.length == 1) {
                              _stopListening();
                              await _downloadService.deletePage(
                                pageDirPath: entry.pageDirPath,
                              );
                              if (mounted) {
                                Get.back();
                              }
                            } else {
                              _downloadService.deleteDownload(
                                entry: entry,
                                removeList: true,
                              );
                            }
                            GStorage.watchProgressStore.delete(
                              entry.cid.toString(),
                            );
                          },
                          controller: this,
                        );
                      },
                      itemCount: _downloadItems.length,
                    );
                  }
                  return const HttpError();
                }),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void onRemove() {
    showConfirmDialog(
      context: context,
      title: const Text('确定删除选中视频？'),
      onConfirm: () async {
        SmartDialog.showLoading();
        final allChecked = this.allChecked.toList();
        final isDeleteAll = allChecked.length == _downloadItems.length;
        if (isDeleteAll) {
          _stopListening();
        }
        await Future.wait([
          GStorage.watchProgressStore.deleteAll(
            allChecked.map((e) => e.cid.toString()),
          ),
          for (final entry in allChecked)
            _downloadService.deleteDownload(
              entry: entry,
              removeList: true,
              refresh: false,
            ),
        ]);
        _downloadService.flagNotifier.refresh();
        if (isDeleteAll) {
          SmartDialog.dismiss();
          if (mounted) {
            Get.back();
          }
        } else {
          if (enableMultiSelect.value) {
            rxCount.value = 0;
            enableMultiSelect.value = false;
          }
          SmartDialog.dismiss();
        }
      },
    );
  }
}
