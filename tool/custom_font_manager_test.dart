import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:PiliMax/utils/custom_font_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

const _keys = CustomFontStorageKeys(
  path: 'fontPath',
  family: 'fontFamily',
  name: 'fontName',
);

const _config = CustomFontConfig(
  directoryName: 'fonts',
  fileNamePrefix: 'custom_font',
  familyNamePrefix: 'custom_font',
  storageKeys: _keys,
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

  test('apply preserves naming and deletes only owned stale fonts', () async {
    final fontDir = await Directory(
      path.join(tempDir.path, 'fonts'),
    ).create(recursive: true);
    final oldFont = File(path.join(fontDir.path, 'custom_font_100.ttf'));
    await oldFont.writeAsBytes([9]);
    final manualFont = File(path.join(fontDir.path, 'manual.otf'));
    await manualFont.writeAsBytes([8]);
    final otherDomainFont = File(
      path.join(fontDir.path, 'custom_danmaku_font_9.otf'),
    );
    await otherDomainFont.writeAsBytes([7]);

    final sourceDir = await Directory(
      path.join(tempDir.path, 'source'),
    ).create();
    final source = File(path.join(sourceDir.path, 'Picked.OTF'));
    await source.writeAsBytes([1, 2, 3, 4]);

    final store = _MemoryFontSettingsStore({
      _keys.path: oldFont.path,
      _keys.family: 'custom_font_100',
      _keys.name: 'old.ttf',
    });
    final loaded = <({String path, String family})>[];
    final manager = CustomFontManager(
      config: _config,
      settingsStore: store,
      supportDirectory: () => tempDir.path,
      nowMilliseconds: () => 100,
      fontLoader: ({required fontPath, required fontFamily}) async {
        loaded.add((path: fontPath, family: fontFamily));
      },
    );

    await manager.apply(CustomFontFileSource(sourcePath: source.path));

    final target = File(path.join(fontDir.path, 'custom_font_101.otf'));
    expect(await target.readAsBytes(), [1, 2, 3, 4]);
    expect(source.existsSync(), isTrue);
    expect(oldFont.existsSync(), isFalse);
    expect(manualFont.existsSync(), isTrue);
    expect(otherDomainFont.existsSync(), isTrue);
    expect(store.values, {
      _keys.path: target.path,
      _keys.family: 'custom_font_101',
      _keys.name: 'Picked.OTF',
    });
    expect(loaded, [(path: target.path, family: 'custom_font_101')]);
  });

  test('failed settings write restores old settings and font', () async {
    final fontDir = await Directory(
      path.join(tempDir.path, 'fonts'),
    ).create(recursive: true);
    final oldFont = File(path.join(fontDir.path, 'custom_font_1.ttf'));
    await oldFont.writeAsBytes([1]);
    final previous = <String, Object?>{
      _keys.path: oldFont.path,
      _keys.family: 'custom_font_1',
      _keys.name: 'old.ttf',
    };
    final store = _MemoryFontSettingsStore(previous)
      ..failNextPutPartially = true;
    final manager = CustomFontManager(
      config: _config,
      settingsStore: store,
      supportDirectory: () => tempDir.path,
      nowMilliseconds: () => 200,
      fontLoader: ({required fontPath, required fontFamily}) async {},
    );

    await expectLater(
      manager.apply(
        CustomFontBytesSource(
          sourceName: 'new.ttf',
          bytes: Uint8List.fromList([2, 3]),
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(store.values, previous);
    expect(oldFont.existsSync(), isTrue);
    expect(
      File(path.join(fontDir.path, 'custom_font_200.ttf')).existsSync(),
      isFalse,
    );
  });

  test('concurrent applies are serialized and use distinct font ids', () async {
    final firstLoadStarted = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    final loadedFamilies = <String>[];
    final store = _MemoryFontSettingsStore({});
    final manager = CustomFontManager(
      config: _config,
      settingsStore: store,
      supportDirectory: () => tempDir.path,
      nowMilliseconds: () => 300,
      fontLoader: ({required fontPath, required fontFamily}) async {
        loadedFamilies.add(fontFamily);
        if (fontFamily == 'custom_font_300') {
          firstLoadStarted.complete();
          await releaseFirstLoad.future;
        }
      },
    );

    final first = manager.apply(
      CustomFontBytesSource(
        sourceName: 'first.ttf',
        bytes: Uint8List.fromList([1]),
      ),
    );
    await firstLoadStarted.future;
    final second = manager.apply(
      CustomFontBytesSource(
        sourceName: 'second.otf',
        bytes: Uint8List.fromList([2]),
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(loadedFamilies, ['custom_font_300']);

    releaseFirstLoad.complete();
    await Future.wait([first, second]);

    expect(loadedFamilies, ['custom_font_300', 'custom_font_301']);
    expect(store.values[_keys.family], 'custom_font_301');
    expect(
      File(
        path.join(tempDir.path, 'fonts', 'custom_font_300.ttf'),
      ).existsSync(),
      isFalse,
    );
    expect(
      File(
        path.join(tempDir.path, 'fonts', 'custom_font_301.otf'),
      ).existsSync(),
      isTrue,
    );
  });

  test('rollback uncertainty retains the newly loaded managed font', () async {
    final oldFontDir = await Directory(
      path.join(tempDir.path, 'fonts'),
    ).create(recursive: true);
    final oldFont = File(path.join(oldFontDir.path, 'custom_font_1.ttf'));
    await oldFont.writeAsBytes([1]);
    final store =
        _MemoryFontSettingsStore({
            _keys.path: oldFont.path,
            _keys.family: 'custom_font_1',
            _keys.name: 'old.ttf',
          })
          ..failNextPutPartially = true
          ..failNextDeletePartially = true;
    final manager = CustomFontManager(
      config: _config,
      settingsStore: store,
      supportDirectory: () => tempDir.path,
      nowMilliseconds: () => 400,
      fontLoader: ({required fontPath, required fontFamily}) async {},
    );

    await expectLater(
      manager.apply(
        CustomFontBytesSource(
          sourceName: 'new.ttf',
          bytes: Uint8List.fromList([2]),
        ),
      ),
      throwsA(isA<CustomFontSettingsException>()),
    );

    expect(
      File(
        path.join(tempDir.path, 'fonts', 'custom_font_400.ttf'),
      ).existsSync(),
      isTrue,
    );
  });

  test('clear never deletes external or unrelated font files', () async {
    final externalDir = await Directory(
      path.join(tempDir.path, 'external'),
    ).create();
    final externalFont = File(path.join(externalDir.path, 'external.ttf'));
    await externalFont.writeAsBytes([1]);

    final fontDir = await Directory(
      path.join(tempDir.path, 'fonts'),
    ).create();
    final managedFont = File(path.join(fontDir.path, 'custom_font_1.ttf'));
    final unrelatedFont = File(path.join(fontDir.path, 'personal.ttf'));
    await managedFont.writeAsBytes([2]);
    await unrelatedFont.writeAsBytes([3]);

    final otherDir = await Directory(
      path.join(tempDir.path, 'danmaku_fonts'),
    ).create();
    final danmakuFont = File(
      path.join(otherDir.path, 'custom_danmaku_font_1.ttf'),
    );
    await danmakuFont.writeAsBytes([4]);

    final store = _MemoryFontSettingsStore({
      _keys.path: externalFont.path,
      _keys.family: 'external_family',
      _keys.name: 'external.ttf',
    });
    final manager = CustomFontManager(
      config: _config,
      settingsStore: store,
      supportDirectory: () => tempDir.path,
      fontLoader: ({required fontPath, required fontFamily}) async {},
    );

    expect(await manager.clear(), isTrue);

    expect(store.values, isEmpty);
    expect(externalFont.existsSync(), isTrue);
    expect(managedFont.existsSync(), isFalse);
    expect(unrelatedFont.existsSync(), isTrue);
    expect(danmakuFont.existsSync(), isTrue);
  });

  test(
    'init load failure resets settings without deleting source font',
    () async {
      final externalDir = await Directory(
        path.join(tempDir.path, 'external'),
      ).create();
      final externalFont = File(path.join(externalDir.path, 'broken.ttf'));
      await externalFont.writeAsBytes([1]);

      final fontDir = await Directory(
        path.join(tempDir.path, 'fonts'),
      ).create();
      final staleManaged = File(path.join(fontDir.path, 'custom_font_1.ttf'));
      final unrelatedFont = File(path.join(fontDir.path, 'keep.ttf'));
      await staleManaged.writeAsBytes([2]);
      await unrelatedFont.writeAsBytes([3]);

      final store = _MemoryFontSettingsStore({
        _keys.path: externalFont.path,
        _keys.family: 'broken_family',
        _keys.name: 'broken.ttf',
      });
      var loadCount = 0;
      final manager = CustomFontManager(
        config: _config,
        settingsStore: store,
        supportDirectory: () => tempDir.path,
        fontLoader: ({required fontPath, required fontFamily}) {
          loadCount++;
          return Future<void>.error(const FormatException('invalid font'));
        },
      );

      await manager.init();

      expect(loadCount, 1);
      expect(store.values, isEmpty);
      expect(externalFont.existsSync(), isTrue);
      expect(staleManaged.existsSync(), isFalse);
      expect(unrelatedFont.existsSync(), isTrue);
    },
  );

  test(
    'init clears incomplete legacy settings and owned stale files',
    () async {
      final fontDir = await Directory(
        path.join(tempDir.path, 'fonts'),
      ).create();
      final staleManaged = File(path.join(fontDir.path, 'custom_font_1.ttf'));
      await staleManaged.writeAsBytes([1]);
      final store = _MemoryFontSettingsStore({_keys.name: 'stale.ttf'});
      var loadCount = 0;
      final manager = CustomFontManager(
        config: _config,
        settingsStore: store,
        supportDirectory: () => tempDir.path,
        fontLoader: ({required fontPath, required fontFamily}) async {
          loadCount++;
        },
      );

      await manager.init();

      expect(loadCount, 0);
      expect(store.values, isEmpty);
      expect(staleManaged.existsSync(), isFalse);
    },
  );

  test(
    'clear keeps the existing false result for empty setting values',
    () async {
      final store = _MemoryFontSettingsStore({
        _keys.path: '',
        _keys.family: '',
        _keys.name: '',
      });
      final manager = CustomFontManager(
        config: _config,
        settingsStore: store,
        supportDirectory: () => tempDir.path,
        fontLoader: ({required fontPath, required fontFamily}) async {},
      );

      expect(await manager.clear(), isFalse);
      expect(store.values, isEmpty);
    },
  );

  test(
    'failed clear restores settings before leaving files untouched',
    () async {
      final fontDir = await Directory(
        path.join(tempDir.path, 'fonts'),
      ).create();
      final currentFont = File(path.join(fontDir.path, 'custom_font_1.ttf'));
      await currentFont.writeAsBytes([1]);
      final previous = <String, Object?>{
        _keys.path: currentFont.path,
        _keys.family: 'custom_font_1',
        _keys.name: 'current.ttf',
      };
      final store = _MemoryFontSettingsStore(previous)
        ..failNextDeletePartially = true;
      final manager = CustomFontManager(
        config: _config,
        settingsStore: store,
        supportDirectory: () => tempDir.path,
        fontLoader: ({required fontPath, required fontFamily}) async {},
      );

      await expectLater(manager.clear(), throwsA(isA<StateError>()));

      expect(store.values, previous);
      expect(currentFont.existsSync(), isTrue);
    },
  );
}

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
