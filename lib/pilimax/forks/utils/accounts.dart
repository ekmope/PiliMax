import 'package:PiliMax/pilimax/forks/http/init.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/pages/mine/controller.dart';
import 'package:PiliMax/pilimax/services/crash/crash_context.dart';
import 'package:PiliMax/pilimax/services/crash/crash_reporter.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/pilimax/utils/accounts/account_storage.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:hive_ce/hive.dart';

abstract final class Accounts {
  static late final Box<LoginAccount> account;
  static Box<LoginAccount>? accountQuarantine;
  static AccountStorage? _accountStorage;
  static Future<void>? _initFuture;
  static bool _initialized = false;
  static bool reauthenticationRequired = false;
  static final List<Account> accountMode = List.filled(
    AccountType.values.length,
    AnonymousAccount(),
  );
  static bool get mainEqVideo => main == video;
  static Account get main => accountMode[AccountType.main.index];
  static Account get video => accountMode[AccountType.video.index];
  static Account get heartbeat => accountMode[AccountType.heartbeat.index];
  static Account get history {
    final heartbeat = Accounts.heartbeat;
    if (heartbeat is AnonymousAccount) {
      return Accounts.main;
    }
    return heartbeat;
  }
  // static set main(Account account) => set(AccountType.main, account);

  static Future<void> init({AccountSecretStore? secretStore}) {
    if (_initialized) return Future<void>.value();
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _initOnce(secretStore);
    _initFuture = future;
    return future.whenComplete(() {
      if (identical(_initFuture, future)) {
        _initFuture = null;
      }
    });
  }

  static Future<void> _initOnce(AccountSecretStore? secretStore) async {
    final nextStorage = AccountStorage(
      secretStore: secretStore ?? const PlatformAccountSecretStore(),
    );
    AccountStorageOpenResult? opened;
    try {
      opened = await nextStorage.open();
      await _quarantineInvalidAccountsIn(
        opened.account,
        opened.quarantine,
      );
      account = opened.account;
      accountQuarantine = opened.quarantine;
      _accountStorage = nextStorage;
      reauthenticationRequired = opened.requiresReauthentication;
      _initialized = true;
    } catch (error, stackTrace) {
      try {
        await opened?.quarantine.close();
      } catch (_) {}
      try {
        await opened?.account.close();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> markReauthenticated() async {
    if (!reauthenticationRequired) return;
    final storage = _accountStorage;
    if (storage == null) return;
    try {
      await storage.markReauthenticated();
      reauthenticationRequired = false;
    } catch (_, stackTrace) {
      _recordQuarantineError(
        stackTrace,
        operation: 'secure_storage.reauthentication',
        reason: 'marker_delete_failed',
      );
    }
  }

  static Future<void> restoreAccountModes() async {
    await _quarantineInvalidAccounts();
    _publishAccountModes(account.values);
  }

  static void _publishAccountModes(Iterable<LoginAccount> accounts) {
    final nextModes = List<Account>.generate(
      AccountType.values.length,
      (_) => AnonymousAccount(),
      growable: false,
    );
    for (final a in accounts) {
      if (!a.isValid) {
        continue;
      }
      for (final t in a.type) {
        nextModes[t.index] = a;
      }
    }

    // Publish without an async gap so request interceptors never observe a
    // partially restored selection.
    for (var i = 0; i < nextModes.length; i++) {
      accountMode[i] = nextModes[i];
    }
  }

  static Future<void> activateAccountModes({
    Future<void> Function(Account account)? activate,
  }) {
    final activateAccount = activate ?? Request.buvidActive;
    return Future.wait(
      (accountMode.toSet()..removeWhere((i) => i.activated)).map(
        activateAccount,
      ),
    );
  }

  static Future<void> refresh() async {
    await restoreAccountModes();
    await activateAccountModes();
  }

  static Future<void> _quarantineInvalidAccounts() =>
      _quarantineInvalidAccountsIn(account, accountQuarantine);

  static Future<void> _quarantineInvalidAccountsIn(
    Box<LoginAccount> source,
    Box<LoginAccount>? quarantine,
  ) async {
    final invalidEntries = source
        .toMap()
        .entries
        .where((entry) => !entry.value.isValid)
        .toList(growable: false);
    for (final entry in invalidEntries) {
      final issue =
          entry.value.validationIssue ??
          LoginAccountValidationIssue.malformedAccountData;
      if (quarantine == null) {
        continue;
      }
      try {
        await quarantine.put(entry.key, entry.value);
      } catch (_, stackTrace) {
        _recordQuarantineError(
          stackTrace,
          operation: 'quarantine.write',
          reason: issue.name,
        );
        continue;
      }
      try {
        await source.delete(entry.key);
      } catch (_, stackTrace) {
        _recordQuarantineError(
          stackTrace,
          operation: 'quarantine.delete',
          reason: issue.name,
        );
      }
    }
  }

  static void _recordQuarantineError(
    StackTrace stackTrace, {
    required String operation,
    required String reason,
  }) {
    try {
      CrashReporter.recordErrorSync(
        StateError('Account quarantine operation failed'),
        stackTrace,
        severity: CrashSeverity.handled,
        module: 'accounts',
        operation: operation,
        reason: reason,
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    await Future.wait([
      account.clear(),
      ?accountQuarantine?.clear(),
    ]);
    for (int i = 0; i < AccountType.values.length; i++) {
      accountMode[i] = AnonymousAccount();
    }
    await AnonymousAccount().delete();
    Request.buvidActive(AnonymousAccount());
  }

  static Future<void> deleteAll(Set<Account> accounts) async {
    final isLoginMain = Accounts.main.isLogin;
    for (int i = 0; i < AccountType.values.length; i++) {
      if (accounts.contains(accountMode[i])) {
        accountMode[i] = AnonymousAccount();
      }
    }
    await Future.wait(accounts.map((i) => i.delete()));
    if (isLoginMain && !Accounts.main.isLogin) {
      await LoginUtils.onLogoutMain();
    }
  }

  static Future<void> set(AccountType key, Account account) async {
    final oldAccount = accountMode[key.index]..type.remove(key);
    accountMode[key.index] = account..type.add(key);
    await Future.wait([?account.onChange(), ?oldAccount.onChange()]);
    if (!account.activated) await Request.buvidActive(account);
    switch (key) {
      case AccountType.main:
        await (account.isLogin
            ? LoginUtils.onLoginMain()
            : LoginUtils.onLogoutMain());
        break;
      case AccountType.heartbeat:
        MineController.anonymity.value = !account.isLogin;
        break;
      default:
        break;
    }
  }

  @pragma("vm:prefer-inline")
  static Account get(AccountType key) {
    return accountMode[key.index];
  }
}
