import 'dart:io';

import 'package:mime/mime.dart';

enum UploadImagePurpose {
  dynamicImage,
  directMessage,
  avatar,
  favoriteCover,
}

class UploadImageValidationException implements Exception {
  const UploadImageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ValidatedUploadImage {
  const ValidatedUploadImage({
    required this.path,
    required this.length,
    required this.mimeType,
  });

  final String path;
  final int length;
  final String mimeType;

  String get mimeSubtype => mimeType.substring(mimeType.indexOf('/') + 1);
}

class UploadImagePolicy {
  const UploadImagePolicy({
    required this.maxBytes,
    required this.allowedMimeTypes,
  });

  final int maxBytes;
  final Set<String> allowedMimeTypes;
}

abstract final class UploadImageValidator {
  static const int _mib = 1024 * 1024;
  static const Set<String> _commonImageTypes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  };

  static const Map<UploadImagePurpose, UploadImagePolicy> policies = {
    UploadImagePurpose.dynamicImage: UploadImagePolicy(
      maxBytes: 20 * _mib,
      allowedMimeTypes: _commonImageTypes,
    ),
    UploadImagePurpose.directMessage: UploadImagePolicy(
      maxBytes: 20 * _mib,
      allowedMimeTypes: _commonImageTypes,
    ),
    UploadImagePurpose.avatar: UploadImagePolicy(
      maxBytes: 5 * _mib,
      allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp'},
    ),
    UploadImagePurpose.favoriteCover: UploadImagePolicy(
      maxBytes: 10 * _mib,
      allowedMimeTypes: _commonImageTypes,
    ),
  };

  static Future<ValidatedUploadImage> validate(
    String path,
    UploadImagePurpose purpose,
  ) async {
    if (path.trim().isEmpty) {
      throw const UploadImageValidationException('图片路径为空');
    }

    try {
      final file = File(path);
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file) {
        throw const UploadImageValidationException('图片文件不存在');
      }
      if (stat.size <= 0) {
        throw const UploadImageValidationException('图片文件为空');
      }

      final policy = policies[purpose]!;
      if (stat.size > policy.maxBytes) {
        final maxMiB = policy.maxBytes ~/ _mib;
        throw UploadImageValidationException('图片不能超过 $maxMiB MB');
      }

      final headerLength = stat.size < 64 ? stat.size : 64;
      final fileHandle = await file.open();
      late final List<int> headerBytes;
      try {
        headerBytes = await fileHandle.read(headerLength);
      } finally {
        await fileHandle.close();
      }
      final mimeType = lookupMimeType('', headerBytes: headerBytes);
      if (mimeType == null || !policy.allowedMimeTypes.contains(mimeType)) {
        final supported = purpose == UploadImagePurpose.avatar
            ? 'JPEG、PNG 或 WebP'
            : 'JPEG、PNG、GIF 或 WebP';
        throw UploadImageValidationException('仅支持 $supported 图片');
      }

      return ValidatedUploadImage(
        path: path,
        length: stat.size,
        mimeType: mimeType,
      );
    } on FileSystemException {
      throw const UploadImageValidationException('无法读取图片文件');
    }
  }
}
