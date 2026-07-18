import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/reply/data.dart';
import 'package:PiliMax/models_new/reply/reply.dart';
import 'package:PiliMax/models_new/reply2reply/data.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_result.dart';

abstract interface class CommentAntifraudGateway {
  Future<LoadingState<ReplyData>> fetchMainPage({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required String offset,
    int? seekRpid,
  });

  Future<LoadingState<ReplyReplyData>> fetchReplyDetail({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required int rootRpid,
  });
}

class CommentAntifraudService {
  static const defaultTextProcessingDelay = Duration(seconds: 5);
  static const defaultPictureProcessingDelay = Duration(seconds: 20);
  static const defaultMaxRootPages = 30;

  final CommentAntifraudGateway gateway;
  final int accountMid;
  final bool isLoggedIn;
  final Duration textProcessingDelay;
  final Duration pictureProcessingDelay;
  final int maxRootPages;
  final Future<void> Function(Duration duration) delay;

  const CommentAntifraudService({
    required this.gateway,
    required this.accountMid,
    required this.isLoggedIn,
    this.textProcessingDelay = defaultTextProcessingDelay,
    this.pictureProcessingDelay = defaultPictureProcessingDelay,
    this.maxRootPages = defaultMaxRootPages,
    this.delay = Future<void>.delayed,
  }) : assert(maxRootPages > 0);

  Future<CommentAntifraudResult> check(
    CommentAntifraudRequest request, {
    bool waitForProcessing = true,
  }) async {
    if (waitForProcessing) {
      await delay(
        request.hasPictures ? pictureProcessingDelay : textProcessingDelay,
      );
    }

    return request.isRoot ? _checkRoot(request) : _checkReply(request);
  }

  Future<CommentAntifraudResult> _checkRoot(
    CommentAntifraudRequest request,
  ) async {
    var offset = '';
    var completedAnonymousScan = false;

    for (var page = 0; page < maxRootPages; page++) {
      final response = await gateway.fetchMainPage(
        request: request,
        authenticated: false,
        offset: offset,
      );
      if (response case Error()) {
        return _unknownFromError(response, '获取无账号评论列表失败');
      }

      final data = response.data;
      final found = _findReply(data, request.rpid);
      if (found != null) {
        return found.invisible == true
            ? const CommentAntifraudResult.invisible()
            : const CommentAntifraudResult.normal();
      }

      final replies = data.replies ?? const <ReplyItemModel>[];
      final reachedSentTime = replies.any(
        (reply) => reply.ctime != null && reply.ctime! < request.ctime,
      );
      final nextOffset = data.cursor?.paginationReply?.nextOffset;
      final reachedEnd =
          data.cursor?.isEnd == true ||
          nextOffset == null ||
          nextOffset.isEmpty ||
          nextOffset == offset;

      if (reachedSentTime || reachedEnd) {
        completedAnonymousScan = true;
        break;
      }
      offset = nextOffset;
    }

    if (!completedAnonymousScan) {
      return const CommentAntifraudResult.unknown(
        '无账号评论列表已达到安全翻页上限，暂时无法判断评论状态。',
      );
    }

    final accountProblem = _accountProblem(request);
    if (accountProblem != null) {
      return accountProblem;
    }

    final authenticated = await gateway.fetchReplyDetail(
      request: request,
      authenticated: true,
      rootRpid: request.rpid,
    );
    if (authenticated case Error()) {
      if (_isCommentDeleted(authenticated)) {
        return const CommentAntifraudResult.deleted();
      }
      return _unknownFromError(authenticated, '登录状态下获取评论详情失败');
    }
    if (authenticated.data.root?.rpid != request.rpid) {
      return const CommentAntifraudResult.unknown(
        '登录状态下的评论详情缺少目标评论，暂时无法判断。',
      );
    }

    final anonymous = await gateway.fetchReplyDetail(
      request: request,
      authenticated: false,
      rootRpid: request.rpid,
    );
    if (anonymous case Error()) {
      if (_isCommentDeleted(anonymous)) {
        return const CommentAntifraudResult.shadowBan();
      }
      return _unknownFromError(anonymous, '无账号状态下获取评论详情失败');
    }

    final anonymousRoot = anonymous.data.root;
    if (anonymousRoot?.rpid != request.rpid) {
      return const CommentAntifraudResult.unknown(
        '无账号状态下的评论详情缺少目标评论，暂时无法判断。',
      );
    }
    return anonymousRoot?.invisible == true
        ? const CommentAntifraudResult.invisible()
        : const CommentAntifraudResult.underReview();
  }

  Future<CommentAntifraudResult> _checkReply(
    CommentAntifraudRequest request,
  ) async {
    final anonymous = await gateway.fetchMainPage(
      request: request,
      authenticated: false,
      offset: '',
      seekRpid: request.rpid,
    );
    if (anonymous case Error()) {
      return _unknownFromError(anonymous, '无账号状态下定位回复失败');
    }

    final anonymousReply = _findReply(anonymous.data, request.rpid);
    if (anonymousReply != null) {
      return anonymousReply.invisible == true
          ? const CommentAntifraudResult.invisible()
          : const CommentAntifraudResult.normal();
    }

    final accountProblem = _accountProblem(request);
    if (accountProblem != null) {
      return accountProblem;
    }

    final authenticated = await gateway.fetchMainPage(
      request: request,
      authenticated: true,
      offset: '',
      seekRpid: request.rpid,
    );
    if (authenticated case Error()) {
      return _unknownFromError(authenticated, '登录状态下定位回复失败');
    }

    final authenticatedReply = _findReply(authenticated.data, request.rpid);
    if (authenticatedReply != null) {
      return authenticatedReply.invisible == true
          ? const CommentAntifraudResult.invisible()
          : const CommentAntifraudResult.shadowBan();
    }
    return const CommentAntifraudResult.deleted();
  }

  CommentAntifraudResult? _accountProblem(
    CommentAntifraudRequest request,
  ) {
    if (!isLoggedIn) {
      return const CommentAntifraudResult.unknown(
        '当前没有可用的登录账号，只能确认游客可见的评论。',
      );
    }
    if (request.uid != 0 && request.uid != accountMid) {
      return CommentAntifraudResult.unknown(
        '评论发布者 UID（${request.uid}）与检查账号 UID（$accountMid）不一致，无法进行登录态对照。',
      );
    }
    return null;
  }

  static ReplyItemModel? _findReply(ReplyData data, int rpid) {
    final items = <ReplyItemModel>[
      ...?data.topReplies,
      ...?data.replies,
    ];
    for (final item in items) {
      final found = _findReplyTree(item, rpid);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static ReplyItemModel? _findReplyTree(ReplyItemModel item, int rpid) {
    if (item.rpid == rpid) {
      return item;
    }
    for (final child in item.replies ?? const <ReplyItemModel>[]) {
      final found = _findReplyTree(child, rpid);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static bool _isCommentDeleted(Error error) => error.code == 12022;

  static CommentAntifraudResult _unknownFromError(
    Error error,
    String operation,
  ) {
    final code = error.code;
    final reason = switch (code) {
      -101 => '登录状态已失效',
      -352 || -412 => '请求被风控或限流',
      12002 => '评论区已关闭或不可用',
      _ =>
        error.errMsg?.trim().isNotEmpty == true
            ? error.errMsg!.trim()
            : '未知接口错误',
    };
    return CommentAntifraudResult.unknown(
      '$operation：$reason${code == null ? '' : '（$code）'}。本次不作吞评判断。',
      apiCode: code,
    );
  }
}
