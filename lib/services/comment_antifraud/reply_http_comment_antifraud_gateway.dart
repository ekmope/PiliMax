import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/http/reply.dart';
import 'package:PiliMax/models_new/reply/data.dart';
import 'package:PiliMax/models_new/reply2reply/data.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_result.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_service.dart';
import 'package:PiliMax/utils/accounts/account.dart';

class ReplyHttpCommentAntifraudGateway implements CommentAntifraudGateway {
  final Account loginAccount;
  final Account anonymousAccount;

  ReplyHttpCommentAntifraudGateway({
    required this.loginAccount,
    Account? anonymousAccount,
  }) : anonymousAccount = anonymousAccount ?? AnonymousAccount();

  Account _account(bool authenticated) =>
      authenticated ? loginAccount : anonymousAccount;

  @override
  Future<LoadingState<ReplyData>> fetchMainPage({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required String offset,
    int? seekRpid,
  }) => ReplyHttp.antifraudMainPage(
    account: _account(authenticated),
    oid: request.oid,
    type: request.type,
    nextOffset: offset,
    seekRpid: seekRpid,
  );

  @override
  Future<LoadingState<ReplyReplyData>> fetchReplyDetail({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required int rootRpid,
  }) => ReplyHttp.antifraudReplyDetail(
    account: _account(authenticated),
    oid: request.oid,
    type: request.type,
    root: rootRpid,
  );
}
