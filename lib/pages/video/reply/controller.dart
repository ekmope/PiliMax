import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliMax/grpc/reply.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models/common/video/video_type.dart';
import 'package:PiliMax/pages/common/reply_controller.dart';
import 'package:PiliMax/pages/video/controller.dart';
import 'package:PiliMax/pages/video/reply/vote/reply_vote_mixin.dart';
import 'package:PiliMax/services/logger.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with ReplyVoteMixin {
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

  // 是否正在进入应用内小窗
  bool isEnteringPip = false;

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
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
