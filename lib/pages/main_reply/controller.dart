import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliMax/grpc/reply.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pages/common/reply_controller.dart';
import 'package:get/get.dart';

class MainReplyController extends ReplyController<MainListReply> {
  MainReplyController({
    this.initialOid,
    this.initialReplyType,
    this.initialHeroTag,
  });

  final int? initialOid;
  final int? initialReplyType;
  final String? initialHeroTag;

  late final int oid;
  late final int replyType;
  late final String? heroTag;

  @override
  int get sourceId => oid;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map?;
    oid = initialOid ?? (args?['oid'] as int);
    replyType = initialReplyType ?? (args?['replyType'] as int);
    heroTag = initialHeroTag ?? (args?['heroTag'] as String?);

    queryData();
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    type: replyType,
    oid: oid,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );

  @override
  List<ReplyInfo>? getDataList(MainListReply response) => response.replies;
}
