import 'dart:async' show FutureOr;

import 'package:get/get.dart';

mixin LoadingActionMixin<K> on GetxController {
  final RxSet<K> loadingActions = <K>{}.obs;

  bool isActionLoading(K key) => loadingActions.contains(key);

  void setActionLoading(K key, bool loading) {
    if (loading) {
      loadingActions.add(key);
    } else {
      loadingActions.remove(key);
    }
    loadingActions.refresh();
  }

  Future<T?> runWithActionLoading<T>(
    K key,
    FutureOr<T> Function() action,
  ) async {
    if (isActionLoading(key)) {
      return null;
    }
    setActionLoading(key, true);
    try {
      return await action();
    } finally {
      setActionLoading(key, false);
    }
  }
}
