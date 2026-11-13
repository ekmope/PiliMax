import 'package:PiliMax/models_new/live/live_medal_wall/uinfo_medal.dart';

/// The medal the server actually displays in a room can differ from the one
/// selected in the user's medal panel (some rooms disallow other anchors).
class UserMedalInfo {
  const UserMedalInfo({
    this.current,
    this.wearing,
    this.roomMedal,
    this.hasMedal = false,
  });

  final UinfoMedal? current;
  final UinfoMedal? wearing;
  final UinfoMedal? roomMedal;
  final bool hasMedal;

  factory UserMedalInfo.fromJson(Map<String, dynamic> json) => UserMedalInfo(
    current: _medal(json['curr_show']),
    wearing: _medal(json['curr_weared_v2']),
    roomMedal: _medal(json['lookup_v2']),
    hasMedal: json['up_medal'] != null,
  );

  static UinfoMedal? _medal(Object? value) => value is Map
      ? UinfoMedal.fromJson({
          for (final entry in value.entries) entry.key.toString(): entry.value,
        })
      : null;
}
