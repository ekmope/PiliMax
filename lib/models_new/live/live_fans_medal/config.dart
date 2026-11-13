class FansMedalConfig {
  const FansMedalConfig({this.closeSpaceMedal, this.onlyShowWearing});

  static const closeSpaceMedalKey = 'close_space_medal';
  static const onlyShowWearingKey = 'only_show_wearing';

  // Missing server settings remain unknown rather than being saved as false.
  final bool? closeSpaceMedal;
  final bool? onlyShowWearing;

  factory FansMedalConfig.fromJson(Map<String, dynamic> json) {
    final config = json['configs'];
    bool? status(String key) {
      if (config is! Map) return null;
      final item = config[key];
      if (item is! Map) return null;
      return switch (item['status']) {
        true || 1 || '1' => true,
        false || 0 || '0' => false,
        _ => null,
      };
    }

    return FansMedalConfig(
      closeSpaceMedal: status(closeSpaceMedalKey),
      onlyShowWearing: status(onlyShowWearingKey),
    );
  }
}
