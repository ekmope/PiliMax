import 'package:PiliMax/models_new/live/live_fans_medal/medal.dart';
import 'package:PiliMax/models_new/live/live_medal_wall/uinfo_medal.dart';

class FansMedalItem {
  FansMedalItem({
    this.medal,
    this.anchorName,
    this.anchorAvatar,
    this.superscript,
    this.uinfoMedal,
  });

  FansMedalDetail? medal;
  String? anchorName;
  String? anchorAvatar;
  String? superscript;
  UinfoMedal? uinfoMedal;

  factory FansMedalItem.fromJson(Map<String, dynamic> json) {
    final medal = _asJsonMap(json['medal']);
    final anchorInfo = _asJsonMap(json['anchor_info']);
    final superscript = _asJsonMap(json['superscript']);
    final uinfoMedal = _asJsonMap(json['uinfo_medal']);
    return FansMedalItem(
      medal: medal == null ? null : FansMedalDetail.fromJson(medal),
      anchorName: _asString(anchorInfo?['nick_name']),
      anchorAvatar: _asString(anchorInfo?['avatar']),
      superscript: _asString(superscript?['content']),
      uinfoMedal: uinfoMedal == null
          ? null
          : UinfoMedal(
              name: _asString(uinfoMedal['name']),
              level: _asInt(uinfoMedal['level']),
              id: _asInt(uinfoMedal['id']),
              ruid: _asInt(uinfoMedal['ruid']),
              v2MedalColorStart: _asString(
                uinfoMedal['v2_medal_color_start'],
              ),
              v2MedalColorText: _asString(uinfoMedal['v2_medal_color_text']),
            ),
    );
  }
}

Map<String, dynamic>? _asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is! Map) return null;
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

int? _asInt(Object? value) => switch (value) {
  int value => value,
  num value => value.toInt(),
  bool value => value ? 1 : 0,
  String value => int.tryParse(value),
  _ => null,
};

String? _asString(Object? value) => switch (value) {
  String value => value,
  num value => value.toString(),
  bool value => value.toString(),
  _ => null,
};
