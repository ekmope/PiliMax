import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliMax/pages/search/controller.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/device_utils.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/utils/parse_int.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/pilimax/utils/app_font.dart';
import 'package:PiliMax/pilimax/utils/custom_font_manager.dart'
    show CustomFontBytesSource;
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:archive/archive.dart';
import 'package:get/get.dart';

class ImportResult {
  const ImportResult({required this.applied, this.message});

  /// 是否已执行（false 表示取消）
  final bool applied;

  /// 附加提示，无则为 null
  final String? message;
}

abstract final class ConfigArchive {
  static const String metaFileName = 'meta.json';
  static const String settingFileName = 'setting.json';
  static const String accountFileName = 'account.json';
  static const String blacklistFileName = 'blacklist.json';
  static const String replyFileName = 'reply.json';
  static const String searchFileName = 'search.json';
  static const String _fontManifestFileName = 'fonts.json';
  static const String _legacyFontFileName = 'customFont.otf';

  /// These values contain paths into this installation's private font pool.
  /// Importing them would replace valid local paths with paths from another
  /// device, so font files are restored through the managed font library.
  static const Set<String> _localFontSettingKeys = {
    SettingBoxKey.customAppFont,
    SettingBoxKey.customAppFontNames,
    SettingBoxKey.customFontPath,
    SettingBoxKey.customFontFamily,
    SettingBoxKey.customFontName,
    SettingBoxKey.customDanmakuFontPath,
    SettingBoxKey.customDanmakuFontFamily,
    SettingBoxKey.customDanmakuFontName,
  };

  static const String _type = 'data_archive';

  /// 归档格式版本
  static const int _majorVersion = 0x0001;
  static const int _minorVersion = 0x0000;

  /// 搜索历史的存储 key
  static const String _searchCacheKey = 'cacheList';

  /// 解压后总大小上限
  static const int _maxTotalBytes = 64 * 1024 * 1024;

  static void export(OutputStream stream) {
    final zip = ZipEncoder()
      ..startEncode(stream)
      ..add(ArchiveFile.string(settingFileName, GStorage.exportAllSettings()))
      ..add(ArchiveFile.string(accountFileName, _exportAccount()))
      ..add(ArchiveFile.string(blacklistFileName, _exportBlacklist()));

    final reply = _exportReply();
    if (reply != null) {
      zip.add(ArchiveFile.string(replyFileName, reply));
    }

    _addSelectedFont(zip);

    zip
      ..add(ArchiveFile.string(searchFileName, _exportSearch()))
      ..add(ArchiveFile.string(metaFileName, _buildMeta()))
      ..endEncode();
    return;
  }

  static Future<String?> import(
    Uint8List bytes, {
    required Future<bool> Function(String warning) onWarning,
  }) async {
    if (bytes.length > _maxTotalBytes) {
      throw UnsupportedError('数据包过大');
    }

    final archive = ZipDecoder().decodeBytes(bytes);

    // 校验 meta
    final metaFile = archive.find(metaFileName);
    if (metaFile == null) {
      throw UnsupportedError('不是有效的数据包（缺少 $metaFileName）');
    }
    final meta = jsonDecode(utf8.decode(metaFile.content));
    if (meta is! Map || meta['type'] != _type) {
      throw UnsupportedError('不是有效的数据包');
    }

    // 校验 formatVersion
    final format = _parseFormat(meta['formatVersion']);
    if (format == null) {
      throw UnsupportedError('不是有效的数据包（缺少合法的 formatVersion）');
    }
    if (format.major > _majorVersion) {
      throw UnsupportedError('数据包格式过新（${format.toVersionString()}），请升级应用后再导入');
    }

    final warning = _warningOf(meta);
    if (warning != null && !await onWarning(warning)) {
      return null;
    }

    final sb = StringBuffer();
    var totalBytes = 0;

    Future<void> apply<T>(
      String name,
      FutureOr<void> Function(T) action,
    ) async {
      if (archive.find(name) case final file?) {
        totalBytes += file.size;
        if (totalBytes > _maxTotalBytes) throw UnsupportedError('数据包过大');

        try {
          await action(jsonDecode(utf8.decode(file.content)) as T);
        } catch (e) {
          sb.writeln('$name：$e');
        } finally {
          file.closeSync();
        }
      }
    }

    await apply(settingFileName, _importSettings);
    await apply(accountFileName, Accounts.importJsonAccount);
    await apply(blacklistFileName, _importBlacklist);
    await apply(replyFileName, _importReply);
    await apply(searchFileName, _importSearch);

    totalBytes = await _importFont(archive, totalBytes, sb);

    return sb.toString();
  }

  /// 生成合并警告
  static String? _warningOf(Map meta) {
    final warnings = StringBuffer();

    final format = _parseFormat(meta['formatVersion']);
    if (format != null &&
        format.major == _majorVersion &&
        format.minor > _minorVersion) {
      warnings.writeln('此数据包使用更新的归档格式（${format.toVersionString()}），部分数据可能无法识别');
    }

    final sourceApp = meta['appName'];
    if (sourceApp != Constants.appName) {
      warnings.writeln('此数据包来自「$sourceApp」，与当前应用不同，可能不完全兼容');
    }

    final packageCode = safeToInt(meta['versionCode']);
    if (packageCode != null && packageCode > BuildConfig.versionCode) {
      final versionName = meta['versionName'];
      warnings.writeln(
        '此数据包来自更新版本（v$versionName，构建号 $packageCode），'
        '当前应用较旧（v${BuildConfig.versionName}，构建号 ${BuildConfig.versionCode}），'
        '部分数据可能无法正确还原',
      );
    }
    return warnings.isEmpty ? null : warnings.toString();
  }

  /// 解析 [主, 次] 格式版本
  static VersionCode? _parseFormat(Object? value) {
    if (value is int) {
      return VersionCode(value);
    }
    return null;
  }

  static String _exportAccount() => jsonEncode(Accounts.account.toMap());

  static String _exportBlacklist() => jsonEncode(Pref.blackMids.toList());

  static String? _exportReply() {
    final store = GStorage.replyCacheStore;
    if (!store.isEnabled) return null;
    return jsonEncode(
      store.values.map((e) => ReplyInfo.fromBuffer(e).toProto3Json()).toList(),
    );
  }

  static void _addSelectedFont(ZipEncoder zip) {
    final selection = AppFont.currentSelection;
    final family = selection.fontFamily;
    final file = _selectedFontFile();
    if (family == null || file == null) return;

    zip
      ..add(
        ArchiveFile.stream(
          _legacyFontFileName,
          InputFileStream(file.path),
        ),
      )
      ..add(
        ArchiveFile.string(
          _fontManifestFileName,
          jsonEncode({
            'version': 1,
            'sourceFamily': family,
            'displayName': selection.displayName,
            'file': _legacyFontFileName,
          }),
        ),
      );
  }

  static File? _selectedFontFile() {
    final selection = AppFont.currentSelection;
    final fontPath = selection.fontPath;
    if (!selection.isComplete || fontPath == null) return null;
    final file = File(fontPath);
    return file.existsSync() ? file : null;
  }

  static Future<int> _importFont(
    Archive archive,
    int totalBytes,
    StringBuffer errors,
  ) async {
    final manifestFile = archive.find(_fontManifestFileName);
    if (manifestFile != null) {
      totalBytes = _addBytes(totalBytes, manifestFile.size);
      try {
        final manifest = jsonDecode(utf8.decode(manifestFile.content));
        if (manifest is! Map || manifest['file'] != _legacyFontFileName) {
          throw const FormatException('字体清单格式不正确');
        }

        final fontFile = archive.find(_legacyFontFileName);
        if (fontFile == null) {
          throw const FormatException('字体文件缺失');
        }
        totalBytes = _addBytes(totalBytes, fontFile.size);
        try {
          final imported = await pilimaxFontLibrary.importFont(
            CustomFontBytesSource(
              sourceName: _legacyFontFileName,
              preferredDisplayName: manifest['displayName'] is String
                  ? manifest['displayName'] as String
                  : null,
              bytes: Uint8List.fromList(fontFile.content),
            ),
          );
          await AppFont.select(imported.fontFamily);
        } finally {
          fontFile.closeSync();
        }
      } catch (error) {
        errors.writeln('$_fontManifestFileName：$error');
      } finally {
        manifestFile.closeSync();
      }
      return totalBytes;
    }

    // Archives produced by earlier PiliPlus releases contain only
    // customFont.otf and identify the selected family in setting.json.
    final legacyFile = archive.find(_legacyFontFileName);
    if (legacyFile == null) return totalBytes;
    totalBytes = _addBytes(totalBytes, legacyFile.size);
    try {
      final family = GStorage.setting.get(SettingBoxKey.appFont);
      if (family is! String || !family.contains('/')) {
        errors.writeln('$_legacyFontFileName：无法获取字体名');
        return totalBytes;
      }
      final imported = await pilimaxFontLibrary.importFont(
        CustomFontBytesSource(
          sourceName: _legacyFontFileName,
          bytes: Uint8List.fromList(legacyFile.content),
        ),
      );
      await AppFont.select(imported.fontFamily);
    } catch (error) {
      errors.writeln('$_legacyFontFileName：$error');
    } finally {
      legacyFile.closeSync();
    }
    return totalBytes;
  }

  static int _addBytes(int totalBytes, int fileSize) {
    final nextTotal = totalBytes + fileSize;
    if (nextTotal > _maxTotalBytes) throw UnsupportedError('数据包过大');
    return nextTotal;
  }

  static String _exportSearch() {
    final list = GStorage.historyWord.get(_searchCacheKey);
    return jsonEncode(list ?? const <String>[]);
  }

  static String _buildMeta() => jsonEncode({
    'type': _type,
    'formatVersion': const VersionCode.fromMajorMinor(
      _majorVersion,
      _minorVersion,
    ),
    'appName': Constants.appName,
    'versionCode': BuildConfig.versionCode,
    'versionName': BuildConfig.versionName,
    'commitHash': BuildConfig.commitHash,
    'buildTime': BuildConfig.buildTime,
    'platform': DeviceUtils.platformName,
    'exportTime': DateTime.now().toIso8601String(),
    'files': [
      settingFileName,
      accountFileName,
      blacklistFileName,
      if (GStorage.replyCacheStore.isEnabled) replyFileName,
      searchFileName,
      if (_selectedFontFile() != null) ...[
        _legacyFontFileName,
        _fontManifestFileName,
      ],
    ],
  });

  static Future<void> _importSettings(Map<String, dynamic> data) async {
    // 先校验结构，避免 clear 后 putAll 失败导致旧设置丢失
    if (data[GStorage.setting.name] is! Map ||
        data[GStorage.video.name] is! Map) {
      throw ArgumentError('设置数据格式不正确');
    }

    // Paths in the archive belong to its source device. Preserve this
    // installation's font library and let the font import below add a
    // managed entry before selecting it.
    for (final section in [GStorage.setting.name, 'settings']) {
      final values = data[section];
      if (values is Map) {
        final sanitized = Map<dynamic, dynamic>.from(values)
          ..removeWhere(
            (key, _) => key is String && _localFontSettingKeys.contains(key),
          );
        data[section] = sanitized;
      }
    }
    await GStorage.importAllJsonSettings(data);
  }

  static void _importBlacklist(List<dynamic> list) {
    // 就地覆盖，保持已有引用
    final set = GlobalData().blackMids
      ..clear()
      ..addAll(Set<int>.from(list));
    Pref.blackMids = set;
  }

  static Future<void> _importReply(List<dynamic> list) async {
    final entries = <String, Uint8List>{};
    for (final item in list) {
      if (item is! Map || item['id'] == null) continue;
      final json = <String, dynamic>{
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      entries[item['id'].toString()] =
          (ReplyInfo.create()..mergeFromProto3Json(json)).writeToBuffer();
    }
    await GStorage.replyCacheStore.putAll(entries);
  }

  static void _importSearch(List<dynamic> list) {
    final history = List<String>.from(list);
    GStorage.historyWord.put(_searchCacheKey, history);
    // 同步刷新内存单例，避免被旧列表覆盖
    if (Get.isRegistered<BaseSearchController>()) {
      Get.find<BaseSearchController>().historyList.assignAll(history);
    }
  }
}

extension type VersionCode(int _version) {
  int get major => _version >>> 16;
  int get minor => _version & 0xFFFF;

  const VersionCode.fromMajorMinor(int major, int minor)
    : _version = (major << 16) | minor;

  String toVersionString() => '$major.$minor';
}
