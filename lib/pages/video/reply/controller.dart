import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliMax/grpc/reply.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/models_new/dynamic/dyn_mention/item.dart';
import 'package:PiliMax/pages/common/reply/reply_controller.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/introduction/ugc/controller.dart';
import 'package:PiliMax/pages/common/reply/vote/reply_vote_mixin.dart';
import 'package:PiliMax/pages/video/reply_reply/view.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/reply_scheme_helper.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart' show BoxConstraints, WidgetsBinding;
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with
        ReplyVoteMixin,
        GetSingleTickerProviderStateMixin,
        ReplyLocateMixin,
        MainReplyLocateMixin {
  VideoReplyController({
    required this.aid,
    required this.videoType,
    required this.heroTag,
  });
  int aid;
  final VideoType videoType;
  late final isPugv = videoType == VideoType.pugv;

  final String heroTag;
  late final videoCtr = Get.find<VideoDetailController>(tag: heroTag);

  @override
  void onInit() {
    super.onInit();
    final rpid = Get.arguments?['rpid'];
    if (rpid is int) targetRpid = Int64(rpid);
  }

  MentionItem? get mentionItem {
    if (videoCtr.isUgc) {
      try {
        return Get.find<UgcIntroController>(
          tag: heroTag,
        ).videoDetail.value.owner?.mentionItem;
      } catch (_) {
        if (kDebugMode) rethrow;
      }
    }
    return null;
  }

  // 是否正在进入应用内小窗
  bool isEnteringPip = false;

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  void onAnimRootReply(ReplyInfo rootReply) {
    if (args[secondRpIdKey] case final int secondRpId) {
      clearTargetRootRpId();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => replyReply(rootReply, secondRpId),
      );
    } else {
      super.onAnimRootReply(rootReply);
    }
  }

  void replyReply(ReplyInfo replyItem, int? id) {
    videoCtr.childKey.currentState?.showBottomSheet(
      constraints: const BoxConstraints(),
      (context) => VideoReplyReplyPanel(
        id: id,
        oid: replyItem.oid.toInt(),
        rpid: replyItem.id.toInt(),
        firstFloor: replyItem.replyControl.isNote ? null : replyItem,
        replyType: videoCtr.videoType.replyType,
        isVideoDetail: true,
        isNested: videoCtr.scrollKey.currentContext != null,
        upMid: upMid,
      ),
    );
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
    rpid: rootRpId ?? targetRpid,
    type: videoType.replyType,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );

  @override
  void onClose() {
    if (kDebugMode) {
      print(
        '[PiliMax] VideoReplyController onClose called, isEnteringPip: $isEnteringPip',
      );
    }
    if (isEnteringPip) {
      return;
    }
    super.onClose();
  }
}
