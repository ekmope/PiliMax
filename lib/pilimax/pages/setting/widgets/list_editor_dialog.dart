import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// A dialog for editing a list of strings with add/remove/edit functionality
/// Follows Material Design 3 style
class ListEditorDialog extends StatefulWidget {
  final String title;
  final List<String> initialItems;
  final String hintText;
  final String itemLabel;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String)? validator;
  // When false, existing items use SelectableText instead of editable TextField
  final bool allowEdit;

  const ListEditorDialog({
    super.key,
    required this.title,
    required this.initialItems,
    this.hintText = '点击添加按钮添加项目',
    this.itemLabel = '项目',
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.allowEdit = true,
  });

  @override
  State<ListEditorDialog> createState() => _ListEditorDialogState();
}

class _ListEditorDialogState extends State<ListEditorDialog> {
  late List<String> _items;
  late List<TextEditingController> _controllers;
  final TextEditingController _addController = TextEditingController();
  final FocusNode _addFocusNode = FocusNode();
  final Map<TextEditingController, String> _editErrors = {};
  final Set<TextEditingController> _retiredControllers = {};
  String? _addError;

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(widget.initialItems);
    _controllers = _items.map((e) => TextEditingController(text: e)).toList();
    if (widget.allowEdit) {
      _validateEdits();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final c in _retiredControllers) {
      c.dispose();
    }
    _retiredControllers.clear();
    _addController.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  bool _addItem() {
    final value = _addController.text.trim();
    if (value.isEmpty) {
      if (_addError != null) setState(() => _addError = null);
      return true;
    }
    final error = _addItemError(value);
    if (error != null) {
      setState(() => _addError = error);
      return false;
    }
    setState(() {
      _items.add(value);
      _controllers.add(TextEditingController(text: value));
      _addController.clear();
      _addError = null;
    });
    return true;
  }

  String? _addItemError(String value) {
    final error = widget.validator?.call(value);
    if (error != null) return error;
    if (_controllers.any((controller) => controller.text.trim() == value)) {
      return '该${widget.itemLabel}已存在';
    }
    return null;
  }

  String? _validationError(String value) {
    if (value.isEmpty) return '${widget.itemLabel}不能为空';
    return widget.validator?.call(value);
  }

  void _refreshAddError() {
    if (_addError == null) return;
    final value = _addController.text.trim();
    _addError = value.isEmpty ? null : _addItemError(value);
  }

  String? _errorTextOf(TextEditingController controller) {
    if (_editErrors[controller] case final error?) return error;
    final value = controller.text.trim();
    if (_controllers.any(
      (other) => other != controller && other.text.trim() == value,
    )) {
      return '该${widget.itemLabel}已存在';
    }
    return null;
  }

  void _updateEditError(TextEditingController controller) {
    final error = _validationError(controller.text.trim());
    if (error == null) {
      _editErrors.remove(controller);
    } else {
      _editErrors[controller] = error;
    }
  }

  bool _validateEdits() {
    if (!widget.allowEdit) return true;
    for (final controller in _controllers) {
      _updateEditError(controller);
    }
    return _controllers.every((controller) => _errorTextOf(controller) == null);
  }

  void _commitEdit(TextEditingController controller) {
    final index = _controllers.indexOf(controller);
    if (index == -1) return;
    setState(() {
      _updateEditError(controller);
      if (_errorTextOf(controller) == null) {
        _items[index] = controller.text.trim();
      }
      _refreshAddError();
    });
  }

  void _removeItem(int index) {
    final controller = _controllers[index];
    setState(() {
      _editErrors.remove(controller);
      _items.removeAt(index);
      _controllers.removeAt(index);
      _retiredControllers.add(controller);
      _refreshAddError();
    });
    // Let the removed TextField detach its listeners before disposing its
    // controller. The dialog's dispose handles an earlier route removal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retiredControllers.remove(controller)) controller.dispose();
    });
  }

  void _save() {
    // Validate the visible controller values, including an edit that still has
    // focus. Never return a previous valid value in place of an invalid edit.
    var editsValid = false;
    setState(() => editsValid = _validateEdits());
    if (!editsValid || !_addItem()) return;
    final result = widget.allowEdit
        ? _controllers.map((controller) => controller.text.trim()).toList()
        : List<String>.from(_items);
    Get.back(result: result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    focusNode: _addFocusNode,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      isDense: true,
                      errorText: _addError,
                    ),
                    onChanged: (_) {
                      if (_addError == null) return;
                      setState(_refreshAddError);
                    },
                    onSubmitted: (_) => _addItem(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _addItem,
                  tooltip: '添加',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '暂无${widget.itemLabel}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final controller = _controllers[index];
                      return Card(
                        key: ObjectKey(controller),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(
                            left: 12,
                            right: 4,
                            top: 4,
                            bottom: 4,
                          ),
                          title: widget.allowEdit
                              ? TextField(
                                  controller: controller,
                                  keyboardType: widget.keyboardType,
                                  inputFormatters: widget.inputFormatters,
                                  style: theme.textTheme.bodyMedium,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    errorText: _errorTextOf(controller),
                                  ),
                                  onChanged: (_) {
                                    setState(() {
                                      _updateEditError(controller);
                                      _refreshAddError();
                                    });
                                  },
                                  onSubmitted: (_) => _commitEdit(controller),
                                  onTapOutside: (_) => _commitEdit(controller),
                                )
                              : SelectableText(
                                  _items[index],
                                  style: theme.textTheme.bodyMedium,
                                ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _removeItem(index),
                            tooltip: '删除',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
