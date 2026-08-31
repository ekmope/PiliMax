import 'dart:async';
import 'dart:io';

import 'package:PiliMax/common/widgets/button/icon_button.dart';
import 'package:PiliMax/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliMax/pilimax/utils/app_font.dart';
import 'package:PiliMax/pilimax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/extension/box_ext.dart';
import 'package:PiliMax/utils/extension/get_ext.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/extension/scroll_controller_ext.dart';
import 'package:PiliMax/utils/extension/size_ext.dart';
import 'package:PiliMax/utils/font_utils.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class FontSettingPage extends StatefulWidget {
  const FontSettingPage({super.key});

  @override
  State<FontSettingPage> createState() => _FontSettingPageState();
}

final class _FontSettingPageState extends State<FontSettingPage> {
  static const double _tileHeight = 45.0;
  static final String? _platformDefaultFontFamily =
      (switch (defaultTargetPlatform) {
        TargetPlatform.iOS => Typography.whiteCupertino,
        TargetPlatform.android ||
        TargetPlatform.fuchsia => Typography.whiteMountainView,
        TargetPlatform.windows => Typography.whiteRedmond,
        TargetPlatform.macOS => Typography.whiteRedwoodCity,
        TargetPlatform.linux => Typography.whiteHelsinki,
      }).bodyMedium?.fontFamily;

  late final List<String> _fonts;
  late final bool _initialCustomFont;
  late ColorScheme _colorScheme;
  late bool _isPortrait;
  late ScrollController _scrollController;

  String? _selectedFont;
  bool _selectedCustom = false;
  int _selectedWeight = FontWeight.values.indexOf(Pref.appFontWeight);
  double _selectedScale = Pref.defaultTextScale;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final selected = Pref.effectiveAppFontFamily;
    final legacyCustom = Pref.customFontFamily;
    _initialCustomFont =
        AppFont.isCustomFont(selected) ||
        (legacyCustom != null && legacyCustom == selected);
    _selectedCustom = _initialCustomFont;
    _selectedFont = selected;
    _fonts = FontUtils.getFont().toList()..sort();

    if (!_selectedCustom && _selectedFont != null) {
      final index = _fonts.indexOf(_selectedFont!);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            final tileIndex = 1 + AppFont.fonts.length + index;
            _scrollController.jumpTo(tileIndex * _tileHeight);
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
    _scrollController = PrimaryScrollController.of(context);
  }

  Future<void> _importFonts() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppFont.allowedExtensions,
    );
    if (files.isEmpty) return;

    SmartDialog.showLoading();
    try {
      final result = await AppFont.importFiles(files);
      if (!mounted) return;
      if (result.fonts.isNotEmpty) {
        final selected = result.fonts.last;
        setState(() {
          _selectedFont = selected.fontFamily;
          _selectedCustom = true;
        });
      }
      if (result.failedCount != 0) {
        SmartDialog.showToast(
          result.fonts.isEmpty ? '字体导入失败' : '${result.failedCount} 个字体导入失败',
        );
      }
    } catch (error) {
      SmartDialog.showToast('字体导入失败: $error');
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<void> _saveFontSetting() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (_selectedCustom) {
        final selected = _selectedFont;
        if (selected == null) {
          throw StateError('所选字体不可用，请重新选择');
        }
        if (AppFont.isCustomFont(selected)) {
          await AppFont.select(selected);
        } else if (!_initialCustomFont ||
            selected != Pref.effectiveAppFontFamily) {
          throw StateError('所选字体不可用，请重新导入');
        }
      } else {
        await AppFont.selectSystemFont(_selectedFont);
      }

      await GStorage.setting.putAllNE({
        SettingBoxKey.appFontWeightV2: _selectedWeight,
        SettingBoxKey.defaultTextScale: _selectedScale,
      });

      if (!mounted) return;
      Get
        ..back()
        ..updateMyAppTheme()
        ..appUpdate();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        SmartDialog.showToast('字体设置保存失败: $error');
      }
    }
  }

  void _onFontChanged(String? value, {bool isCustom = false}) {
    if (_selectedFont == value && _selectedCustom == isCustom) return;
    setState(() {
      _selectedFont = value;
      _selectedCustom = isCustom;
    });
    if (isCustom && value != null && AppFont.isCustomFont(value)) {
      unawaited(_loadForPreview(value));
    }
  }

  Future<void> _loadForPreview(String fontFamily) async {
    try {
      await AppFont.ensureLoaded(fontFamily);
      if (mounted) setState(() {});
    } catch (error) {
      SmartDialog.showToast('字体加载失败: $error');
    }
  }

  Color? _tileColor(String? value, {bool isCustom = false}) {
    if (_selectedFont == value && _selectedCustom == isCustom) {
      return _colorScheme.onInverseSurface;
    }
    return null;
  }

  Widget _buildCustomFontTile(CustomFontEntry font) {
    final family = font.fontFamily;
    return ListTile(
      minTileHeight: _tileHeight,
      tileColor: _tileColor(family, isCustom: true),
      onTap: () => _onFontChanged(
        family,
        isCustom: true,
      ),
      title: Text(
        font.displayName,
        style: TextStyle(fontFamily: family),
      ),
      trailing: iconButton(
        size: 38,
        iconSize: 22,
        tooltip: '移除',
        onPressed: () => _confirmRemoveFont(font),
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }

  Future<void> _confirmRemoveFont(CustomFontEntry font) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除字体'),
        content: Text('确认移除“${font.displayName}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final appWasUsing = Pref.effectiveAppFontFamily == font.fontFamily;
    try {
      await AppFont.removeFont(font.fontFamily);
    } catch (error) {
      SmartDialog.showToast('字体移除失败: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_selectedCustom && _selectedFont == font.fontFamily) {
        _selectedFont = null;
        _selectedCustom = false;
      }
    });
    if (appWasUsing) {
      Get
        ..updateMyAppTheme()
        ..appUpdate();
    }
  }

  Future<void> _confirmClearFonts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空字体库'),
        content: const Text('确认移除全部已导入字体？App 与弹幕中正在使用的字体会恢复默认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final appWasUsing = AppFont.isCustomFont(Pref.effectiveAppFontFamily);
    final selectedWasImported = AppFont.isCustomFont(_selectedFont);
    try {
      await AppFont.clearFonts();
    } catch (error) {
      SmartDialog.showToast('字体库清空失败: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_selectedCustom && selectedWasImported) {
        _selectedFont = null;
        _selectedCustom = false;
      }
    });
    if (appWasUsing) {
      Get
        ..updateMyAppTheme()
        ..appUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final importedFonts = AppFont.fonts;
    final customFontTiles = importedFonts.map(_buildCustomFontTile).toList();

    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('App字体设置'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _selectedFont = null;
                    _selectedCustom = false;
                    _selectedWeight = FontWeight.values.indexOf(
                      FontWeight.normal,
                    );
                    _selectedScale = 1.0;
                  }),
            child: const Text('重置'),
          ),
          TextButton(
            onPressed: _saving ? null : _saveFontSetting,
            child: const Text('确定'),
          ),
          if (importedFonts.isNotEmpty)
            iconButton(
              tooltip: '清空字体库',
              onPressed: _saving ? null : _confirmClearFonts,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Flex(
          direction: _isPortrait ? Axis.vertical : Axis.horizontal,
          children: [
            Expanded(
              flex: _isPortrait ? 1 : 2,
              child: Center(
                child: Text(
                  'abcdefghijklmnopqrstuvwxyz\n'
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'
                  '1234567890.:,;\'"(!?)+-*/=\n'
                  '${Platform.isWindows
                      ? "中国智造，惠及全球"
                      : Platform.isMacOS || Platform.isIOS
                      ? "汉体书写信息技术标准相容"
                      : "我能吞下玻璃而不伤身体"}\n\n'
                  '注：部分字体可能无法应用',
                  style: TextStyle(
                    fontFamily: _selectedFont ?? _platformDefaultFontFamily,
                    fontWeight: FontWeight.values[_selectedWeight],
                    fontSize: 14 * _selectedScale,
                  ),
                ),
              ),
            ),
            _isPortrait
                ? Divider(
                    height: 1,
                    color: _colorScheme.primary.withValues(alpha: 0.3),
                  )
                : VerticalDivider(
                    width: 1,
                    color: _colorScheme.primary.withValues(alpha: 0.3),
                  ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _scrollController.jumpToTop,
                      child: Row(
                        children: [
                          const Text(
                            '字体：',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _selectedCustom
                                  ? (_selectedFont == null
                                        ? '自定义字体'
                                        : AppFont.displayName(_selectedFont!))
                                  : _selectedFont ?? '默认',
                              style: TextStyle(
                                fontSize: 15,
                                fontFamily:
                                    _selectedFont ?? _platformDefaultFontFamily,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: iconButton(
                              size: 32,
                              iconSize: 20,
                              tooltip: '导入',
                              context: context,
                              onPressed: _saving ? null : _importFonts,
                              icon: const Icon(Icons.add),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Material(
                      type: MaterialType.transparency,
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: ListTile(
                              minTileHeight: _tileHeight,
                              tileColor: _tileColor(null),
                              onTap: () => _onFontChanged(null),
                              title: const Text('默认'),
                            ),
                          ),
                          ...customFontTiles.map(
                            (tile) => SliverToBoxAdapter(child: tile),
                          ),
                          if (_fonts.isNotEmpty)
                            SliverList.builder(
                              itemCount: _fonts.length,
                              itemBuilder: (context, index) {
                                final font = _fonts[index];
                                return ListTile(
                                  minTileHeight: _tileHeight,
                                  tileColor: _tileColor(font),
                                  onTap: () => _onFontChanged(font),
                                  title: Text(
                                    font,
                                    style: TextStyle(fontFamily: font),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  _buildItem(
                    Row(
                      children: [
                        const Text(
                          '字重：',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(
                          width: 40,
                          child: Text(
                            'w100',
                            style: TextStyle(fontWeight: FontWeight.w100),
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            padding: EdgeInsets.zero,
                            value: _selectedWeight.toDouble(),
                            min: 0,
                            max: 8,
                            divisions: 8,
                            secondaryTrackValue: FontWeight.values
                                .indexOf(FontWeight.normal)
                                .toDouble(),
                            label: 'w${(_selectedWeight + 1) * 100}',
                            onChanged: (value) {
                              setState(
                                () => _selectedWeight = value.toInt(),
                              );
                            },
                          ),
                        ),
                        const SizedBox(
                          width: 50,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'w900',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildItem(
                    Row(
                      children: [
                        const Text(
                          '字号：',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(
                          width: 40,
                          child: Text('小', style: TextStyle(fontSize: 11.9)),
                        ),
                        Expanded(
                          child: Slider(
                            padding: EdgeInsets.zero,
                            value: _selectedScale,
                            min: 0.85,
                            max: 1.6,
                            divisions: 15,
                            secondaryTrackValue: 1,
                            label: _selectedScale == 1.0
                                ? '默认'
                                : _selectedScale.toStringAsFixed(2),
                            onChanged: (value) => setState(
                              () => _selectedScale = value.toPrecision(2),
                            ),
                          ),
                        ),
                        const SizedBox(
                          width: 50,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '大',
                              style: TextStyle(fontSize: 22.4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: child,
    );
  }
}
