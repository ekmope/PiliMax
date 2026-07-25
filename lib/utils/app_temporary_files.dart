import 'dart:io';

import 'package:PiliMax/utils/path_utils.dart';
import 'package:path/path.dart' as path;

enum AppTemporaryOwner {
  cache('cache'),
  logExport('log_export'),
  crashReportExport('crash_report_export');

  final String directoryName;

  const AppTemporaryOwner(this.directoryName);
}

final class OwnedTemporaryDirectories {
  final Directory root;

  const OwnedTemporaryDirectories(this.root);

  Directory directory(AppTemporaryOwner owner) =>
      Directory(path.join(root.path, owner.directoryName));

  Future<Directory> ensure(AppTemporaryOwner owner) =>
      directory(owner).create(recursive: true);

  Future<Directory> reset(AppTemporaryOwner owner) async {
    await clear(owner);
    return ensure(owner);
  }

  Future<void> clear(AppTemporaryOwner owner) async {
    final target = directory(owner);
    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
  }

  bool ownsPath(String candidate, {AppTemporaryOwner? owner}) {
    final base = owner == null ? root.path : directory(owner).path;
    final normalizedBase = path.normalize(path.absolute(base));
    final normalizedCandidate = path.normalize(path.absolute(candidate));
    return path.equals(normalizedBase, normalizedCandidate) ||
        path.isWithin(normalizedBase, normalizedCandidate);
  }
}

abstract final class AppTemporaryFiles {
  static OwnedTemporaryDirectories get _directories =>
      OwnedTemporaryDirectories(Directory(tmpDirPath));

  static Directory directory(AppTemporaryOwner owner) =>
      _directories.directory(owner);

  static Future<Directory> ensure(AppTemporaryOwner owner) =>
      _directories.ensure(owner);

  static Future<Directory> reset(AppTemporaryOwner owner) =>
      _directories.reset(owner);

  static Future<void> clear(AppTemporaryOwner owner) =>
      _directories.clear(owner);

  static bool ownsPath(String candidate, {AppTemporaryOwner? owner}) =>
      _directories.ownsPath(candidate, owner: owner);
}
