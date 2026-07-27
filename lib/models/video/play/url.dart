import 'dart:math' show max, min;

import 'package:PiliMax/models/common/video/audio_quality.dart';
import 'package:PiliMax/models/common/video/video_quality.dart';
import 'package:PiliMax/models_new/sponsor_block/segment_item.dart';
import 'package:PiliMax/utils/extension/iterable_ext.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class PlayUrlModel {
  PlayUrlModel({
    this.from,
    this.result,
    this.message,
    this.quality,
    this.format,
    this.timeLength,
    this.acceptFormat,
    this.acceptDesc,
    this.acceptQuality,
    this.videoCodecid,
    this.seekParam,
    this.seekType,
    this.dash,
    this.supportFormats,
    this._lastPlayTime = 0,
    this.lastPlayCid,
  });

  String? from;
  String? result;
  String? message;
  int? quality;
  String? format;
  int? timeLength;
  String? acceptFormat;
  List<dynamic>? acceptDesc;
  List<int>? acceptQuality;
  int? videoCodecid;
  String? seekParam;
  String? seekType;
  Dash? dash;
  List<Durl>? durl;
  List<FormatItem>? supportFormats;
  Volume? volume;

  Set<int> get playableQualityIds => {
    ...?dash?.video?.where(_hasUsableUrl).map((item) => item.quality.code),
  };

  static bool _hasUsableUrl(BaseItem item) =>
      item.playUrls.any((url) => url.trim().isNotEmpty);

  String? playableCapabilityLabel(int? qualityCode) {
    if (qualityCode == null) return null;

    VideoQuality? quality;
    double? highestFrameRate;
    for (final item in dash?.video ?? const <VideoItem>[]) {
      if (item.quality.code != qualityCode || !_hasUsableUrl(item)) continue;
      quality = item.quality;
      final frameRate = _parseFrameRate(item.frameRate);
      if (frameRate != null &&
          (highestFrameRate == null || frameRate > highestFrameRate)) {
        highestFrameRate = frameRate;
      }
    }
    if (quality == null) return null;

    final qualityLabel = _capabilityQualityLabel(quality);
    return highestFrameRate == null
        ? qualityLabel
        : '$qualityLabel/${_formatFrameRate(highestFrameRate)}帧';
  }

  static double? _parseFrameRate(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;

    double? frameRate;
    final parts = value.split('/');
    if (parts.length == 1) {
      frameRate = double.tryParse(value);
    } else if (parts.length == 2) {
      final numerator = double.tryParse(parts[0].trim());
      final denominator = double.tryParse(parts[1].trim());
      if (numerator != null && denominator != null && denominator > 0) {
        frameRate = numerator / denominator;
      }
    }
    if (frameRate == null ||
        !frameRate.isFinite ||
        frameRate < 1 ||
        frameRate > 240) {
      return null;
    }
    return frameRate;
  }

  static String _formatFrameRate(double frameRate) {
    final rounded = frameRate.round();
    if ((frameRate - rounded).abs() < 0.1) return rounded.toString();
    return frameRate
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _capabilityQualityLabel(VideoQuality quality) =>
      switch (quality) {
        VideoQuality.hdrVivid => 'HDR Vivid',
        VideoQuality.super8k => '8K',
        VideoQuality.dolbyVision => '杜比视界',
        VideoQuality.hdr => 'HDR',
        VideoQuality.super4K => '4K',
        VideoQuality.high108060 => '1080P',
        VideoQuality.high1080plus => '1080P+',
        VideoQuality.high1080 => '1080P',
        VideoQuality.high72060 => '720P',
        VideoQuality.high720 => '720P',
        VideoQuality.clear480 => '480P',
        VideoQuality.fluent360 => '360P',
        VideoQuality.speed240 => '240P',
      };

  bool isPreviewQuality(int? quality) =>
      quality != null &&
      dash?.video?.any(
            (item) =>
                item.quality.code == quality &&
                item.isPreview &&
                _hasUsableUrl(item),
          ) ==
          true;

  late int _lastPlayTime;
  int get lastPlayTime => _lastPlayTime;
  set lastPlayTime(int? value) {
    if (value != null && value > 0) {
      _lastPlayTime = value;
    } else {
      _lastPlayTime = 0;
    }
  }

  int? lastPlayCid;
  String? curLanguage;
  Language? language;
  List<SegmentItemModel>? clipInfoList;

  PlayUrlModel.fromJson(Map<String, dynamic> json) {
    from = json['from'];
    result = json['result'];
    message = json['message'];
    quality = json['quality'];
    format = json['format'];
    timeLength = json['timelength'];
    acceptFormat = json['accept_format'];
    acceptDesc = json['accept_description'];
    acceptQuality = (json['accept_quality'] as List?)
        ?.map<int>((e) => e as int)
        .toList();
    videoCodecid = json['video_codecid'];
    seekParam = json['seek_param'];
    seekType = json['seek_type'];
    dash = json['dash'] != null ? Dash.fromJson(json['dash']) : null;
    durl = (json['durl'] as List?)?.map<Durl>((e) => Durl.fromJson(e)).toList();
    supportFormats = (json['support_formats'] as List?)
        ?.map<FormatItem>((e) => FormatItem.fromJson(e))
        .toList();
    volume = json['volume'] == null ? null : Volume.fromJson(json['volume']);
    lastPlayTime = json['last_play_time'];
    lastPlayCid = json['last_play_cid'];
    curLanguage = json['cur_language'];
    language = json['language'] == null
        ? null
        : Language.fromJson(json['language']);
    // debug
    // final clipInfoList = [
    //   {
    //     "start": 0,
    //     "end": 150,
    //     "clipType": "CLIP_TYPE_OP",
    //   },
    //   {
    //     "start": timeLength! ~/ 1000 - 150,
    //     "end": timeLength! ~/ 1000,
    //     "clipType": "CLIP_TYPE_ED",
    //   },
    // ];
    try {
      final List? clipInfoList = json['clip_info_list'];
      if (clipInfoList != null && clipInfoList.isNotEmpty) {
        this.clipInfoList = clipInfoList
            .map((e) => SegmentItemModel.fromPgcJson(e, timeLength))
            .toList();
      }
    } catch (_) {
      if (kDebugMode) rethrow;
    }
  }
}

class Language {
  Language({
    this.support,
    this.items,
  });

  bool? support;
  List<LanguageItem>? items;

  Language.fromJson(Map<String, dynamic> json) {
    support = json['support'];
    items =
        (json['items'] as List?)?.map((e) => LanguageItem.fromJson(e)).toList()
          ?..sort((a, b) {
            final aHasZh = a.lang?.contains('zh') ?? false;
            final bHasZh = b.lang?.contains('zh') ?? false;
            if (aHasZh != bHasZh) return aHasZh ? -1 : 1;
            if (a.isAi != b.isAi) return a.isAi ? 1 : -1;
            return 0;
          });
  }
}

class LanguageItem {
  LanguageItem({
    this.lang,
    this.title,
    this.subtitleLang,
  });

  String? lang;
  String? title;
  String? subtitleLang;
  bool isAi = false;

  LanguageItem.fromJson(Map<String, dynamic> json) {
    lang = json['lang'];
    isAi = json['production_type'] == 2;
    title = '${json['title']}${isAi ? '（AI）' : ''}';
    subtitleLang = json['subtitle_lang'];
  }
}

class Dash {
  Dash({
    this.duration,
    this.minBufferTime,
    this.video,
    this.audio,
  });

  int? duration;
  double? minBufferTime;
  List<VideoItem>? video;
  List<AudioItem>? audio;

  Dash.fromJson(Map<String, dynamic> json) {
    duration = json['duration'];
    minBufferTime = json['minBufferTime'];
    video = (json['video'] as List?)
        ?.map<VideoItem>((e) => VideoItem.fromJson(e))
        .toList();
    final audio = [
      if (json['flac']?['audio'] case Map<String, dynamic> flac)
        AudioItem.fromJson(flac),
      if (json['dolby']?['audio'] case List list)
        ...list.map((e) => AudioItem.fromJson(e)),
      if (json['audio'] case List list)
        ...list.map((e) => AudioItem.fromJson(e)),
    ];
    this.audio = audio.isEmpty ? null : audio;
  }
}

class Durl {
  int? order;
  int? length;
  int? size;
  String? ahead;
  String? vhead;
  String? url;
  List<String>? backupUrl;

  Durl({
    this.order,
    this.length,
    this.size,
    this.ahead,
    this.vhead,
    this.url,
    this.backupUrl,
  });

  factory Durl.fromJson(Map<String, dynamic> json) {
    return Durl(
      order: json['order'],
      length: json['length'],
      size: json['size'],
      ahead: json['ahead'],
      vhead: json['vhead'],
      url: json['url'],
      backupUrl: (json['backup_url'] as List?)?.fromCast<String>(),
    );
  }

  Iterable<String> get playUrls sync* {
    if (url?.isNotEmpty == true) yield url!;
    if (backupUrl?.isNotEmpty == true) yield* backupUrl!;
  }
}

abstract class BaseItem {
  int? id;
  String? baseUrl;
  List<String>? backupUrl;
  int? bandWidth;
  String? mimeType;
  String? codecs;
  int? width;
  int? height;
  String? frameRate;
  String? sar;
  int? startWithSap;
  Map? segmentBase;
  int? codecid;

  BaseItem({
    this.id,
    this.baseUrl,
    this.backupUrl,
    this.bandWidth,
    this.mimeType,
    this.codecs,
    this.width,
    this.height,
    this.frameRate,
    this.sar,
    this.startWithSap,
    this.segmentBase,
    this.codecid,
  });

  BaseItem.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    baseUrl = json['baseUrl'] ?? json['base_url'];
    backupUrl = ((json['backupUrl'] ?? json['backup_url']) as List?)
        ?.fromCast<String>();
    bandWidth = json['bandWidth'] ?? json['bandwidth'];
    mimeType = json['mime_type'];
    codecs = json['codecs'];
    width = json['width'];
    height = json['height'];
    frameRate = json['frameRate'] ?? json['frame_rate'];
    sar = json['sar'];
    startWithSap = json['startWithSap'] ?? json['start_with_sap'];
    segmentBase = json['segmentBase'] ?? json['segment_base'];
    codecid = json['codecid'];
  }

  Iterable<String> get playUrls sync* {
    if (baseUrl?.isNotEmpty == true) yield baseUrl!;
    if (backupUrl?.isNotEmpty == true) yield* backupUrl!;
  }
}

class VideoItem extends BaseItem {
  late VideoQuality quality;
  final bool isPreview;

  VideoItem({
    super.id,
    super.baseUrl,
    super.backupUrl,
    super.bandWidth,
    super.mimeType,
    super.codecs,
    super.width,
    super.height,
    super.frameRate,
    super.sar,
    super.startWithSap,
    super.segmentBase,
    super.codecid,
    required this.quality,
    this.isPreview = false,
  });

  VideoItem.fromJson(Map<String, dynamic> json)
    : isPreview = false,
      super.fromJson(json) {
    quality = VideoQuality.fromCode(json['id']);
  }
}

class AudioItem extends BaseItem {
  late String quality;

  AudioItem();

  AudioItem.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    quality = AudioQuality.fromCode(json['id']).desc;
  }
}

class FormatItem {
  FormatItem({
    this.quality,
    this.format,
    this.newDesc,
    this.displayDesc,
    this.codecs,
  });

  int? quality;
  String? format;
  String? newDesc;
  String? displayDesc;
  List<String>? codecs;

  FormatItem.fromJson(Map<String, dynamic> json) {
    quality = json['quality'];
    format = json['format'];
    newDesc = json['new_description'];
    displayDesc = json['display_desc'];
    codecs = (json['codecs'] as List?)?.fromCast<String>();
  }
}

class Volume {
  Volume({
    required this.measuredI,
    required this.measuredLra,
    required this.measuredTp,
    required this.measuredThreshold,
    required this.targetOffset,
    required this.targetI,
    required this.targetTp,
    // required this.multiSceneArgs,
  });

  final num measuredI;
  final num measuredLra;
  final num measuredTp;
  final num measuredThreshold;
  final num targetOffset;
  final num targetI;
  final num targetTp;

  // final MultiSceneArgs? multiSceneArgs;

  // FFmpeg loudnorm 滤镜的标准有效范围（https://ffmpeg.org/ffmpeg-filters.html#loudnorm）
  static const double minTpValue = -9.0;
  static const double maxTpValue = 0.0;

  factory Volume.fromJson(Map<String, dynamic> json) {
    return Volume(
      measuredI: json["measured_i"] ?? 0,
      measuredLra: json["measured_lra"] ?? 0,
      measuredTp: json["measured_tp"] ?? 0,
      measuredThreshold: json["measured_threshold"] ?? 0,
      targetOffset: json["target_offset"] ?? 0,
      targetI: json["target_i"] ?? 0,
      targetTp: json["target_tp"] ?? 0,
      // multiSceneArgs: json["multi_scene_args"] == null ? null : MultiSceneArgs.fromJson(json["multi_scene_args"]),
    );
  }

  String format(Map<String, num> config) {
    final lra = max(config['lra'] ?? 11, measuredLra);
    num i = config['i'] ?? targetI;
    final tp = min(
      config['tp'] ?? targetTp,
      measuredTp,
    ).clamp(minTpValue, maxTpValue);
    final offset = config['offset'] ?? targetOffset;
    num measuredI = this.measuredI;
    if (measuredI > 0) {
      i -= measuredI;
      measuredI = 0;
    }
    num measuredThreshold = this.measuredThreshold;
    if (measuredThreshold > 0) {
      measuredThreshold = 0;
    }

    return 'LRA=$lra:I=$i:TP=$tp:offset=$offset:linear=true:measured_I=$measuredI:measured_LRA=$measuredLra:measured_TP=$measuredTp:measured_thresh=$measuredThreshold';
  }

  bool get isNotEmpty =>
      measuredI != 0 ||
      measuredLra != 0 ||
      measuredTp != 0 ||
      measuredThreshold != 0;
}
