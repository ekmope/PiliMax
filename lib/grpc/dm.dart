import 'package:PiliMax/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliMax/grpc/grpc_req.dart';
import 'package:PiliMax/grpc/url.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/video/video_play_info/subtitle.dart';
import 'package:fixnum/fixnum.dart';

abstract final class DmGrpc {
  static Future<LoadingState<DmSegMobileReply>> dmSegMobile({
    required int cid,
    required int segmentIndex,
    int type = 1,
  }) {
    return GrpcReq.request(
      GrpcUrl.dmSegMobile,
      DmSegMobileReq(
        oid: Int64(cid),
        segmentIndex: Int64(segmentIndex),
        type: type,
      ),
      DmSegMobileReply.fromBuffer,
      isolate: true,
    );
  }

  static Future<LoadingState<DmViewReply>> dmView(int aid, int cid) {
    return GrpcReq.request(
      GrpcUrl.dmView,
      DmViewReq(pid: Int64(aid), oid: Int64(cid), type: 1),
      DmViewReply.fromBuffer,
    );
  }

  static List<Subtitle>? dmViewToSubtitle(DmViewReply? dmView) {
    if (dmView == null || !dmView.hasSubtitle()) return null;
    final subtitles = dmView.subtitle.subtitles;
    if (subtitles.isEmpty) return null;
    return subtitles
        .map(
          (item) => Subtitle(
            id: item.id.toInt(),
            lan: item.lan,
            lanDoc: item.lanDoc,
            type: item.type.value,
            subtitleUrl: item.subtitleUrl,
            isAi: item.type == .AI,
          ),
        )
        .toList()
      ..sort();
  }
}
