import 'package:PiliMax/models/user/danmaku_rule.dart';
import 'package:PiliMax/models/user/info.dart';

abstract final class AndroidMmkvStorageCodec {
  static Object? encodeUserInfoData(UserInfoData value) => {
    'isLogin': value.isLogin,
    'email_verified': value.emailVerified,
    'face': value.face,
    'level_info': _encodeLevelInfo(value.levelInfo),
    'mid': value.mid,
    'mobile_verified': value.mobileVerified,
    'money': value.money,
    'moral': value.moral,
    'official': value.official,
    'officialVerify': value.officialVerify,
    'pendant': value.pendant,
    'scores': value.scores,
    'uname': value.uname,
    'vipDueDate': value.vipDueDate,
    'vipStatus': value.vipStatus,
    'vipType': value.vipType,
    'vip_pay_type': value.vipPayType,
    'vip_theme_type': value.vipThemeType,
    'vip_label': value.vipLabel,
    'vip_avatar_subscript': value.vipAvatarSub,
    'vip_nickname_color': value.vipNicknameColor,
    'wallet': value.wallet,
    'has_shop': value.hasShop,
    'shop_url': value.shopUrl,
    'is_senior_member': value.isSeniorMember,
  };

  static UserInfoData decodeUserInfoData(Object? value) {
    final map = Map<String, dynamic>.from(value as Map);
    if (map['level_info'] case final Map levelInfo) {
      map['level_info'] = Map<String, dynamic>.from(levelInfo);
    }
    return UserInfoData.fromJson(map);
  }

  static Object? encodeLocalCacheValue(dynamic value) {
    if (value is RuleFilter) {
      return {
        '@appType': 'RuleFilter',
        'dmFilterString': value.dmFilterString,
        'dmRegExp': value.dmRegExp.map((item) => item.pattern).toList(),
        'dmUid': value.dmUid.toList(),
      };
    }
    return value;
  }

  static dynamic decodeLocalCacheValue(Object? value) {
    if (value case {'@appType': 'RuleFilter'}) {
      final map = Map<String, dynamic>.from(value as Map);
      return RuleFilter(
        List<String>.from(map['dmFilterString'] as List? ?? const []),
        List<String>.from(
          map['dmRegExp'] as List? ?? const [],
        ).map((item) => RegExp(item, caseSensitive: false)).toList(),
        List<String>.from(map['dmUid'] as List? ?? const []).toSet(),
      );
    }
    return value;
  }

  static Map<String, dynamic>? _encodeLevelInfo(LevelInfo? value) =>
      value == null
      ? null
      : {
          'current_level': value.currentLevel,
          'current_min': value.currentMin,
          'current_exp': value.currentExp,
          'next_exp': value.nextExp,
        };
}
