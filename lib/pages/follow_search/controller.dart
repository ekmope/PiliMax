import 'dart:async';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/member.dart';
import 'package:PiliMax/models_new/follow/data.dart';
import 'package:PiliMax/models_new/follow/list.dart';
import 'package:PiliMax/pages/common/search/common_search_controller.dart';
import 'package:get/get.dart';

class FollowSearchController
    extends CommonSearchController<FollowData, FollowItemModel> {
  FollowSearchController(this.mid) {
    editController.addListener(_onQueryChanged);
  }

  final int mid;

  static const int _suggestionPageSize = 8;

  /// Live results are kept separate from the committed, paginated search
  /// results managed by [loadingState].
  final suggestions = <FollowItemModel>[].obs;

  Timer? _suggestionTimer;
  int _suggestionRequestId = 0;
  bool _isDisposed = false;

  void _onQueryChanged() {
    if (_isDisposed) return;
    _suggestionTimer?.cancel();
    final requestId = ++_suggestionRequestId;
    final query = editController.text.trim();
    if (query.isEmpty) {
      suggestions.clear();
      return;
    }

    _suggestionTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_loadSuggestions(query, requestId)),
    );
  }

  Future<void> _loadSuggestions(String query, int requestId) async {
    try {
      final res = await MemberHttp.getfollowSearch(
        mid: mid,
        ps: _suggestionPageSize,
        pn: 1,
        name: query,
      );
      if (_isDisposed ||
          requestId != _suggestionRequestId ||
          editController.text.trim() != query) {
        return;
      }

      if (res case Success(:final response)) {
        suggestions.assignAll(
          response.list
              .where(
                (item) => item.mid > 0 && item.uname?.trim().isNotEmpty == true,
              )
              .take(_suggestionPageSize),
        );
      } else {
        suggestions.clear();
      }
    } catch (_) {
      if (!_isDisposed &&
          requestId == _suggestionRequestId &&
          editController.text.trim() == query) {
        suggestions.clear();
      }
    }
  }

  void _clearSuggestions() {
    _suggestionTimer?.cancel();
    _suggestionTimer = null;
    _suggestionRequestId++;
    suggestions.clear();
  }

  @override
  Future<void> onRefresh() {
    _clearSuggestions();
    return super.onRefresh();
  }

  @override
  Future<LoadingState<FollowData>> customGetData() =>
      MemberHttp.getfollowSearch(
        mid: mid,
        ps: 20,
        pn: page,
        name: editController.value.text,
      );

  @override
  List<FollowItemModel>? getDataList(FollowData response) {
    return response.list;
  }

  @override
  void onClose() {
    _isDisposed = true;
    editController.removeListener(_onQueryChanged);
    _clearSuggestions();
    super.onClose();
  }
}
