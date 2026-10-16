final class AudioQuality {
  final int code;
  final String desc;

  const AudioQuality(this.code, this.desc);

  @override
  String toString() => 'code: $code, desc: $desc';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioQuality && code == other.code;

  @override
  int get hashCode => code.hashCode;

  static const u_100010 = AudioQuality(100010, '100010');
  static const u_100009 = AudioQuality(100009, '100009');
  static const u_100008 = AudioQuality(100008, '100008');
  static const hiRes = AudioQuality(30251, 'Hi-Res无损');
  static const dolby_30250 = AudioQuality(30250, '杜比全景声');
  static const dolby_30255 = AudioQuality(30255, '杜比全景声');
  static const k192 = AudioQuality(30280, '192K');
  static const k132 = AudioQuality(30232, '132K');
  static const k64 = AudioQuality(30216, '64K');

  static const List<AudioQuality> values = [
    u_100010,
    u_100009,
    u_100008,
    hiRes,
    dolby_30250,
    dolby_30255,
    k192,
    k132,
    k64,
  ];

  static final _codeMap = {for (final quality in values) quality.code: quality};

  factory AudioQuality.fromId(int code) => AudioQuality(code, code.toString());

  factory AudioQuality.fromCode(int code) =>
      _codeMap[code] ?? AudioQuality.fromId(code);
}
