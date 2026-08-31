import 'package:PiliMax/models_new/live/live_fans_medal/item.dart';

class FansMedalPanelData {
  FansMedalPanelData({
    this.specialList,
    this.list,
    this.totalNumber,
    this.hasMore,
    this.nextPage,
  });

  List<FansMedalItem>? specialList;
  List<FansMedalItem>? list;
  int? totalNumber;
  bool? hasMore;
  int? nextPage;

  factory FansMedalPanelData.fromJson(Map<String, dynamic> json) {
    final pageInfo = _asJsonMap(json['page_info']);
    return FansMedalPanelData(
      specialList: _parseItems(json['special_list']),
      list: _parseItems(json['list']),
      totalNumber: _asInt(json['total_number']),
      hasMore: _asBool(pageInfo?['has_more'] ?? json['has_more']),
      nextPage: _asInt(pageInfo?['next_page'] ?? json['next_page']),
    );
  }
}

List<FansMedalItem>? _parseItems(Object? value) {
  if (value is! List) return null;
  return [
    for (final item in value)
      if (_asJsonMap(item) case final json?) FansMedalItem.fromJson(json),
  ];
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

bool? _asBool(Object? value) => switch (value) {
  bool value => value,
  num value => value != 0,
  String value when value == '1' || value.toLowerCase() == 'true' => true,
  String value when value == '0' || value.toLowerCase() == 'false' => false,
  _ => null,
};
