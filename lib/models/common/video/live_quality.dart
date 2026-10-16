final class LiveQuality {
  final int code;
  final String desc;

  const LiveQuality(this.code, this.desc);

  @override
  String toString() => 'code: $code, desc: $desc';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LiveQuality && code == other.code;

  @override
  int get hashCode => code.hashCode;

  static const dolby = LiveQuality(30000, '杜比');
  static const origin4K = LiveQuality(25000, '4K 原画');
  static const super4K = LiveQuality(20000, '4K');
  static const super2K = LiveQuality(15000, '2K');
  static const origin = LiveQuality(10000, '原画');
  static const bluRay = LiveQuality(400, '蓝光');
  static const superHD = LiveQuality(250, '超清');
  static const smooth = LiveQuality(150, '高清');
  static const flunt = LiveQuality(80, '流畅');

  static const List<LiveQuality> values = [
    dolby,
    origin4K,
    super4K,
    super2K,
    origin,
    bluRay,
    superHD,
    smooth,
    flunt,
  ];

  static final _codeMap = {for (final quality in values) quality.code: quality};

  factory LiveQuality.fromId(int code) => LiveQuality(code, code.toString());

  factory LiveQuality.fromCode(int code) =>
      _codeMap[code] ?? LiveQuality.fromId(code);

  factory LiveQuality.fromJson(Map<String, dynamic> json) {
    final code = (json['qn'] as num?)?.toInt() ?? -1;
    final desc = json['desc']?.toString() ?? code.toString();
    return LiveQuality(code, desc);
  }

  factory LiveQuality.fromFormat(int code, List<LiveQuality>? formats) {
    if (formats != null) {
      for (final quality in formats) {
        if (quality.code == code) return quality;
      }
    }
    return LiveQuality.fromCode(code);
  }
}
