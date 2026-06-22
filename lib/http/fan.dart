import 'package:PiliMax/http/api.dart';
import 'package:PiliMax/http/error_msg.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/follow/data.dart';

abstract final class FanHttp {
  static Future<LoadingState<FollowData>> fans({
    int? vmid,
    int? pn,
    int ps = 20,
    String? orderType,
  }) async {
    final res = await Request().get(
      Api.fans,
      queryParameters: {
        'vmid': vmid,
        'pn': pn,
        'ps': ps,
        'order': 'desc',
        'order_type': orderType,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FollowData.fromJson(res.data['data']));
    } else {
      return Error(errorMsg[res.data['code']] ?? res.data['message']);
    }
  }
}
