import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/grpc_headers.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:hive_ce/hive.dart';

sealed class Account {
  Map<String, dynamic>? toJson() => null;

  Future<void>? onChange() => null;

  Set<AccountType> get type => const {};

  bool get activated => false;

  set activated(bool value) => throw UnimplementedError();

  String? get accessKey => throw UnimplementedError();

  DefaultCookieJar get cookieJar => throw UnimplementedError();

  String get csrf => throw UnimplementedError();

  Future<void> delete() => throw UnimplementedError();

  Map<String, String> get headers => throw UnimplementedError();

  Map<String, String> get grpcHeaders => throw UnimplementedError();

  bool get isLogin => throw UnimplementedError();

  int get mid => throw UnimplementedError();

  String? get refresh => throw UnimplementedError();

  const Account();
}

enum LoginAccountValidationIssue {
  missingSession,
  missingUserId,
  invalidUserId,
  missingCsrf,
  malformedCookieData,
  malformedAccountData,
}

final class LoginAccountValidationException implements Exception {
  final LoginAccountValidationIssue issue;

  const LoginAccountValidationException(this.issue);

  @override
  String toString() => 'LoginAccountValidationException(${issue.name})';
}

final class _LoginIdentity {
  final String midString;
  final int mid;
  final String csrf;

  const _LoginIdentity(this.midString, this.mid, this.csrf);
}

@HiveType(typeId: 9)
class LoginAccount extends Account {
  @override
  final bool isLogin = true;
  @override
  @HiveField(0)
  final DefaultCookieJar cookieJar;
  @override
  @HiveField(1)
  final String? accessKey;
  @override
  @HiveField(2)
  final String? refresh;
  @override
  @HiveField(3)
  final Set<AccountType> type;

  @override
  bool activated = false;

  final _LoginIdentity? _identity;

  final LoginAccountValidationIssue? validationIssue;

  bool get isValid => validationIssue == null && _identity != null;

  _LoginIdentity get _validIdentity {
    if (!isValid) {
      throw StateError('Invalid login account');
    }
    return _identity!;
  }

  @override
  late final int mid = _validIdentity.mid;

  @override
  late final Map<String, String> headers = {
    ...Constants.baseHeaders,
    'x-bili-mid': _validIdentity.midString,
    'x-bili-aurora-eid': IdUtils.genAuroraEid(mid),
  };

  @override
  late final Map<String, String> grpcHeaders = GrpcHeaders.newHeaders(
    accessKey,
  );

  @override
  late final String csrf = _validIdentity.csrf;

  bool _hasDeleted = false;
  Future<void>? _deleteFuture;

  @override
  Future<void> delete() {
    if (!isValid) {
      return Future.error(StateError('Invalid login account'));
    }
    final pendingDelete = _deleteFuture;
    if (pendingDelete != null) {
      return pendingDelete;
    }

    late final Future<void> deleteFuture;
    deleteFuture =
        Future.wait([
              cookieJar.deleteAll(),
              _box.delete(_validIdentity.midString),
            ])
            .then<void>((_) {
              _hasDeleted = true;
            })
            .whenComplete(() {
              if (!_hasDeleted && identical(_deleteFuture, deleteFuture)) {
                _deleteFuture = null;
              }
            });
    _deleteFuture = deleteFuture;
    return deleteFuture;
  }

  @override
  Future<void> onChange() {
    if (!isValid) {
      return Future.error(StateError('Invalid login account'));
    }
    if (_hasDeleted || _deleteFuture != null) {
      return Future.error(StateError('Deleted login account'));
    }
    return _box
        .put(_validIdentity.midString, this)
        .then<void>((_) => Accounts.markReauthenticated());
  }

  @override
  Map<String, dynamic>? toJson() => {
    'cookies': cookieJar.toJson(),
    'accessKey': accessKey,
    'refresh': refresh,
    'type': type.map((i) => i.index).toList(),
  };

  late final Box<LoginAccount> _box = Accounts.account;

  factory LoginAccount(
    DefaultCookieJar cookieJar,
    Object? accessKey,
    Object? refresh, [
    Set<AccountType>? type,
  ]) {
    final identity = _validateIdentity(cookieJar);
    return _createValidated(
      cookieJar,
      accessKey,
      refresh,
      type,
      identity,
    );
  }

  static LoginAccount _createValidated(
    DefaultCookieJar cookieJar,
    Object? accessKey,
    Object? refresh,
    Set<AccountType>? type,
    _LoginIdentity identity,
  ) {
    final account = LoginAccount._(
      cookieJar,
      _optionalCredential(accessKey),
      _optionalCredential(refresh),
      type ?? <AccountType>{},
      identity,
      null,
    );
    cookieJar.setBuvid3();
    return account;
  }

  LoginAccount._(
    this.cookieJar,
    this.accessKey,
    this.refresh,
    this.type,
    this._identity,
    this.validationIssue,
  );

  factory LoginAccount.fromCookieMap(
    Object? cookies, {
    Object? accessKey,
    Object? refresh,
    Set<AccountType>? type,
  }) {
    final cookieMap = _parseCookieMap(cookies);
    final identity = _validateIdentityValues(cookieMap);
    return _createValidated(
      _cookieJarFromValues(cookieMap),
      accessKey,
      refresh,
      type,
      identity,
    );
  }

  factory LoginAccount.fromCookieList(
    Object? cookies, {
    Object? accessKey,
    Object? refresh,
    Set<AccountType>? type,
  }) => LoginAccount.fromCookieMap(
    _parseCookieList(cookies),
    accessKey: accessKey,
    refresh: refresh,
    type: type,
  );

  factory LoginAccount.fromJson(Object? json) {
    if (json is! Map) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.malformedAccountData,
      );
    }
    return LoginAccount.fromCookieMap(
      json['cookies'],
      accessKey: json['accessKey'],
      refresh: json['refresh'],
      type: _accountTypesFromJson(json['type']),
    );
  }

  factory LoginAccount.fromStorage({
    required Object? cookieJar,
    Object? accessKey,
    Object? refresh,
    Object? type,
  }) {
    LoginAccountValidationIssue? issue;
    final DefaultCookieJar safeCookieJar;
    if (cookieJar is DefaultCookieJar) {
      safeCookieJar = cookieJar;
    } else {
      safeCookieJar = BiliCookieJar.fromStorageJson(null);
      issue = LoginAccountValidationIssue.malformedAccountData;
    }

    final String? safeAccessKey;
    if (accessKey == null || accessKey is String) {
      safeAccessKey = accessKey as String?;
    } else {
      safeAccessKey = null;
      issue ??= LoginAccountValidationIssue.malformedAccountData;
    }

    final String? safeRefresh;
    if (refresh == null || refresh is String) {
      safeRefresh = refresh as String?;
    } else {
      safeRefresh = null;
      issue ??= LoginAccountValidationIssue.malformedAccountData;
    }

    final safeTypes = <AccountType>{};
    if (type != null) {
      if (type is Iterable) {
        for (final value in type) {
          if (value is AccountType) {
            safeTypes.add(value);
          } else {
            issue ??= LoginAccountValidationIssue.malformedAccountData;
          }
        }
      } else {
        issue ??= LoginAccountValidationIssue.malformedAccountData;
      }
    }

    _LoginIdentity? identity;
    try {
      identity = _validateIdentity(safeCookieJar);
    } on LoginAccountValidationException catch (error) {
      issue ??= error.issue;
    }

    final account = LoginAccount._(
      safeCookieJar,
      safeAccessKey,
      safeRefresh,
      safeTypes,
      identity,
      issue,
    );
    if (account.isValid) {
      safeCookieJar.setBuvid3();
    }
    return account;
  }

  static String? _optionalCredential(Object? value) {
    if (value == null || value is String) {
      return value as String?;
    }
    throw const LoginAccountValidationException(
      LoginAccountValidationIssue.malformedAccountData,
    );
  }

  static Set<AccountType> _accountTypesFromJson(Object? value) {
    if (value == null) {
      return <AccountType>{};
    }
    if (value is! Iterable) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.malformedAccountData,
      );
    }

    final types = <AccountType>{};
    for (final index in value) {
      if (index is! int || index < 0 || index >= AccountType.values.length) {
        throw const LoginAccountValidationException(
          LoginAccountValidationIssue.malformedAccountData,
        );
      }
      types.add(AccountType.values[index]);
    }
    return types;
  }

  static _LoginIdentity _validateIdentity(DefaultCookieJar cookieJar) {
    final cookies = cookieJar.domainCookies['bilibili.com']?['/'];
    return _validateIdentityValues({
      if (cookies?['SESSDATA'] case final cookie?)
        'SESSDATA': cookie.cookie.value,
      if (cookies?['DedeUserID'] case final cookie?)
        'DedeUserID': cookie.cookie.value,
      if (cookies?['bili_jct'] case final cookie?)
        'bili_jct': cookie.cookie.value,
    });
  }

  static _LoginIdentity _validateIdentityValues(
    Map<String, String> cookies,
  ) {
    final session = cookies['SESSDATA'];
    if (session == null || session.trim().isEmpty) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.missingSession,
      );
    }

    final midString = cookies['DedeUserID'];
    if (midString == null || midString.trim().isEmpty) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.missingUserId,
      );
    }
    final mid = int.tryParse(midString);
    if (mid == null || mid <= 0) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.invalidUserId,
      );
    }

    final csrf = cookies['bili_jct'];
    if (csrf == null || csrf.trim().isEmpty) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.missingCsrf,
      );
    }
    return _LoginIdentity(midString, mid, csrf);
  }

  @override
  int get hashCode => isValid ? mid.hashCode : identityHashCode(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (isValid && other is LoginAccount && other.isValid && mid == other.mid);
}

class AnonymousAccount extends Account {
  @override
  final bool isLogin = false;
  @override
  final DefaultCookieJar cookieJar = DefaultCookieJar()..setBuvid3();
  @override
  final String? accessKey = null;
  @override
  final String? refresh = null;
  @override
  final Set<AccountType> type = {};
  @override
  final int mid = 0;
  @override
  final String csrf = '';
  @override
  final Map<String, String> headers = Constants.baseHeaders;

  @override
  final Map<String, String> grpcHeaders = GrpcHeaders.newHeaders();

  @override
  bool activated = false;

  @override
  Future<void> delete() {
    grpcHeaders['x-bili-fawkes-req-bin'] = GrpcHeaders.fawkes;
    return cookieJar.deleteAll().whenComplete(cookieJar.setBuvid3);
  }

  static final _instance = AnonymousAccount._();

  AnonymousAccount._();

  factory AnonymousAccount() => _instance;

  @override
  int get hashCode => cookieJar.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnonymousAccount && cookieJar == other.cookieJar);
}

extension BiliCookie on Cookie {
  void setBiliDomain([String domain = '.bilibili.com']) {
    this.domain = domain;
    httpOnly = false;
    path = '/';
  }
}

extension BiliCookieJar on DefaultCookieJar {
  Map<String, String> toJson() {
    final cookies = domainCookies['bilibili.com']?['/'] ?? const {};
    return {for (final i in cookies.values) i.cookie.name: i.cookie.value};
  }

  List<Cookie> toList() =>
      domainCookies['bilibili.com']?['/']?.entries
          .map((i) => i.value.cookie)
          .toList() ??
      [];

  void setBuvid3() {
    (domainCookies['bilibili.com'] ??= {
      '/': {},
    })['/']!['buvid3'] ??= SerializableCookie(
      Cookie('buvid3', IdUtils.genBuvid3())..setBiliDomain(),
    );
  }

  static DefaultCookieJar fromJson(Object? json) {
    return _cookieJarFromValues(_parseCookieMap(json));
  }

  static DefaultCookieJar fromList(Object? cookieList) =>
      _cookieJarFromValues(_parseCookieList(cookieList));

  static DefaultCookieJar fromStorageJson(Object? json) {
    final cookies = <String, SerializableCookie>{};
    if (json is Map) {
      for (final entry in json.entries) {
        if (entry.key is! String || entry.value is! String) {
          continue;
        }
        try {
          final name = entry.key as String;
          cookies[name] = SerializableCookie(
            Cookie(name, entry.value as String)..setBiliDomain(),
          );
        } catch (_) {}
      }
    }
    return DefaultCookieJar(ignoreExpires: true)
      ..domainCookies['bilibili.com'] = {'/': cookies};
  }
}

Map<String, String> _parseCookieMap(Object? json) {
  if (json is! Map) {
    throw const LoginAccountValidationException(
      LoginAccountValidationIssue.malformedCookieData,
    );
  }
  final cookies = <String, String>{};
  for (final entry in json.entries) {
    if (entry.key is! String || entry.value is! String) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.malformedCookieData,
      );
    }
    cookies[entry.key as String] = entry.value as String;
  }
  return cookies;
}

Map<String, String> _parseCookieList(Object? cookieList) {
  if (cookieList is! List) {
    throw const LoginAccountValidationException(
      LoginAccountValidationIssue.malformedCookieData,
    );
  }
  final cookies = <String, String>{};
  for (final item in cookieList) {
    if (item is! Map || item['name'] is! String || item['value'] is! String) {
      throw const LoginAccountValidationException(
        LoginAccountValidationIssue.malformedCookieData,
      );
    }
    cookies[item['name'] as String] = item['value'] as String;
  }
  return cookies;
}

DefaultCookieJar _cookieJarFromValues(Map<String, String> values) {
  final cookies = <String, SerializableCookie>{};
  try {
    for (final entry in values.entries) {
      cookies[entry.key] = SerializableCookie(
        Cookie(entry.key, entry.value)..setBiliDomain(),
      );
    }
  } catch (_) {
    throw const LoginAccountValidationException(
      LoginAccountValidationIssue.malformedCookieData,
    );
  }
  return DefaultCookieJar(ignoreExpires: true)
    ..domainCookies['bilibili.com'] = {'/': cookies};
}

final class NoAccount extends Account {
  const NoAccount();
}
