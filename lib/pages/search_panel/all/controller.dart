import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/search/search_type.dart';
import 'package:PiliMax/models/search/result.dart';
import 'package:PiliMax/pages/search_panel/video/controller.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/url_utils.dart';

class SearchAllController extends SearchVideoController {
  SearchAllController({
    required super.keyword,
    required super.searchType,
    required super.tag,
  });

  List<SearchUser>? searchUser;
  List<SearchPgcItemModel>? searchMedia;
  List<SearchActivity>? searchActivity;

  @override
  bool customHandleResponse(bool isRefresh, Success<SearchVideoData> response) {
    final res = response.response;
    if (isRefresh) {
      searchUser = res.searchUser;
      searchMedia = res.searchMedia;
      searchActivity = res.searchActivity;
      _actualSearchType = SearchType.video;
    }
    return super.customHandleResponse(isRefresh, response);
  }

  SearchType _actualSearchType = SearchType.all;

  @override
  SearchType get searchType_ => _actualSearchType;

  void _computeActualSearchType() {
    if (order.isNotEmpty ||
        videoDurationType != .all ||
        videoZoneType != .all ||
        pubBegin != null ||
        pubEnd != null) {
    _actualSearchType = SearchType.video;
      return;
    }
    _actualSearchType = SearchType.all;
  }

  static final _b23Regex = RegExp(r'b23\.tv/[A-Za-z0-9]{7}$', caseSensitive: false);

  Future<void> jump2Video() async {
    if (IdUtils.avRegexExact.hasMatch(keyword)) {
      hasJump2Video = true;
      PiliScheme.videoPush(
        int.parse(keyword.substring(2)),
        null,
        showDialog: false,
      );
    } else if (IdUtils.bvRegexExact.hasMatch(keyword)) {
      hasJump2Video = true;
      PiliScheme.videoPush(null, keyword, showDialog: false);
    } else if (_b23Regex.hasMatch(keyword)) {
      hasJump2Video = true;
      final redirectUrl = await UrlUtils.parseRedirectUrl(keyword);
      if (redirectUrl != null) {
        final matchRes = IdUtils.matchAvorBv(input: redirectUrl);
        final aid = matchRes.av;
        String? bvid = matchRes.bv;
        if (aid != null || bvid != null) {
          bvid ??= IdUtils.av2bv(aid!);
          PiliScheme.videoPush(aid, bvid, showDialog: false);
        }
      }
    }
  }

  @override
  Future<void> onRefresh() {
    _computeActualSearchType();
    searchUser = null;
    searchMedia = null;
    searchActivity = null;
    return super.onRefresh();
  }
}
