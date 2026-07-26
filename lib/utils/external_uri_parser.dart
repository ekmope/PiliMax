abstract final class ExternalUriParser {
  static final BigInt _maxSignedInt64 = BigInt.parse('9223372036854775807');
  static final double _maxSignedInt64AsDouble = _maxSignedInt64.toDouble();

  static int? positiveInt(String? value) {
    final parsed = nonNegativeInt(value);
    return parsed == null || parsed == 0 ? null : parsed;
  }

  static int? nonNegativeInt(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final parsed = BigInt.tryParse(value);
    if (parsed == null || parsed < BigInt.zero || parsed > _maxSignedInt64) {
      return null;
    }
    return parsed.toInt();
  }

  static int? nonNegativeSecondsToMilliseconds(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final seconds = double.tryParse(value);
    if (seconds == null || !seconds.isFinite || seconds < 0) {
      return null;
    }
    final milliseconds = seconds * Duration.millisecondsPerSecond;
    if (!milliseconds.isFinite || milliseconds >= _maxSignedInt64AsDouble) {
      return null;
    }
    return milliseconds.toInt();
  }

  static int? positivePathSegment(List<String> segments, int index) {
    if (index < 0 || index >= segments.length) {
      return null;
    }
    return positiveInt(segments[index]);
  }
}
