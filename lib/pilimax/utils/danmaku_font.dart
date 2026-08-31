import 'package:PiliMax/pilimax/models/common/danmaku/danmaku_font_sync_mode.dart';
import 'package:PiliMax/pilimax/utils/app_font.dart';
import 'package:PiliMax/pilimax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:file_picker/file_picker.dart';

abstract final class DanmakuFont {
  static const List<String> allowedExtensions =
      CustomFontManager.allowedExtensions;

  static List<CustomFontEntry> get fonts => pilimaxFontLibrary.fonts;

  static CustomFontSelection get currentSelection =>
      pilimaxFontLibrary.selectionFor(Pref.customDanmakuFontFamily);

  static String? get currentFontName {
    final selected = currentSelection;
    return selected.isComplete
        ? selected.displayName
        : Pref.customDanmakuFontName;
  }

  static Future<void> init() => AppFont.init();

  static Future<CustomFontImportResult> importFiles(
    Iterable<PlatformFile> files,
  ) => AppFont.importFiles(files);

  static Future<void> select(String fontFamily) =>
      pilimaxFontLibrary.selectExisting(
        fontFamily: fontFamily,
        selectionKey: SettingBoxKey.customDanmakuFontFamily,
        deleteKeys: const {
          SettingBoxKey.customDanmakuFontPath,
          SettingBoxKey.customDanmakuFontName,
        },
        additionalValues: {
          SettingBoxKey.danmakuFontSyncMode: DanmakuFontSyncMode.custom.index,
          SettingBoxKey.enableCustomDanmakuFont: true,
        },
      );

  /// Clears only the independent selection. The shared font stays reusable.
  static Future<bool> clear() async {
    final hadCustomFont =
        Pref.customDanmakuFontFamily != null ||
        Pref.customDanmakuFontPath != null;
    await pilimaxFontLibrary.selectValue(
      selectionKey: SettingBoxKey.customDanmakuFontFamily,
      fontFamily: null,
      deleteKeys: const {
        SettingBoxKey.customDanmakuFontPath,
        SettingBoxKey.customDanmakuFontName,
      },
    );
    return hadCustomFont;
  }
}
