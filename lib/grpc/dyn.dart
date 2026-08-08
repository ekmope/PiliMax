import 'package:PiliMax/grpc/bilibili/app/dynamic/v1.pb.dart'
    show DynRedReq, DynRedReq_DynRedReqScene, TabOffset, DynRedReply;
import 'package:PiliMax/grpc/bilibili/app/dynamic/v2.pb.dart'
    show OpusType, OpusDetailReq, OpusDetailResp;
import 'package:PiliMax/grpc/grpc_req.dart';
import 'package:PiliMax/grpc/url.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:fixnum/fixnum.dart';

enum DynRedScene { initial, returnToTab1, periodicallyAwake, switchAccount }

abstract final class DynGrpc {
  // static Future dynSpace({
  //   required int uid,
  //   required int page,
  // }) {
  //   return _request(
  //     GrpcUrl.dynSpace,
  //     DynSpaceReq(
  //       hostUid: Int64(uid),
  //       localTime: 8,
  //       page: Int64(page),
  //       from: 'space',
  //     ),
  //     DynSpaceRsp.fromBuffer,
  //   );
  // }

  static Future<int?> dynRed({DynRedScene scene = DynRedScene.initial}) async {
    final requestScene = switch (scene) {
      DynRedScene.initial => DynRedReq_DynRedReqScene.RED_REQ_NONE,
      DynRedScene.returnToTab1 =>
        DynRedReq_DynRedReqScene.RED_REQ_RETURN_TO_TAB_1,
      DynRedScene.periodicallyAwake =>
        DynRedReq_DynRedReqScene.RED_REQ_PERIODICALLY_AWAKE,
      DynRedScene.switchAccount =>
        DynRedReq_DynRedReqScene.RED_REQ_SWITCH_ACCOUNT,
    };
    final res = await GrpcReq.request(
      GrpcUrl.dynRed,
      DynRedReq(
        tabOffset: [TabOffset(tab: 1)],
        reqScene: requestScene,
      ),
      DynRedReply.fromBuffer,
    );
    return res.dataOrNull?.dynRedItem.count.toInt();
  }

  static Future<LoadingState<OpusDetailResp>> opusDetail({
    OpusType? opusType,
    required int oid,
  }) {
    return GrpcReq.request(
      GrpcUrl.opusDetail,
      OpusDetailReq(
        opusType: opusType,
        oid: Int64(oid),
      ),
      OpusDetailResp.fromBuffer,
    );
  }
}
