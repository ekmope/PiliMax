class FansMedalDetail {
  FansMedalDetail({
    this.medalId,
    this.targetId,
    this.medalName,
    this.level,
    this.intimacy,
    this.nextIntimacy,
    this.dayLimit,
    this.todayFeed,
    this.isLighted,
    this.wearingStatus,
  });

  int? medalId;
  int? targetId;
  String? medalName;
  int? level;
  int? intimacy;
  int? nextIntimacy;
  int? dayLimit;
  int? todayFeed;
  int? isLighted;
  int? wearingStatus;

  factory FansMedalDetail.fromJson(Map<String, dynamic> json) =>
      FansMedalDetail(
        medalId: _asInt(json['medal_id']),
        targetId: _asInt(json['target_id']),
        medalName: _asString(json['medal_name']),
        level: _asInt(json['level']),
        intimacy: _asInt(json['intimacy']),
        nextIntimacy: _asInt(json['next_intimacy']),
        dayLimit: _asInt(json['day_limit']),
        todayFeed: _asInt(json['today_feed']),
        isLighted: _asInt(json['is_lighted']),
        wearingStatus: _asInt(json['wearing_status']),
      );
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
