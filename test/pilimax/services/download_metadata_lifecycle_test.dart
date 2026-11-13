import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/video/play/url.dart';
import 'package:PiliMax/models_new/download/bili_download_entry_info.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _ControlledDownloadService service;
  late BiliDownloadEntryInfo entry;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pilimax-metadata-');
    service = _ControlledDownloadService();
    entry = _entry(directory.path);
    await Directory(entry.entryDirPath).create(recursive: true);
    await _writeEntry(entry);
    service.downloadList.add(entry);
  });
  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test(
    'late metadata response cannot overwrite a new download at the same path',
    () async {
      final update = service.updateVolume(entry);
      await service.requested.future;
      await service.deleteDownload(
        entry: entry,
        removeList: true,
        refresh: false,
      );
      final replacement = _entry(directory.path);
      await Directory(replacement.entryDirPath).create(recursive: true);
      await _writeEntry(replacement, marker: 'new generation');
      service.downloadList.add(replacement);

      service.playUrl.complete(Success(_playUrl()));
      expect(await update, DownloadMetadataUpdateResult.removed);
      final saved = jsonDecode(
        await File(path.join(entry.entryDirPath, 'entry.json')).readAsString(),
      );
      expect(saved['marker'], 'new generation');
      expect(saved.containsKey('volume'), isFalse);
      expect(replacement.volume, isNull);
    },
  );

  test('late danmaku response cannot overwrite a re-downloaded file', () async {
    final update = service.downloadDanmaku(entry: entry, isUpdate: true);
    await service.requested.future;
    await service.deleteDownload(
      entry: entry,
      removeList: true,
      refresh: false,
    );
    final replacement = _entry(directory.path);
    await Directory(replacement.entryDirPath).create(recursive: true);
    final file = File(
      path.join(replacement.entryDirPath, PathUtils.danmakuName),
    );
    await file.writeAsBytes([9, 8, 7]);
    service.downloadList.add(replacement);

    service.danmaku.complete([1, 2, 3]);
    expect(await update, isFalse);
    expect(await file.readAsBytes(), [9, 8, 7]);
  });

  test('deleting a page rejects an in-flight metadata response', () async {
    final update = service.updateVolume(entry);
    await service.requested.future;
    await service.deletePage(pageDirPath: entry.pageDirPath, refresh: false);
    service.playUrl.complete(Success(_playUrl()));
    expect(await update, DownloadMetadataUpdateResult.removed);
    expect(service.downloadList, isEmpty);
    expect(Directory(entry.pageDirPath).existsSync(), isFalse);
  });

  test(
    'deletion waits for an already open metadata commit before removing files',
    () async {
      final realFile = File(path.join(entry.entryDirPath, 'entry.json'));
      final metaFile = File(
        path.join(entry.entryDirPath, PathUtils.playbackMetaName),
      );
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      final delayedFile = _DelayedWriteFile(
        realFile,
        writeStarted,
        releaseWrite,
      );
      final update = IOOverrides.runZoned(
        () => service.updateVolume(entry),
        createFile: (name) {
          if (path.equals(name, metaFile.path)) return metaFile;
          expect(path.equals(name, realFile.path), isTrue);
          return delayedFile;
        },
      );
      await service.requested.future;
      service.playUrl.complete(Success(_playUrl()));
      await writeStarted.future;
      var deleted = false;
      final deletion = service
          .deleteDownload(
            entry: entry,
            removeList: true,
            refresh: false,
          )
          .then((_) => deleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(deleted, isFalse);
      expect(Directory(entry.entryDirPath).existsSync(), isTrue);
      releaseWrite.complete();
      expect(await update, DownloadMetadataUpdateResult.removed);
      await deletion;
      expect(deleted, isTrue);
      expect(Directory(entry.entryDirPath).existsSync(), isFalse);
    },
  );

  test('a stale delete callback cannot remove a replacement entry', () async {
    final replacement = _entry(directory.path);
    service.downloadList
      ..remove(entry)
      ..add(replacement);
    await _writeEntry(replacement, marker: 'replacement');
    await service.deleteDownload(
      entry: entry,
      removeList: true,
      refresh: false,
    );
    expect(service.downloadList.single, same(replacement));
    final saved = jsonDecode(
      await File(path.join(entry.entryDirPath, 'entry.json')).readAsString(),
    );
    expect(saved['marker'], 'replacement');
  });
}

class _ControlledDownloadService extends DownloadService {
  final requested = Completer<void>();
  final playUrl = Completer<LoadingState<PlayUrlModel>>();
  final danmaku = Completer<List<int>>();

  @override
  Future<LoadingState<PlayUrlModel>> fetchPlayUrlMetadata(
    BiliDownloadEntryInfo entry,
  ) {
    requested.complete();
    return playUrl.future;
  }

  @override
  Future<List<int>> fetchDanmakuBytes(BiliDownloadEntryInfo entry) {
    requested.complete();
    return danmaku.future;
  }
}

class _DelayedWriteFile implements File {
  _DelayedWriteFile(this.file, this.started, this.release);
  final File file;
  final Completer<void> started;
  final Completer<void> release;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    started.complete();
    await release.future;
    return file.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _writeEntry(BiliDownloadEntryInfo entry, {String? marker}) =>
    File(path.join(entry.entryDirPath, 'entry.json')).writeAsString(
      jsonEncode({
        ...entry.toJson(),
        'marker': ?marker,
      }),
    );

PlayUrlModel _playUrl() => PlayUrlModel()
  ..volume = Volume.fromJson({
    'measured_i': -18,
    'measured_lra': 8,
    'measured_tp': -12,
    'measured_threshold': -28,
    'target_offset': 1,
    'target_i': -16,
    'target_tp': -1,
  });

BiliDownloadEntryInfo _entry(String directory) =>
    BiliDownloadEntryInfo(
        isCompleted: true,
        totalBytes: 100,
        downloadedBytes: 100,
        title: '视频',
        cover: '',
        typeTag: '80',
        preferedVideoQuality: 80,
        guessedTotalBytes: 100,
        totalTimeMilli: 1000,
        danmakuCount: 0,
        avid: 1,
        bvid: 'BV1',
        ownerId: 42,
        ownerName: 'UP',
        autoFolderTitle: '我的合集',
        autoFolderSourceKey: 'ugc-season:5',
        autoFolderIndex: 7,
        pageData: PageInfo(cid: 11, page: 1, hasAlias: false, tid: 0),
      )
      ..pageDirPath = path.join(directory, '1')
      ..entryDirPath = path.join(directory, '1', 'c_11');
