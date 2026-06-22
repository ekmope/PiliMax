import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/member.dart';
import 'package:PiliMax/models_new/member/coin_like_arc/data.dart';
import 'package:PiliMax/models_new/member/coin_like_arc/item.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';

class MemberLikeArcController
    extends CommonListController<CoinLikeArcData, CoinLikeArcItem> {
  final dynamic mid;
  MemberLikeArcController({this.mid});

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  List<CoinLikeArcItem>? getDataList(CoinLikeArcData response) {
    return response.item;
  }

  @override
  Future<LoadingState<CoinLikeArcData>> customGetData() =>
      MemberHttp.likeArc(mid: mid, page: page);
}
