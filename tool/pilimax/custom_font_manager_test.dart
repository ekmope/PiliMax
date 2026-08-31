import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/pilimax/utils/custom_font_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

const _libraryPathKey = 'fontLibraryPaths';
const _libraryNameKey = 'fontLibraryNames';
const _selectionKey = 'fontFamily';
const _modeKey = 'fontMode';
const _legacyPathKey = 'legacyPath';

const _legacyKeys = CustomFontStorageKeys(
  path: _legacyPathKey,
  family: 'legacyFamily',
  name: 'legacyName',
);

const _config = CustomFontConfig(
  directoryName: 'font_library',
  fileNamePrefix: 'pilimax_font',
  familyNamePrefix: 'pilimax_font',
  libraryPathKey: _libraryPathKey,
  libraryNameKey: _libraryNameKey,
  selectionBindings: [
    CustomFontSelectionBinding(
      selectionKey: _selectionKey,
      fallbackValues: {_modeKey: 0},
      fallbackDeletes: {_legacyPathKey},
    ),
  ],
);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pilimax-font-test-');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('imports into the shared pool and deduplicates by content', () async {
    final libraryDir = await Directory(
      path.join(tempDir.path, _config.directoryName),
    ).create(recursive: true);
    final manualFont = File(path.join(libraryDir.path, 'manual.otf'));
    await manualFont.writeAsBytes([8]);

    final sourceDir = await Directory(
      path.join(tempDir.path, 'source'),
    ).create();
    final source = File(path.join(sourceDir.path, 'Picked.OTF'));
    final bytes = _testFontBytes('Shared Font', marker: 1);
    await source.writeAsBytes(bytes);

    final store = _MemoryFontSettingsStore({});
    final loaded = <({String path, String family})>[];
    final manager = _manager(
      tempDir,
      store,
      fontLoader: ({required fontPath, required fontFamily}) async {
        loaded.add((path: fontPath, family: fontFamily));
      },
    );

    final first = await manager.importFont(
      CustomFontFileSource(sourcePath: source.path),
    );
    final duplicate = await manager.importFont(
      CustomFontBytesSource(sourceName: 'duplicate.ttf', bytes: bytes),
    );

    expect(duplicate.fontFamily, first.fontFamily);
    expect(duplicate.fontPath, first.fontPath);
    expect(first.displayName, 'Shared Font');
    expect(source.existsSync(), isTrue);
    expect(manualFont.existsSync(), isTrue);
    expect(loaded, [(path: first.fontPath, family: first.fontFamily)]);
    expect(store.values[_libraryPathKey], {
      first.fontFamily: first.fontPath,
    });
    expect(store.values[_libraryNameKey], {
      first.fontFamily: 'Shared Font',
    });
  });

  test('selects an imported font without copying it again', () async {
    final store = _MemoryFontSettingsStore({});
    final manager = _manager(tempDir, store);
    final entry = await manager.importFont(
      CustomFontBytesSource(
        sourceName: 'selected.ttf',
        bytes: _testFontBytes('Selected Font', marker: 2),
      ),
    );

    await manager.selectExisting(
      fontFamily: entry.fontFamily,
      selectionKey: _selectionKey,
    );

    expect(store.values[_selectionKey], entry.fontFamily);
    expect(manager.selectionFor(entry.fontFamily).displayName, 'Selected Font');
  });

  test('rejects a non-font without persisting or retaining it', () async {
    final store = _MemoryFontSettingsStore({});
    final manager = _manager(tempDir, store);

    await expectLater(
      manager.importFont(
        CustomFontBytesSource(
          sourceName: 'fake.ttf',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(store.values, isEmpty);
    expect(await _managedFiles(tempDir), isEmpty);
  });

  test(
    'failed settings write restores settings and removes new file',
    () async {
      final previous = <String, Object?>{
        _libraryPathKey: const <String, String>{},
        _libraryNameKey: const <String, String>{},
      };
      final store = _MemoryFontSettingsStore(previous)
        ..failNextPutPartially = true;
      final manager = _manager(tempDir, store);

      await expectLater(
        manager.importFont(
          CustomFontBytesSource(
            sourceName: 'new.ttf',
            bytes: _testFontBytes('Rollback Font', marker: 3),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      expect(store.values, previous);
      expect(await _managedFiles(tempDir), isEmpty);
    },
  );

  test('rollback uncertainty retains the newly loaded managed font', () async {
    final store = _MemoryFontSettingsStore({})
      ..failNextPutPartially = true
      ..failNextDeletePartially = true;
    final manager = _manager(tempDir, store);

    await expectLater(
      manager.importFont(
        CustomFontBytesSource(
          sourceName: 'uncertain.ttf',
          bytes: _testFontBytes('Uncertain Font', marker: 4),
        ),
      ),
      throwsA(isA<CustomFontSettingsException>()),
    );

    expect(await _managedFiles(tempDir), hasLength(1));
  });

  test('clear removes managed files and preserves unrelated files', () async {
    final store = _MemoryFontSettingsStore({_legacyPathKey: 'stale'});
    final manager = _manager(tempDir, store);
    final entry = await manager.importFont(
      CustomFontBytesSource(
        sourceName: 'clear.ttf',
        bytes: _testFontBytes('Clear Font', marker: 5),
      ),
    );
    await manager.selectExisting(
      fontFamily: entry.fontFamily,
      selectionKey: _selectionKey,
    );

    final libraryDir = Directory(path.dirname(entry.fontPath));
    final unrelated = File(path.join(libraryDir.path, 'personal.ttf'));
    await unrelated.writeAsBytes([1]);
    final external = File(path.join(tempDir.path, 'external.ttf'));
    await external.writeAsBytes([2]);

    await manager.clearFonts();

    expect(File(entry.fontPath).existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
    expect(external.existsSync(), isTrue);
    expect(store.values[_libraryPathKey], <String, String>{});
    expect(store.values[_libraryNameKey], <String, String>{});
    expect(store.values.containsKey(_selectionKey), isFalse);
    expect(store.values.containsKey(_legacyPathKey), isFalse);
    expect(store.values[_modeKey], 0);
  });

  test('valid legacy selection migrates into the shared pool', () async {
    final legacyDir = await Directory(
      path.join(tempDir.path, 'legacy_fonts'),
    ).create();
    final legacyFile = File(path.join(legacyDir.path, 'custom_font_1.ttf'));
    await legacyFile.writeAsBytes(_testFontBytes('Legacy Font', marker: 6));
    final store = _MemoryFontSettingsStore({
      _legacyKeys.path: legacyFile.path,
      _legacyKeys.family: 'custom_font_1',
      _legacyKeys.name: 'legacy.ttf',
    });
    final manager = _manager(tempDir, store);

    await manager.init(
      migrations: const [
        LegacyCustomFontMigration(
          directoryName: 'legacy_fonts',
          fileNamePrefix: 'custom_font',
          storageKeys: _legacyKeys,
          selectionKey: _selectionKey,
        ),
      ],
    );

    final selected = store.values[_selectionKey];
    expect(selected, isA<String>());
    expect(manager.isCustomFont(selected as String), isTrue);
    expect(store.values.containsKey(_legacyKeys.path), isFalse);
    expect(store.values.containsKey(_legacyKeys.family), isFalse);
    expect(store.values.containsKey(_legacyKeys.name), isFalse);
    expect(legacyFile.existsSync(), isFalse);
  });

  test('missing legacy file clears only a matching stale selection', () async {
    const staleFamily = 'custom_font_9';
    final store = _MemoryFontSettingsStore({
      _legacyKeys.path: 'missing.ttf',
      _legacyKeys.family: staleFamily,
      _legacyKeys.name: 'missing.ttf',
      _selectionKey: staleFamily,
    });
    final manager = _manager(tempDir, store);

    await manager.init(
      migrations: const [
        LegacyCustomFontMigration(
          directoryName: 'legacy_fonts',
          fileNamePrefix: 'custom_font',
          storageKeys: _legacyKeys,
          selectionKey: _selectionKey,
        ),
      ],
    );

    expect(store.values.containsKey(_legacyKeys.path), isFalse);
    expect(store.values.containsKey(_legacyKeys.family), isFalse);
    expect(store.values.containsKey(_legacyKeys.name), isFalse);
    expect(store.values.containsKey(_selectionKey), isFalse);
    expect(store.values[_modeKey], 0);
  });

  test(
    'new danmaku selection survives a second startup migration pass',
    () async {
      final firstStore = _MemoryFontSettingsStore({});
      final firstManager = _manager(tempDir, firstStore);
      final entry = await firstManager.importFont(
        CustomFontBytesSource(
          sourceName: 'danmaku.ttf',
          bytes: _testFontBytes('Danmaku Font', marker: 7),
        ),
      );
      await firstManager.selectExisting(
        fontFamily: entry.fontFamily,
        selectionKey: _selectionKey,
      );

      final secondManager = _manager(tempDir, firstStore);
      await secondManager.init(
        migrations: const [
          LegacyCustomFontMigration(
            directoryName: 'legacy_fonts',
            fileNamePrefix: 'custom_font',
            storageKeys: CustomFontStorageKeys(
              path: 'danmakuLegacyPath',
              family: _selectionKey,
              name: 'danmakuLegacyName',
            ),
            selectionKey: _selectionKey,
          ),
        ],
      );

      expect(firstStore.values[_selectionKey], entry.fontFamily);
      expect(secondManager.isCustomFont(entry.fontFamily), isTrue);
    },
  );

  test('init repairs a dangling managed-family selection', () async {
    final staleFamily = 'pilimax_font_${'a' * 40}';
    final store = _MemoryFontSettingsStore({_selectionKey: staleFamily});
    final manager = _manager(tempDir, store);

    await manager.init();

    expect(store.values.containsKey(_selectionKey), isFalse);
    expect(store.values[_modeKey], 0);
  });
}

CustomFontManager _manager(
  Directory tempDir,
  _MemoryFontSettingsStore store, {
  CustomFontLoaderCallback? fontLoader,
}) => CustomFontManager(
  config: _config,
  settingsStore: store,
  supportDirectory: () => tempDir.path,
  nowMicroseconds: () => 100,
  fontLoader:
      fontLoader ??
      ({required String fontPath, required String fontFamily}) async {},
);

Future<List<File>> _managedFiles(Directory tempDir) async {
  final directory = Directory(path.join(tempDir.path, _config.directoryName));
  if (!directory.existsSync()) return [];
  return [
    await for (final entity in directory.list())
      if (entity is File &&
          path
              .basename(entity.path)
              .startsWith(
                '${_config.fileNamePrefix}_',
              ))
        entity,
  ];
}

Uint8List _testFontBytes(String name, {required int marker}) {
  final nameBytes = <int>[
    for (final unit in name.codeUnits) ...[unit >> 8, unit & 0xFF],
  ];
  final nameTable = Uint8List(18 + nameBytes.length);
  _writeNameTableHeader(
    ByteData.sublistView(nameTable),
    nameBytes.length,
  );
  nameTable.setRange(18, nameTable.length, nameBytes);

  final tables = <String, Uint8List>{
    'cmap': Uint8List.fromList([0, 0, 0, marker]),
    'glyf': Uint8List.fromList([marker]),
    'head': Uint8List(54),
    'maxp': Uint8List(6),
    'name': nameTable,
  };
  final directoryLength = 12 + tables.length * 16;
  final totalLength =
      directoryLength +
      tables.values.fold<int>(0, (sum, table) => sum + table.length);
  final bytes = Uint8List(totalLength);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, tables.length);

  var recordOffset = 12;
  var tableOffset = directoryLength;
  for (final entry in tables.entries) {
    data
      ..setUint32(recordOffset, _tag(entry.key))
      ..setUint32(recordOffset + 4, 0)
      ..setUint32(recordOffset + 8, tableOffset)
      ..setUint32(recordOffset + 12, entry.value.length);
    bytes.setRange(tableOffset, tableOffset + entry.value.length, entry.value);
    recordOffset += 16;
    tableOffset += entry.value.length;
  }
  return bytes;
}

void _writeNameTableHeader(ByteData nameData, int nameLength) {
  nameData
    ..setUint16(0, 0)
    ..setUint16(2, 1)
    ..setUint16(4, 18)
    ..setUint16(6, 3)
    ..setUint16(8, 1)
    ..setUint16(10, 0x0409)
    ..setUint16(12, 4)
    ..setUint16(14, nameLength)
    ..setUint16(16, 0);
}

int _tag(String value) => value.codeUnits.fold<int>(
  0,
  (result, unit) => (result << 8) | unit,
);

final class _MemoryFontSettingsStore implements CustomFontSettingsStore {
  _MemoryFontSettingsStore(Map<String, Object?> initialValues)
    : values = Map.of(initialValues);

  final Map<String, Object?> values;
  bool failNextPutPartially = false;
  bool failNextDeletePartially = false;

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  Object? read(String key) => values[key];

  @override
  Future<void> putAll(Map<String, Object?> newValues) async {
    if (failNextPutPartially) {
      failNextPutPartially = false;
      final first = newValues.entries.first;
      values[first.key] = first.value;
      throw StateError('simulated settings write failure');
    }
    values.addAll(newValues);
  }

  @override
  Future<void> deleteAll(Iterable<String> keys) async {
    if (failNextDeletePartially) {
      failNextDeletePartially = false;
      values.remove(keys.first);
      throw StateError('simulated settings delete failure');
    }
    for (final key in keys) {
      values.remove(key);
    }
  }
}
