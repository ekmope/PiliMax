import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliMax/grpc/reply.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/dynamic/dyn_mention/item.dart';
import 'package:PiliMax/pages/common/reply/reply_controller.dart';
import 'package:PiliMax/pages/common/reply/vote/reply_vote_mixin.dart';
import 'package:PiliMax/utils/reply_scheme_helper.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:get/get.dart';

mixin DynReplyLocateMixin on MainReplyLocateMixin {
  int? targetSecondRpId; // jump

  @override
  void onAnimRootReply(ReplyInfo rootReply) {
    if (args[secondRpIdKey] case final int secondRpId) {
      args.remove(rootRpIdKey);
      targetRootRpId = rootRpId;
      targetSecondRpId = secondRpId;
    } else {
      super.onAnimRootReply(rootReply);
    }
  }
}

abstract class CommonDynController extends ReplyController<MainListReply>
    with
        ReplyVoteMixin,
        GetSingleTickerProviderStateMixin,
        ReplyLocateMixin<MainListReply>,
        MainReplyLocateMixin,
        DynReplyLocateMixin {
  int get oid;
  int get replyType;

  MentionItem? get mentionItem => null;

  late final RxBool showTitle = false.obs;

  late final horizontalPreview = Pref.horizontalPreview;
  late final List<double> ratio = Pref.dynamicDetailRatio;

  late final showDynActionBar = Pref.showDynActionBar;

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    type: replyType,
    oid: oid,
    rpid: rootRpId ?? targetRpid,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }
}
