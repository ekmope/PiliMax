import 'package:PiliMax/http/live.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/config.dart';
import 'package:PiliMax/models_new/live/live_fans_medal/item.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts/account.dart';
import 'package:PiliMax/pilimax/live/fans_medal_actions.dart';
import 'package:get/get.dart';

class FansMedalController extends GetxController {
  final Account account = Accounts.main;
  final items = <FansMedalItem>[].obs;
  final loading = false.obs;
  final acting = false.obs;
  final error = RxnString();
  final total = RxnInt();
  final hasMore = false.obs;
  final config = Rxn<FansMedalConfig>();
  final configLoading = false.obs;
  final configError = RxnString();
  int _page = 0;
  int _generation = 0;
  int? _nextPage;

  bool get isCurrent => !isClosed && identical(account, Accounts.main);

  @override
  void onClose() {
    _generation++;
    super.onClose();
  }

  Future<void> reload() => load(refresh: true);

  Future<void> load({bool refresh = false}) async {
    if (!isCurrent || loading.value || acting.value) return;
    if (!account.isLogin) {
      error.value = '账号未登录';
      return;
    }
    if (!refresh && !hasMore.value) return;
    final page = refresh ? 1 : _nextPage;
    if (page == null || page < 1 || page > 20 || (!refresh && page <= _page)) {
      hasMore.value = false;
      return;
    }
    final generation = ++_generation;
    loading.value = true;
    try {
      final result = await LiveHttp.fansMedalPanel(
        page: page,
        account: account,
      );
      if (!isCurrent || generation != _generation) return;
      if (result case Success(:final response)) {
        final existing = refresh ? <FansMedalItem>[] : items.toList();
        final ids = {for (final item in existing) identity(item)};
        var added = 0;
        for (final item in [...?response.specialList, ...?response.list]) {
          if (ids.add(identity(item))) {
            existing.add(item);
            added++;
          }
        }
        items.assignAll(existing);
        total.value = response.totalNumber ?? (refresh ? null : total.value);
        _page = page;
        // Older panel responses omit next_page; only advance when has_more
        // explicitly permits another page, and stop if it repeats known data.
        _nextPage = response.nextPage ?? page + 1;
        hasMore.value =
            response.hasMore == true &&
            added > 0 &&
            _nextPage! > page &&
            _nextPage! <= 20 &&
            (total.value == null || items.length < total.value!);
        error.value = null;
      } else {
        error.value = result.toString();
        if (items.isNotEmpty) await result.toast();
      }
    } finally {
      if (!isClosed && generation == _generation) loading.value = false;
    }
  }

  static String identity(FansMedalItem item) =>
      '${item.medal?.medalId ?? item.uinfoMedal?.id ?? ''}:'
      '${item.medal?.targetId ?? item.uinfoMedal?.ruid ?? ''}:'
      '${item.medal?.medalName ?? item.uinfoMedal?.name ?? ''}';

  Future<void> toggle(FansMedalItem item) async {
    if (!isCurrent || !account.isLogin || loading.value || acting.value) return;
    final id = item.medal?.medalId ?? item.uinfoMedal?.id;
    final target = item.medal?.targetId ?? item.uinfoMedal?.ruid;
    if (id == null || id <= 0 || target == null || target <= 0) {
      await const Error('勋章信息不完整，请刷新后重试').toast();
      return;
    }
    acting.value = true;
    try {
      final wearing = item.medal?.wearingStatus == 1;
      final result = await FansMedalActions.run(
        () => wearing
            ? LiveHttp.fansMedalTakeOff(
                medalId: id,
                targetId: target,
                account: account,
              )
            : LiveHttp.fansMedalWear(
                medalId: id,
                targetId: target,
                account: account,
              ),
      );
      if (!isCurrent) return;
      if (!result.isSuccess) {
        await result.toast();
        return;
      }
      for (final entry in items) {
        entry.medal?.wearingStatus = identical(entry, item) && !wearing ? 1 : 0;
      }
      items.refresh();
    } finally {
      if (!isClosed) acting.value = false;
    }
  }

  Future<void> loadConfig() async {
    if (!isCurrent || !account.isLogin || configLoading.value) return;
    configLoading.value = true;
    try {
      final result = await LiveHttp.fansMedalConfig(account: account);
      if (!isCurrent) return;
      if (result case Success(:final response)) {
        config.value = response;
        configError.value = null;
      } else {
        configError.value = result.toString();
      }
    } finally {
      if (!isClosed) configLoading.value = false;
    }
  }

  Future<void> setConfig(String key, bool enabled) async {
    if (!isCurrent || configLoading.value || !account.isLogin) return;
    configLoading.value = true;
    try {
      final result = await LiveHttp.setFansMedalConfig(
        key: key,
        enabled: enabled,
        account: account,
      );
      if (!isCurrent) return;
      if (result.isSuccess) {
        final current = config.value;
        config.value = FansMedalConfig(
          closeSpaceMedal: key == FansMedalConfig.closeSpaceMedalKey
              ? enabled
              : current?.closeSpaceMedal,
          onlyShowWearing: key == FansMedalConfig.onlyShowWearingKey
              ? enabled
              : current?.onlyShowWearing,
        );
        configError.value = null;
      } else {
        configError.value = result.toString();
        await result.toast();
      }
    } finally {
      if (!isClosed) configLoading.value = false;
    }
  }
}
