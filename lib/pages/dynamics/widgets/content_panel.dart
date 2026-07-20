// 内容
import 'package:PiliMax/common/widgets/custom_icon.dart';
import 'package:PiliMax/common/widgets/dialog/dialog.dart';
import 'package:PiliMax/common/widgets/flutter/text/text.dart' as custom_text;
import 'package:PiliMax/common/widgets/image_grid/image_grid_view.dart';
import 'package:PiliMax/common/widgets/selectable_text.dart';
import 'package:PiliMax/models/dynamics/result.dart';
import 'package:PiliMax/pages/dynamics/widgets/rich_node_panel.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

Widget content(
  BuildContext context, {
  required int floor,
  required ThemeData theme,
  required DynamicItemModel item,
  required bool isSave,
  required bool isDetail,
}) {
  TextSpan? richNodes = richNode(
    context,
    theme: theme,
    item: item,
  );
  final moduleDynamic = item.modules.moduleDynamic;
  final pics = moduleDynamic?.major?.opus?.pics;
  final text =
      moduleDynamic?.desc?.text ?? moduleDynamic?.major?.opus?.summary?.text;
  return Padding(
    padding: floor == 1
        ? const EdgeInsets.fromLTRB(12, 0, 12, 6)
        : const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (moduleDynamic?.topic case final topic?)
          GestureDetector(
            onTap: () => Get.toNamed(
              '/dynTopic',
              parameters: {
                'id': topic.id!.toString(),
                'name': topic.name!,
              },
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        size: 18,
                        CustomIcons.topic_tag,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  TextSpan(text: topic.name),
                ],
              ),
              style: TextStyle(
                fontSize: floor != 1
                    ? 14
                    : isDetail && !isSave
                    ? 16
                    : 15,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (richNodes != null)
          isDetail && floor == 1
              ? SelectionText.rich(
                  richNodes,
                  style: isSave
                      ? const TextStyle(fontSize: 15)
                      : const TextStyle(fontSize: 16),
                  contextMenuBuilder: (context, state, selectedText) {
                    if (text == null || text.isEmpty) {
                      return AdaptiveTextSelectionToolbar.selectableRegion(
                        selectableRegionState: state,
                      );
                    }
                    return _contextMenuBuilder(
                      context,
                      state,
                      selectedText,
                      text,
                    );
                  },
                )
              : custom_text.Text.rich(
                  style: floor == 1
                      ? const TextStyle(fontSize: 15)
                      : const TextStyle(fontSize: 14),
                  richNodes,
                  maxLines: isSave ? null : 6,
                  onShowMore: () => PageUtils.pushDynDetail(item, isPush: true),
                  primary: theme.colorScheme.primary,
                ),
        if (pics != null && pics.isNotEmpty)
          ImageGridView(
            fullScreen: true,
            picArr: pics
                .map(
                  (item) => ImageModel(
                    width: item.width,
                    height: item.height,
                    url: item.url ?? '',
                    liveUrl: item.liveUrl,
                  ),
                )
                .toList(),
          ),
      ],
    ),
  );
}

Widget _contextMenuBuilder(
  BuildContext context,
  SelectableRegionState state,
  String? selectedText,
  String text,
) {
  final items = state.contextMenuButtonItems;
  if (selectedText != null && selectedText.isNotEmpty) {
    final insertIndex = items.length >= 3 ? 3 : items.length;
    items.insert(
      insertIndex,
      ContextMenuButtonItem(
        onPressed: () {
          state.hideToolbar();
          final escapedText = RegExp.escape(selectedText);

          showConfirmDialog(
            context: context,
            title: const Text('是否将以下内容加入动态过滤：'),
            content: Text(
              escapedText,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: .bold,
              ),
            ),
            onConfirm: () {
              final currentStored = Pref.banWordForDyn;
              final existingKeywords = currentStored.isEmpty
                  ? <String>[]
                  : currentStored.split('\n');
              if (existingKeywords.contains(escapedText)) {
                SmartDialog.showToast('该关键词已在过滤列表中');
                return;
              }
              final newStored = currentStored.isEmpty
                  ? escapedText
                  : '$currentStored\n$escapedText';
              GStorage.setting.put(SettingBoxKey.banWordForDyn, newStored);
              final newPattern = Pref.parseBanWordToRegex(newStored);
              DynamicsDataModel.banWordForDyn =
                  RegExp(newPattern, caseSensitive: true);
              DynamicsDataModel.enableFilter = true;
              SmartDialog.showToast('已保存');
            },
          );
        },
        label: '加入过滤',
      ),
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    buttonItems: items
      ..add(
        ContextMenuButtonItem(
          label: '文本',
          onPressed: () {
            state.hideToolbar();
            _onCopyText(context, text);
          },
        ),
      ),
    anchors: state.contextMenuAnchors,
  );
}

void _onCopyText(BuildContext context, String text) {
  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Padding(
        padding: const .symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: SelectionText(
            text,
            style: const TextStyle(fontSize: 15, height: 1.7),
            contextMenuBuilder: (context, state, selectedText) =>
                _contextMenuBuilder(context, state, selectedText, text),
          ),
        ),
      ),
    ),
  );
}
