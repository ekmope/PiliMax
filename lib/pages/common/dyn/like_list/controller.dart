import 'package:PiliMax/grpc/bilibili/app/dynamic/v2.pb.dart'
    show LikeListReply, ModuleAuthor;
import 'package:PiliMax/grpc/dyn.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pages/common/common_list_controller.dart';
import 'package:get/get.dart';

class DynLikeController
    extends CommonListController<LikeListReply, ModuleAuthor> {
  DynLikeController(this.id, {int count = -1}) : count = RxInt(count);

  final String id;
  final RxInt count;

  @override
  List<ModuleAuthor>? getDataList(LikeListReply response) {
    count.value = response.totalCount.toInt();
    if (!response.hasMore) {
      isEnd = true;
    }
    return response.list;
  }

  @override
  Future<LoadingState<LikeListReply>> customGetData() =>
      DynGrpc.likeList(dynamicId: id, page: page);
}
