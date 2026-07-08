import 'package:PiliMax/common/widgets/appbar/appbar.dart';
import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/flutter/pop_scope.dart';
import 'package:PiliMax/common/widgets/loading_widget/http_error.dart';
import 'package:PiliMax/common/widgets/view_sliver_safe_area.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/pages/common/multi_select/base.dart'
    show BaseMultiSelectMixin;
import 'package:PiliMax/pages/download/detail/widgets/item.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/utils/grid.dart';
import 'package:flutter/material.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({super.key});

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage>
    with BaseMultiSelectMixin<BiliDownloadEntryInfo> {
  final _downloadService = Get.find<DownloadService>();
  late final _waitDownloadQueue = _downloadService.waitDownloadQueue;
  @override
  RxList<BiliDownloadEntryInfo> get list => _waitDownloadQueue;
  @override
  RxList<BiliDownloadEntryInfo> get state => _waitDownloadQueue;

  @override
  Widget build(BuildContext context) {
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
            child: AppBar(
              title: const Text('正在缓存'),
              actions: [
                IconButton(
                  tooltip: '全部开始',
                  onPressed: _downloadService.startAllDownloads,
                  icon: const Icon(Icons.play_arrow),
                ),
                IconButton(
                  tooltip: '全部暂停',
                  onPressed: _downloadService.pauseAllDownloads,
                  icon: const Icon(Icons.pause),
                ),
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
                  if (_waitDownloadQueue.isNotEmpty) {
                    return SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        mainAxisSpacing: 2,
                        mainAxisExtent: 100,
                        maxCrossAxisExtent: Grid.smallCardWidth * 2,
                      ),
                      itemCount: _waitDownloadQueue.length,
                      itemBuilder: (context, index) {
                        final entry = _waitDownloadQueue[index];
                        final isCurr = _downloadService.isActive(entry);
                        return DetailItem(
                          entry: entry,
                          downloadService: _downloadService,
                          showTitle: true,
                          isCurr: isCurr,
                          onDelete: () => _downloadService.deleteDownload(
                            entry: entry,
                            removeQueue: true,
                            downloadNext: isCurr,
                          ),
                          controller: this,
                        );
                      },
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
        final allChecked = this.allChecked.toSet();
        for (final entry in allChecked) {
          await _downloadService.deleteDownload(
            entry: entry,
            refresh: false,
            downloadNext: false,
          );
        }
        _downloadService.waitDownloadQueue.removeWhere(allChecked.contains);
        _downloadService.nextDownload();
        if (enableMultiSelect.value) {
          rxCount.value = 0;
          enableMultiSelect.value = false;
        }
        SmartDialog.dismiss();
      },
    );
  }
}
