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
        super.page = (count / ps).ceil();
      } else {
        super.page--;
      }
    } else {
      super.page = value;
    }
  }

  void updatePageOrder(bool value) {
    if (count == 0) return;
    _pageDesc = value;
    onReload();
  }
}
