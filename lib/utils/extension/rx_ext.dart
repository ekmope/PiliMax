import 'package:get/get_rx/src/rx_types/rx_types.dart' show RxList;

extension RxListExt<E> on RxList<E> {
  /// Returns the backing list without emitting an Rx notification.
  List<E> get rawValue {
    // GetX exposes the backing value as a protected member. This extension is
    // the narrow compatibility boundary for synchronous list consumers.
    // ignore: invalid_use_of_protected_member
    return value;
  }

  void fillRangeOnly(int start, int end, [E? fill]) {
    final value = fill as E;
    for (var i = start; i < end; i++) {
      rawValue[i] = value;
    }
  }
}
