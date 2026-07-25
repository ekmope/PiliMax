import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/models/common/account_type.dart';
import 'package:PiliMax/pages/mine/controller.dart';
import 'package:PiliMax/services/crash/crash_context.dart';
import 'package:PiliMax/services/crash/crash_reporter.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:hive_ce/hive.dart';

abstract final class Accounts {
  static late final Box<LoginAccount> account;
  static Box<LoginAccount>? accountQuarantine;
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

  static Future<void> init() async {
    account = await Hive.openBox<LoginAccount>(
      'account',
      compactionStrategy: (int entries, int deletedEntries) {
        return deletedEntries > 2;
      },
    );
    try {
      accountQuarantine = await Hive.openBox<LoginAccount>(
        'accountQuarantine',
        compactionStrategy: (int entries, int deletedEntries) {
          return deletedEntries > 2;
        },
      );
    } catch (_, stackTrace) {
      accountQuarantine = null;
      _recordQuarantineError(
        stackTrace,
        operation: 'quarantine.open',
        reason: 'quarantine_unavailable',
      );
    }
    await _quarantineInvalidAccounts();
  }

  static Future<void> refresh() async {
    await _quarantineInvalidAccounts();
    for (int i = 0; i < AccountType.values.length; i++) {
      accountMode[i] = AnonymousAccount();
    }
    for (final a in account.values) {
      if (!a.isValid) {
        continue;
      }
      for (final t in a.type) {
        accountMode[t.index] = a;
      }
    }
    await Future.wait(
      (accountMode.toSet()..removeWhere((i) => i.activated)).map(
        Request.buvidActive,
      ),
    );
  }

  static Future<void> _quarantineInvalidAccounts() async {
    final invalidEntries = account
        .toMap()
        .entries
        .where((entry) => !entry.value.isValid)
        .toList(growable: false);
    for (final entry in invalidEntries) {
      final issue =
          entry.value.validationIssue ??
          LoginAccountValidationIssue.malformedAccountData;
      final quarantine = accountQuarantine;
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
        await account.delete(entry.key);
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
