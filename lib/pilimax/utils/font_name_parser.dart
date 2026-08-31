import 'dart:io';
import 'dart:typed_data';

final class FontFileMetadata {
  const FontFileMetadata({required this.displayName});

  final String? displayName;
}

/// Validates a TTF, OTF, or TTC file and reads its first font's display name.
abstract final class FontNameParser {
  static const int _tagTtcf = 0x74746366;
  static const int _tagCmap = 0x636D6170;
  static const int _tagHead = 0x68656164;
  static const int _tagMaxp = 0x6D617870;
  static const Set<int> _sfntTags = {
    0x00010000,
    0x4F54544F,
    0x74727565,
    0x74797031,
  };
  static const int _tagName = 0x6E616D65;
  static const Set<int> _glyphTableTags = {
    0x676C7966,
    0x43464620,
    0x43464632,
    0x43424454,
    0x45424454,
    0x73626978,
  };
  static const int _nameIdFullName = 4;
  static const int _nameIdTypographicFamily = 16;
  static const int _nameIdFamily = 1;
  static const int _maxNameLength = 64;

  static Future<FontFileMetadata?> inspect(String filePath) async {
    RandomAccessFile? file;
    try {
      final source = File(filePath);
      final fileLength = await source.length();
      file = await source.open();

      var headerOffset = 0;
      var header = await _readAt(file, 0, 12);
      if (header == null) return null;
      if (header.getUint32(0) == _tagTtcf) {
        final fontCount = header.getUint32(8);
        if (fontCount == 0 ||
            fontCount > 1024 ||
            12 + fontCount * 4 > fileLength) {
          return null;
        }
        final firstFontOffset = await _readAt(file, 12, 4);
        if (firstFontOffset == null) return null;
        headerOffset = firstFontOffset.getUint32(0);
        if (headerOffset < 12 + fontCount * 4) return null;
        header = await _readAt(file, headerOffset, 12);
        if (header == null) return null;
      }
      if (!_sfntTags.contains(header.getUint32(0))) return null;

      final tableCount = header.getUint16(4);
      if (tableCount == 0 || tableCount > 512) return null;
      if (headerOffset + 12 + tableCount * 16 > fileLength) return null;
      final directory = await _readAt(
        file,
        headerOffset + 12,
        tableCount * 16,
      );
      if (directory == null) return null;

      var nameOffset = -1;
      var nameLength = 0;
      final validTableTags = <int>{};
      for (var index = 0; index < tableCount; index++) {
        final recordOffset = index * 16;
        final tag = directory.getUint32(recordOffset);
        final offset = directory.getUint32(recordOffset + 8);
        final length = directory.getUint32(recordOffset + 12);
        if (offset > fileLength || length > fileLength - offset) {
          return null;
        }
        if (length == 0) continue;
        validTableTags.add(tag);
        if (tag == _tagName) {
          nameOffset = offset;
          nameLength = length;
        }
      }
      if (!validTableTags.containsAll({
            _tagCmap,
            _tagHead,
            _tagMaxp,
            _tagName,
          }) ||
          !validTableTags.any(_glyphTableTags.contains)) {
        return null;
      }
      if (nameLength < 6 ||
          nameLength > 1 << 22 ||
          nameOffset + nameLength > fileLength) {
        return null;
      }

      final table = await _readAt(file, nameOffset, nameLength);
      return table == null
          ? null
          : FontFileMetadata(displayName: _pickName(table));
    } catch (_) {
      return null;
    } finally {
      try {
        await file?.close();
      } catch (_) {}
    }
  }

  static Future<ByteData?> _readAt(
    RandomAccessFile file,
    int offset,
    int length,
  ) async {
    if (offset < 0 || length <= 0) return null;
    await file.setPosition(offset);
    final bytes = await file.read(length);
    return bytes.length == length ? ByteData.sublistView(bytes) : null;
  }

  static String? _pickName(ByteData table) {
    final recordCount = table.getUint16(2);
    final storageOffset = table.getUint16(4);
    String? best;
    var bestScore = -1;

    for (var index = 0; index < recordCount; index++) {
      final recordOffset = 6 + index * 12;
      if (recordOffset + 12 > table.lengthInBytes) break;
      final nameId = table.getUint16(recordOffset + 6);
      if (nameId != _nameIdFullName &&
          nameId != _nameIdTypographicFamily &&
          nameId != _nameIdFamily) {
        continue;
      }

      final platformId = table.getUint16(recordOffset);
      final score = _score(
        platformId,
        table.getUint16(recordOffset + 4),
        nameId,
      );
      if (score <= bestScore) continue;

      final length = table.getUint16(recordOffset + 8);
      final offset = storageOffset + table.getUint16(recordOffset + 10);
      if (length == 0 || offset + length > table.lengthInBytes) continue;
      final value = _decode(
        platformId,
        Uint8List.sublistView(table, offset, offset + length),
      );
      if (value == null) continue;
      best = value;
      bestScore = score;
    }
    return best;
  }

  static int _score(int platformId, int languageId, int nameId) {
    final nameScore = switch (nameId) {
      _nameIdFullName => 300,
      _nameIdTypographicFamily => 200,
      _ => 100,
    };
    final languageScore = switch (platformId) {
      3 => switch (languageId) {
        0x0804 => 50,
        0x0404 || 0x0C04 || 0x1404 => 40,
        0x0409 => 30,
        _ => 10,
      },
      0 => 20,
      1 => switch (languageId) {
        33 => 45,
        19 => 35,
        0 => 25,
        _ => 5,
      },
      _ => 0,
    };
    return nameScore + languageScore;
  }

  static String? _decode(int platformId, Uint8List bytes) {
    final String raw;
    if (platformId == 1) {
      if (bytes.any((byte) => byte >= 0x80)) return null;
      raw = String.fromCharCodes(bytes);
    } else {
      if (bytes.length < 2) return null;
      final units = Uint16List(bytes.length >> 1);
      for (var index = 0; index < units.length; index++) {
        units[index] = (bytes[index * 2] << 8) | bytes[index * 2 + 1];
      }
      raw = String.fromCharCodes(units);
    }
    return _sanitize(raw);
  }

  static String? _sanitize(String value) {
    final result = StringBuffer();
    var length = 0;
    for (final rune in value.runes) {
      if (rune == 0x2F || rune < 0x20 || rune == 0x7F) continue;
      result.writeCharCode(rune);
      if (++length >= _maxNameLength) break;
    }
    final sanitized = result.toString().trim();
    return sanitized.isEmpty ? null : sanitized;
  }
}
