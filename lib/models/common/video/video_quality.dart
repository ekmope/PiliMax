import 'package:PiliMax/models/video/play/url.dart' show FormatItem;

final class VideoQuality {
  final int code;
  final String desc;
  final String shortDesc;

  const VideoQuality(this.code, this.desc, this.shortDesc);

  @override
  String toString() => 'code: $code, desc: $desc, shortDesc: $shortDesc';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VideoQuality && code == other.code;

  @override
  int get hashCode => code.hashCode;

  static const hdrVivid = VideoQuality(129, 'HDR Vivid', 'HDR Vivid');
  static const super8k = VideoQuality(127, '8K 超高清', '8K');
  static const dolbyVision = VideoQuality(126, '杜比视界', '杜比');
  static const hdr = VideoQuality(125, 'HDR 真彩', 'HDR');
  static const super4K = VideoQuality(120, '4K 超高清', '4K');
  static const high108060 = VideoQuality(116, '1080P 60帧', '1080P60');
  static const high1080plus = VideoQuality(112, '1080P 高码率', '1080P+');
  static const superResolution = VideoQuality(100, '智能修复', '智能修复');
  static const high1080 = VideoQuality(80, '1080P 高清', '1080P');
  static const high72060 = VideoQuality(74, '720P 60帧', '720P60');
  static const high720 = VideoQuality(64, '720P 准高清', '720P');
  static const clear480 = VideoQuality(32, '480P 标清', '480P');
  static const fluent360 = VideoQuality(16, '360P 流畅', '360P');
  static const speed240 = VideoQuality(6, '240P 极速', '240P');

  static const List<VideoQuality> values = [
    hdrVivid,
    super8k,
    dolbyVision,
    hdr,
    super4K,
    high108060,
    high1080plus,
    superResolution,
    high1080,
    high72060,
    high720,
    clear480,
    fluent360,
    speed240,
  ];

  static final _codeMap = {for (final quality in values) quality.code: quality};

  factory VideoQuality.fromId(int id, String idStr) =>
      VideoQuality(id, idStr, idStr);

  factory VideoQuality.fromCode(int code) =>
      _codeMap[code] ?? VideoQuality.fromId(code, code.toString());

  factory VideoQuality.fromFormat(int code, List<FormatItem>? formats) {
    if (formats != null) {
      for (final format in formats) {
        if (format.quality == code) {
          final desc = format.newDesc ?? format.displayDesc;
          if (desc != null && desc.isNotEmpty) {
            return VideoQuality(
              code,
              desc,
              format.displayDesc?.isNotEmpty == true
                  ? format.displayDesc!
                  : desc,
            );
          }
        }
      }
    }
    return VideoQuality.fromCode(code);
  }
}
