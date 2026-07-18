import 'package:PiliMax/utils/custom_font_gstorage_store.dart';
import 'package:PiliMax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/storage_key.dart';

abstract final class DanmakuFont {
  static const List<String> allowedExtensions =
      CustomFontManager.allowedExtensions;

  static final CustomFontManager _manager = CustomFontManager(
    settingsStore: const GStorageCustomFontSettingsStore(),
    config: const CustomFontConfig(
      directoryName: 'danmaku_fonts',
      fileNamePrefix: 'custom_danmaku_font',
      familyNamePrefix: 'custom_danmaku_font',
      storageKeys: CustomFontStorageKeys(
        path: SettingBoxKey.customDanmakuFontPath,
        family: SettingBoxKey.customDanmakuFontFamily,
        name: SettingBoxKey.customDanmakuFontName,
      ),
    ),
  );

  static String? get currentFontName => _manager.currentFontName;

  static Future<void> init() => _manager.init();

  static Future<bool> pickAndApply() => _manager.pickAndApply();

  static Future<bool> clear() => _manager.clear();
}
