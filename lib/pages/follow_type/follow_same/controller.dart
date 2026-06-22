import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/user.dart';
import 'package:PiliMax/models_new/follow/data.dart';
import 'package:PiliMax/pages/follow_type/controller.dart';

class FollowSameController extends FollowTypeController {
  @override
  Future<LoadingState<FollowData>> customGetData() =>
      UserHttp.sameFollowing(mid: mid, pn: page);
}
