import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show loadFontFromList;

import 'package:PiliMax/pilimax/models/common/danmaku/danmaku_font_sync_mode.dart';
import 'package:PiliMax/pilimax/utils/custom_font_gstorage_store.dart';
import 'package:PiliMax/pilimax/utils/custom_font_manager.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:file_picker/file_picker.dart';

final CustomFontManager pilimaxFontLibrary = CustomFontManager(
  settingsStore: const GStorageCustomFontSettingsStore(),
  config: CustomFontConfig(
    directoryName: 'font',
    fileNamePrefix: 'pilimax_font',
    familyNamePrefix: 'pilimax_font',
    libraryPathKey: SettingBoxKey.customAppFont,
    libraryNameKey: SettingBoxKey.customAppFontNames,
    selectionBindings: [
      const CustomFontSelectionBinding(
        selectionKey: SettingBoxKey.appFont,
      ),
      CustomFontSelectionBinding(
        selectionKey: SettingBoxKey.customDanmakuFontFamily,
        fallbackValues: {
          SettingBoxKey.danmakuFontSyncMode: DanmakuFontSyncMode.global.index,
        },
      ),
    ],
  ),
);

abstract final class AppFont {
  static const List<String> allowedExtensions =
      CustomFontManager.allowedExtensions;

  static const CustomFontStorageKeys _legacyAppKeys = CustomFontStorageKeys(
    path: SettingBoxKey.customFontPath,
    family: SettingBoxKey.customFontFamily,
    name: SettingBoxKey.customFontName,
  );

  static const CustomFontStorageKeys _legacyDanmakuKeys = CustomFontStorageKeys(
    path: SettingBoxKey.customDanmakuFontPath,
    family: SettingBoxKey.customDanmakuFontFamily,
    name: SettingBoxKey.customDanmakuFontName,
  );

  static List<CustomFontEntry> get fonts => pilimaxFontLibrary.fonts;

  static String? get currentFontName {
    final selected = currentSelection;
    return selected.isComplete ? selected.displayName : Pref.customFontName;
  }

  static CustomFontSelection get currentSelection =>
      pilimaxFontLibrary.selectionFor(Pref.effectiveAppFontFamily);

  static bool isCustomFont(String? fontFamily) =>
      pilimaxFontLibrary.isCustomFont(fontFamily);

  static String displayName(String fontFamily) =>
      pilimaxFontLibrary.displayName(fontFamily);

  static Future<void> init() => pilimaxFontLibrary.init(
    migrations: const [
      LegacyCustomFontMigration(
        directoryName: 'fonts',
        fileNamePrefix: 'custom_font',
        storageKeys: _legacyAppKeys,
        selectionKey: SettingBoxKey.appFont,
      ),
      LegacyCustomFontMigration(
        directoryName: 'danmaku_fonts',
        fileNamePrefix: 'custom_danmaku_font',
        storageKeys: _legacyDanmakuKeys,
        selectionKey: SettingBoxKey.customDanmakuFontFamily,
      ),
    ],
    activeFamilies: [
      Pref.effectiveAppFontFamily,
      if (Pref.danmakuFontSyncMode == DanmakuFontSyncMode.custom)
        Pref.customDanmakuFontFamily,
    ],
  );

  static Future<CustomFontImportResult> importFiles(
    Iterable<PlatformFile> files,
  ) async {
    final sources = <CustomFontSource>[];
    var failedCount = 0;
    for (final file in files) {
      try {
        final sourcePath = file.path;
        if (sourcePath != null &&
            sourcePath.isNotEmpty &&
            File(sourcePath).existsSync()) {
          sources.add(CustomFontFileSource(sourcePath: sourcePath));
        } else {
          sources.add(
            CustomFontBytesSource(
              sourceName: file.name,
              bytes: await file.readAsBytes(),
            ),
          );
        }
      } catch (_) {
        failedCount++;
      }
    }
    final result = await pilimaxFontLibrary.importFonts(sources);
    return CustomFontImportResult(
      fonts: result.fonts,
      failedCount: failedCount + result.failedCount,
    );
  }

  static Future<void> select(String fontFamily) =>
      pilimaxFontLibrary.selectExisting(
        fontFamily: fontFamily,
        selectionKey: SettingBoxKey.appFont,
        deleteKeys: _legacyAppKeys.all,
      );

  static Future<void> selectSystemFont(String? fontFamily) async {
    if (isCustomFont(fontFamily)) {
      throw StateError('custom fonts must be selected through AppFont.select');
    }
    await pilimaxFontLibrary.selectValue(
      selectionKey: SettingBoxKey.appFont,
      fontFamily: fontFamily,
      deleteKeys: _legacyAppKeys.all,
    );
  }

  static Future<void> ensureLoaded(String fontFamily) =>
      pilimaxFontLibrary.ensureLoaded(fontFamily);

  static Future<void> removeFont(String fontFamily) =>
      pilimaxFontLibrary.removeFont(fontFamily);

  static Future<void> clearFonts() => pilimaxFontLibrary.clearFonts();

  /// Loads a font family for a page-local preview without changing settings.
  static Future<void> loadPreview({
    required String fontFamily,
    required Uint8List bytes,
  }) => loadFontFromList(bytes, fontFamily: fontFamily);

  /// Clears only the App selection. Imported files remain in the shared pool.
  static Future<bool> clear() async {
    final hadCustomFont =
        currentSelection.isComplete ||
        Pref.customFontFamily != null ||
        Pref.customFontPath != null;
    await selectSystemFont(null);
    return hadCustomFont;
  }
}
