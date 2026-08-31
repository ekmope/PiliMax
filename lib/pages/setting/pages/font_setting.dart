import 'dart:io';
import 'dart:typed_data';

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
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

class FontSettingPage extends StatefulWidget {
  const FontSettingPage({super.key});

  @override
  State<FontSettingPage> createState() => _FontSettingPageState();
}

final class _PendingFont {
  const _PendingFont({
    required this.sourceName,
    required this.bytes,
  });

  final String sourceName;
  final Uint8List bytes;

  String get displayName => path.basename(sourceName);
}

final class _FontSettingPageState extends State<FontSettingPage> {
  static const double _tileHeight = 45.0;

  late final List<String> _fonts;
  late final bool _initialCustomFont;
  late ColorScheme _colorScheme;
  late bool _isPortrait;
  late ScrollController _scrollController;

  String? _selectedFont;
  String? _selectedDisplayName;
  bool _selectedCustom = false;
  int _selectedWeight = FontWeight.values.indexOf(Pref.appFontWeight);
  double _selectedScale = Pref.defaultTextScale;
  bool _saving = false;

  final Map<String, _PendingFont> _customFonts = {};

  @override
  void initState() {
    super.initState();
    final current = AppFont.currentSelection;
    _initialCustomFont = current.isComplete;
    _selectedCustom = _initialCustomFont;
    _selectedFont = _initialCustomFont ? current.fontFamily : Pref.appFont;
    _selectedDisplayName = current.displayName;
    _fonts = FontUtils.getFont().toList()..sort();

    if (!_selectedCustom && _selectedFont != null) {
      final index = _fonts.indexOf(_selectedFont!);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(index * _tileHeight);
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

  @override
  void dispose() {
    _customFonts.clear();
    super.dispose();
  }

  Future<void> _importFonts() async {
    SmartDialog.showLoading();
    var changed = false;
    String? lastFamily;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppFont.allowedExtensions,
      );
      if (files.isEmpty) return;

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      for (var index = 0; index < files.length; index++) {
        final file = files[index];
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        final family = 'pilimax_preview_font_${timestamp}_$index';
        await AppFont.loadPreview(fontFamily: family, bytes: bytes);
        final sourceName = file.path ?? file.name;
        _customFonts[family] = _PendingFont(
          sourceName: sourceName,
          bytes: bytes,
        );
        lastFamily = family;
        changed = true;
      }
    } catch (error) {
      SmartDialog.showToast('字体加载失败: $error');
    } finally {
      SmartDialog.dismiss();
      if (mounted && changed && lastFamily != null) {
        setState(() {
          _selectedFont = lastFamily;
          _selectedDisplayName = _customFonts[lastFamily]!.displayName;
          _selectedCustom = true;
        });
      }
    }
  }

  Future<void> _saveFontSetting() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      if (_selectedCustom) {
        final pending = _selectedFont == null
            ? null
            : _customFonts[_selectedFont];
        if (pending != null) {
          await AppFont.apply(
            CustomFontBytesSource(
              sourceName: pending.sourceName,
              bytes: pending.bytes,
            ),
          );
        } else if (!AppFont.currentSelection.isComplete ||
            AppFont.currentSelection.fontFamily != _selectedFont) {
          throw StateError('所选字体不可用，请重新导入');
        }
        await GStorage.setting.delete(SettingBoxKey.appFont);
      } else {
        await AppFont.clear();
        if (_selectedFont == null) {
          await GStorage.setting.delete(SettingBoxKey.appFont);
        } else {
          await GStorage.setting.put(SettingBoxKey.appFont, _selectedFont);
        }
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
      _selectedDisplayName = isCustom
          ? _customFonts[value]?.displayName ??
                (AppFont.currentSelection.fontFamily == value
                    ? AppFont.currentFontName
                    : null)
          : null;
    });
  }

  Color? _tileColor(String? value, {bool isCustom = false}) {
    if (_selectedFont == value && _selectedCustom == isCustom) {
      return _colorScheme.onInverseSurface;
    }
    return null;
  }

  Widget _buildCustomFontTile(String family, _PendingFont? pending) {
    final displayName =
        pending?.displayName ??
        (family == AppFont.currentSelection.fontFamily
            ? AppFont.currentFontName
            : null) ??
        family;
    return ListTile(
      minTileHeight: _tileHeight,
      tileColor: _tileColor(family, isCustom: true),
      onTap: () => _onFontChanged(
        family,
        isCustom: true,
      ),
      title: Text(
        displayName,
        style: TextStyle(fontFamily: family),
      ),
      trailing: pending == null
          ? null
          : iconButton(
              size: 38,
              iconSize: 22,
              tooltip: '移除',
              onPressed: () {
                setState(() {
                  if (_selectedCustom && _selectedFont == family) {
                    _selectedFont = null;
                    _selectedDisplayName = null;
                    _selectedCustom = false;
                  }
                  _customFonts.remove(family);
                });
              },
              icon: const Icon(Icons.clear),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final persistedCustomFamily = AppFont.currentSelection.fontFamily;
    final customFontTiles = <Widget>[
      if (persistedCustomFamily != null &&
          !_customFonts.containsKey(persistedCustomFamily))
        _buildCustomFontTile(persistedCustomFamily, null),
      for (final entry in _customFonts.entries)
        _buildCustomFontTile(entry.key, entry.value),
    ];

    return SimpleScaffold(
      appBar: AppBar(
        title: const Text('App字体设置'),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    _selectedFont = null;
                    _selectedDisplayName = null;
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
                    fontFamily: _selectedFont ?? '',
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
                                  ? (_selectedDisplayName ??
                                        _selectedFont ??
                                        '自定义字体')
                                  : _selectedFont ?? '默认',
                              style: TextStyle(
                                fontSize: 15,
                                fontFamily: _selectedFont ?? '',
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
