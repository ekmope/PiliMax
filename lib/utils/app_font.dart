import 'package:PiliMax/utils/custom_font_gstorage_store.dart';
import 'package:PiliMax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/storage_key.dart';

abstract final class AppFont {
  static const List<String> allowedExtensions =
      CustomFontManager.allowedExtensions;

  static final CustomFontManager _manager = CustomFontManager(
    settingsStore: const GStorageCustomFontSettingsStore(),
    config: const CustomFontConfig(
      directoryName: 'fonts',
      fileNamePrefix: 'custom_font',
      familyNamePrefix: 'custom_font',
      storageKeys: CustomFontStorageKeys(
        path: SettingBoxKey.customFontPath,
        family: SettingBoxKey.customFontFamily,
        name: SettingBoxKey.customFontName,
      ),
    ),
  );

  static String? get currentFontName => _manager.currentFontName;

  static Future<void> init() => _manager.init();

  static Future<bool> pickAndApply() => _manager.pickAndApply();

  static Future<bool> clear() => _manager.clear();
}
