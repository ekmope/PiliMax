import 'dart:io';

import 'package:PiliMax/utils/upload_image_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload-image-test-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('detects image type from header instead of extension', () async {
    final file = File('${tempDir.path}/image.bin');
    await file.writeAsBytes(_pngHeader);

    final image = await UploadImageValidator.validate(
      file.path,
      UploadImagePurpose.dynamicImage,
    );

    expect(image.mimeType, 'image/png');
    expect(image.mimeSubtype, 'png');
  });

  test('rejects a fake image with a trusted extension', () async {
    final file = File('${tempDir.path}/not-an-image.png');
    await file.writeAsString('plain text');

    await expectLater(
      UploadImageValidator.validate(
        file.path,
        UploadImagePurpose.dynamicImage,
      ),
      throwsA(isA<UploadImageValidationException>()),
    );
  });

  test('applies purpose-specific MIME policies', () async {
    final file = File('${tempDir.path}/animated.bin');
    await file.writeAsBytes(_gifHeader);

    final dynamicImage = await UploadImageValidator.validate(
      file.path,
      UploadImagePurpose.dynamicImage,
    );
    expect(dynamicImage.mimeType, 'image/gif');

    await expectLater(
      UploadImageValidator.validate(file.path, UploadImagePurpose.avatar),
      throwsA(isA<UploadImageValidationException>()),
    );
  });

  test('rejects files larger than the purpose limit', () async {
    final file = File('${tempDir.path}/large.png');
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.truncate(5 * 1024 * 1024 + 1);
    } finally {
      await handle.close();
    }

    await expectLater(
      UploadImageValidator.validate(file.path, UploadImagePurpose.avatar),
      throwsA(
        isA<UploadImageValidationException>().having(
          (error) => error.message,
          'message',
          contains('5 MB'),
        ),
      ),
    );
  });

  test('rejects missing and empty files', () async {
    final empty = File('${tempDir.path}/empty.png');
    await empty.create();

    await expectLater(
      UploadImageValidator.validate(
        '${tempDir.path}/missing.png',
        UploadImagePurpose.favoriteCover,
      ),
      throwsA(isA<UploadImageValidationException>()),
    );
    await expectLater(
      UploadImageValidator.validate(
        empty.path,
        UploadImagePurpose.favoriteCover,
      ),
      throwsA(isA<UploadImageValidationException>()),
    );
  });
}

const _pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _gifHeader = <int>[71, 73, 70, 56, 57, 97];
