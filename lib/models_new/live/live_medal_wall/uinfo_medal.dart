class UinfoMedal {
  String? name;
  int? level;
  int? id;
  int? ruid;
  String? v2MedalColorStart;
  String? v2MedalColorText;

  UinfoMedal({
    this.name,
    this.level,
    this.id,
    this.ruid,
    this.v2MedalColorStart,
    this.v2MedalColorText,
  });

  factory UinfoMedal.fromJson(Map<String, dynamic> json) => UinfoMedal(
    name: json['name']?.toString(),
    level: _asInt(json['level']),
    id: _asInt(json['id']),
    ruid: _asInt(json['ruid']),
    v2MedalColorStart: json['v2_medal_color_start']?.toString(),
    v2MedalColorText: json['v2_medal_color_text']?.toString(),
  );

  static UinfoMedal? lightMedal(Map<String, dynamic>? json) {
    if (json == null || json['is_light'] != 1) return null;
    return .fromJson(json);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'level': level,
    'id': id,
    'ruid': ruid,
    'v2_medal_color_start': v2MedalColorStart,
    'v2_medal_color_text': v2MedalColorText,
  };

  static int? _asInt(Object? value) => switch (value) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UinfoMedal &&
          name == other.name &&
          level == other.level &&
          id == other.id &&
          ruid == other.ruid &&
          v2MedalColorStart == other.v2MedalColorStart &&
          v2MedalColorText == other.v2MedalColorText;

  @override
  int get hashCode => Object.hash(
    name,
    level,
    id,
    ruid,
    v2MedalColorStart,
    v2MedalColorText,
  );
}
