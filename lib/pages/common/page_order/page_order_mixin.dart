import 'package:PiliMax/pages/common/common_list_controller.dart';

/// Allows paged lists to load from the last page toward the first page.
mixin PageOrderMixin<R, T> on CommonListController<R, T> {
  int get ps;
  int get count;

  bool _pageDesc = false;
  bool get pageDesc => _pageDesc;

  @override
  set page(int value) {
    if (pageDesc) {
      if (value == 1) {
        super.page = count > 0 && ps > 0 ? (count / ps).ceil() : 1;
      } else {
        super.page--;
      }
    } else {
      super.page = value;
    }
  }

  void updatePageOrder(bool value) {
    if (updatePageOrderOnly(value)) return;
    onReload();
  }

  bool updatePageOrderOnly(bool value) {
    // Do not change pagination under a request that still uses the old order.
    if (isLoading || count <= 0 || value == _pageDesc) return true;
    _pageDesc = value;
    return false;
  }
}
