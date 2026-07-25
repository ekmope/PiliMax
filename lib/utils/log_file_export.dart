import 'dart:io';

import 'package:PiliMax/utils/app_temporary_files.dart';
import 'package:PiliMax/utils/log_redactor.dart';
import 'package:PiliMax/utils/share_utils.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

abstract final class LogFileExport {
  static final _safeFilePrefix = RegExp(r'^[a-z0-9_]+$');

  static String buildExportText(String content) =>
      LogRedactor.redactText(content);

  static String buildFileName(String filePrefix, DateTime timestamp) {
    if (!_safeFilePrefix.hasMatch(filePrefix)) {
      throw ArgumentError.value(
        filePrefix,
        'filePrefix',
        'Only lowercase letters, digits, and underscores are allowed',
      );
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    String threeDigits(int value) => value.toString().padLeft(3, '0');

    return '${filePrefix}_'
        '${timestamp.year}'
        '${twoDigits(timestamp.month)}'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}_'
        '${threeDigits(timestamp.millisecond)}.log';
  }

  static Future<File> writeToDirectory({
    required String content,
    required String filePrefix,
    required Directory directory,
    DateTime? timestamp,
  }) async {
    final file = File(
      p.join(
        directory.path,
        buildFileName(filePrefix, timestamp ?? DateTime.now()),
      ),
    );
    await file.writeAsString(buildExportText(content), flush: true);
    return file;
  }

  static Future<bool> share({
    required String content,
    required String filePrefix,
    required String subject,
  }) async {
    if (content.trim().isEmpty) return false;

    final directory = await AppTemporaryFiles.reset(
      AppTemporaryOwner.logExport,
    );
    final file = await writeToDirectory(
      content: content,
      filePrefix: filePrefix,
      directory: directory,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: subject,
        sharePositionOrigin: await ShareUtils.sharePositionOrigin,
      ),
    );
    return true;
  }
}
