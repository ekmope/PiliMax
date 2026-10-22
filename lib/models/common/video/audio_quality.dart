part of 'base_quality.dart';

class AudioQuality extends BaseQuality {
  /// 音质优先级，数值越大音质越高。未知音质为 0。
  final int rank;

  const AudioQuality(super.code, super.desc, {this.rank = 0});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioQuality && code == other.code;

  @override
  int get hashCode => code.hashCode;

  static const u_100010 = AudioQuality(100010, '100010');
  static const u_100009 = AudioQuality(100009, '100009');
  static const u_100008 = AudioQuality(100008, '100008');
  static const hiRes = AudioQuality(30251, 'Hi-Res无损', rank: 60);
  static const dolby_30250 = AudioQuality(30250, '杜比全景声', rank: 50);
  static const dolby_30255 = AudioQuality(30255, '杜比全景声', rank: 50);
  static const k192 = AudioQuality(30280, '192K', rank: 40);
  static const k132 = AudioQuality(30232, '132K', rank: 30);
  static const k64 = AudioQuality(30216, '64K', rank: 20);

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

  AudioQuality.fromId(super.code) : rank = 0, super.fromId();

  factory AudioQuality.fromCode(int code) =>
      _codeMap[code] ?? AudioQuality.fromId(code);
}
