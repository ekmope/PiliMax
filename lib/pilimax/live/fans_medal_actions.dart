import 'package:PiliMax/http/loading_state.dart';
import 'package:get/get.dart';

/// Room panels, automatic wearing and the global page share a single action
/// lane. A slow action must not overwrite a newer choice made in another page.
abstract final class FansMedalActions {
  static final revision = 0.obs;
  static bool _busy = false;

  static bool get isBusy => _busy;

  static Future<LoadingState<void>> run(
    Future<LoadingState<void>> Function() action,
  ) async {
    if (_busy) return const Error('粉丝勋章操作进行中，请稍后重试');
    _busy = true;
    try {
      final result = await action();
      if (result.isSuccess) revision.value++;
      return result;
    } finally {
      _busy = false;
    }
  }
}
