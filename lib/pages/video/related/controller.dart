import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/video.dart';
import 'package:PiliMax/models/model_hot_video_item.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';
import 'package:get/get.dart';

class RelatedController
    extends CommonListController<List<HotVideoItemModel>?, HotVideoItemModel> {
  RelatedController({
    this.autoQuery = true,
    String? bvid,
    Future<LoadingState<List<HotVideoItemModel>?>>? initialRelated,
  }) : _bvid = bvid ?? Get.arguments['bvid'],
       _initialRelated = initialRelated {
    _initialBvid = _bvid;
  }

  final bool autoQuery;
  late final String _initialBvid;
  String _bvid;
  Future<LoadingState<List<HotVideoItemModel>?>>? _initialRelated;
  Future<void>? _activeQuery;
  bool _queryRequested = false;
  bool _closed = false;
  int _requestGeneration = 0;

  String get bvid => _bvid;

  set bvid(String value) {
    if (_bvid == value) {
      return;
    }
    _bvid = value;
    loadingState.value = LoadingState<List<HotVideoItemModel>?>.loading();
  }

  @override
  void onInit() {
    super.onInit();
    if (autoQuery) {
      queryData();
    }
  }

  Future<void> ensureLoaded() {
    final activeQuery = _activeQuery;
    if (activeQuery != null) {
      return activeQuery;
    }
    return loadingState.value is Loading ? queryData() : Future.value();
  }

  @override
  Future<void> queryData([bool isRefresh = true]) {
    if (_closed || (!isRefresh && isEnd)) {
      return Future.value();
    }
    _queryRequested = true;
    _requestGeneration++;
    final activeQuery = _activeQuery;
    if (activeQuery != null) {
      return activeQuery;
    }

    late final Future<void> query;
    query = _drainQueries().whenComplete(() {
      if (identical(_activeQuery, query)) {
        _activeQuery = null;
      }
    });
    _activeQuery = query;
    return query;
  }

  Future<void> _drainQueries() async {
    isLoading = true;
    try {
      while (_queryRequested && !_closed) {
        _queryRequested = false;
        final generation = _requestGeneration;
        final requestBvid = _bvid;
        LoadingState<List<HotVideoItemModel>?> result;
        try {
          result = await _getData(requestBvid);
        } catch (error) {
          result = Error(error.toString());
        }
        if (_closed) {
          return;
        }
        if (generation != _requestGeneration || requestBvid != _bvid) {
          continue;
        }
        _applyResult(result);
      }
    } finally {
      isLoading = false;
    }
  }

  Future<LoadingState<List<HotVideoItemModel>?>> _getData(
    String requestBvid,
  ) {
    if (requestBvid == _initialBvid) {
      final initialRelated = _initialRelated;
      _initialRelated = null;
      if (initialRelated != null) {
        return initialRelated;
      }
    }
    return VideoHttp.relatedVideoList(bvid: requestBvid);
  }

  void _applyResult(LoadingState<List<HotVideoItemModel>?> result) {
    switch (result) {
      case Success(:final response):
        isEnd = response == null || response.isEmpty;
        if (response != null && response.isNotEmpty) {
          handleListResponse(response);
          checkIsEnd(response.length);
        }
        loadingState.value = Success(response);
        page++;
        break;
      case Error(:final errMsg):
        if (!handleError(errMsg)) {
          loadingState.value = result;
        }
        break;
      case Loading():
        loadingState.value = result;
        break;
    }
  }

  @override
  Future<LoadingState<List<HotVideoItemModel>?>> customGetData() =>
      _getData(_bvid);

  @override
  void onClose() {
    _closed = true;
    _initialRelated = null;
    super.onClose();
  }
}
