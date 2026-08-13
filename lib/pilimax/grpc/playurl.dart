import 'package:PiliMax/grpc/bilibili/app/playurl/v1.pb.dart';
import 'package:PiliMax/grpc/grpc_req.dart';
import 'package:PiliMax/grpc/url.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/accounts/grpc_headers.dart';
import 'package:fixnum/fixnum.dart';

abstract final class PlayUrlGrpc {
  static PlayViewReq buildPlayViewRequest({
    required int aid,
    required int cid,
    int qn = 80,
    bool voiceBalance = false,
  }) => PlayViewReq(
    aid: Int64(aid),
    cid: Int64(cid),
    qn: Int64(qn),
    fnver: 0,
    fnval: 4048,
    download: 0,
    forceHost: 2,
    fourk: true,
    spmid: 'main.ugc-video-detail.0.0',
    fromSpmid: 'main.ugc-video-detail.0.0',
    teenagersMode: 0,
    preferCodecType: CodeType.NOCODE,
    business: Business.UNKNOWN,
    voiceBalance: Int64(voiceBalance ? 1 : 0),
  );

  static Future<LoadingState<PlayViewReply>> playView({
    required int aid,
    required int cid,
    int qn = 80,
    bool voiceBalance = false,
  }) {
    final account = Accounts.video;
    return GrpcReq.request(
      GrpcUrl.playView,
      buildPlayViewRequest(
        aid: aid,
        cid: cid,
        qn: qn,
        voiceBalance: voiceBalance,
      ),
      PlayViewReply.fromBuffer,
      account: account,
      grpcHeaders: GrpcHeaders.newAppHeaders(account.accessKey, account.mid),
      transportPolicy: GrpcTransportPolicy.primaryThenHttp11,
    );
  }
}
