import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:PiliMax/models/video/play/url.dart' show Volume;
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:media_kit/media_kit.dart' show Player;

enum AudioNormalization {
  disable('禁用'),
  // ref https://github.com/KRTirtho/spotube/commit/da10ab2e291d4ba4d3082b9a6ae535639fb8f1b7
  dynaudnorm('预设 dynaudnorm', 'dynaudnorm=g=5:f=250:r=0.9:p=0.5'),
  loudnorm('预设 loudnorm', 'loudnorm=I=-16:LRA=11:TP=-1.5'),
  custom('自定义参数'),
  ;

  final String title;
  final String param;
  const AudioNormalization(this.title, [this.param = '']);

  static String getTitleFromConfig(String config) => switch (config) {
    '0' => disable.title,
    '1' => dynaudnorm.title,
    '2' => loudnorm.title,
    _ => config,
  };

  static String getParamFromConfig(String config) => switch (config) {
    '0' => disable.param,
    '1' => dynaudnorm.param,
    '2' => loudnorm.param,
    _ => config,
  };

  static final loudnormRegExp = RegExp('loudnorm=([^,]+)');

  static String parse(Volume? volume, String param) {
    if (volume != null && volume.isNotEmpty) {
      return param.replaceFirstMapped(
        loudnormRegExp,
        (i) =>
            'loudnorm=${volume.format(
              Map.fromEntries(
                i.group(1)!.split(':').map((item) {
                  final parts = item.split('=');
                  return MapEntry(parts[0].toLowerCase(), num.parse(parts[1]));
                }),
              ),
            )}',
      );
    } else {
      return param.replaceFirst(
        loudnormRegExp,
        AudioNormalization.getParamFromConfig(Pref.fallbackNormalization),
      );
    }
  }
}

mixin AudioNormalizationMixin {
  late final _audioNormalization = Pref.audioNormalization;
  late final enableAudioNormalization =
      Platform.isAndroid && _audioNormalization != '0';
  late final _param = AudioNormalization.getParamFromConfig(
    _audioNormalization,
  );

  static const _kNormalizationKey = 'lavfi-complex';

  String? _alimiter;

  /// Applies mpv's cubic volume curve without allowing boosted PCM to clip.
  Future<void>? setVolumeCapped(Player? player, double volume) {
    assert(volume >= 0);
    if (player == null) return null;
    final boost = _boostAf(volume);
    if (boost == null) {
      if (_alimiter != null) {
        player.setProperty('af', '');
        _alimiter = null;
      }
      return player.setVolume(volume * 100);
    }
    if (_alimiter != boost) {
      player.setProperty('af', boost);
      _alimiter = boost;
    }
    return player.setVolume(100);
  }

  static String? _boostAf(double volume) {
    if (volume <= 1.0) return null;
    final db = (60 * math.log(volume) / math.ln10 * 2).round() / 2;
    final gain = math.pow(10, db / 20).toDouble();
    return 'alimiter=level_in=${gain.toStringAsFixed(3)}:limit=1:level=0';
  }

  Map<String, String>? audioFilterExtras(
    Volume? volume, {
    Map<String, String>? map,
  }) {
    if (!enableAudioNormalization) return map;
    var audioNormalization = AudioNormalization.parse(volume, _param);
    if (audioNormalization.isEmpty) return map;
    audioNormalization = '"[aid1] $audioNormalization [ao]"';
    if (map != null) {
      map[_kNormalizationKey] = audioNormalization;
      return map;
    }
    return {_kNormalizationKey: audioNormalization};
  }
}
