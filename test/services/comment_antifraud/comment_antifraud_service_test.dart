import 'dart:collection';

import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/models_new/reply/cursor.dart';
import 'package:PiliMax/models_new/reply/data.dart';
import 'package:PiliMax/models_new/reply/pagination_reply.dart';
import 'package:PiliMax/models_new/reply/reply.dart';
import 'package:PiliMax/models_new/reply2reply/data.dart';
import 'package:PiliMax/models_new/reply2reply/root.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_result.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = CommentAntifraudRequest(
    oid: 100,
    type: 1,
    rpid: 200,
    root: 0,
    parent: 0,
    ctime: 1000,
    uid: 42,
    message: 'test',
    hasPictures: false,
  );

  CommentAntifraudService service(FakeGateway gateway, {int accountMid = 42}) =>
      CommentAntifraudService(
        gateway: gateway,
        accountMid: accountMid,
        isLoggedIn: true,
        delay: (_) async {},
      );

  test('root comment visible to anonymous users is normal', () async {
    final gateway = FakeGateway(
      mainResponses: [
        Success(ReplyData(replies: [ReplyItemModel(rpid: 200)])),
      ],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.normal);
    expect(gateway.replyDetailCalls, isEmpty);
  });

  test('invisible flag is preserved', () async {
    final gateway = FakeGateway(
      mainResponses: [
        Success(
          ReplyData(replies: [ReplyItemModel(rpid: 200, invisible: true)]),
        ),
      ],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.invisible);
  });

  test('root scan follows pagination before classifying', () async {
    final gateway = FakeGateway(
      mainResponses: [
        Success(
          ReplyData(
            replies: [ReplyItemModel(rpid: 1, ctime: 1100)],
            cursor: ReplyCursor(
              isEnd: false,
              paginationReply: PaginationReply(nextOffset: 'next'),
            ),
          ),
        ),
        Success(ReplyData(replies: [ReplyItemModel(rpid: 200, ctime: 1000)])),
      ],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.normal);
    expect(gateway.mainCalls.map((call) => call.offset), ['', 'next']);
  });

  test('login-only root comment is classified as shadow ban', () async {
    final gateway = FakeGateway(
      mainResponses: [Success(ReplyData(replies: const []))],
      replyDetailResponses: [
        Success(ReplyReplyData(root: ReplyRoot(rpid: 200))),
        const Error('评论已删除', code: 12022),
      ],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.shadowBan);
    expect(gateway.replyDetailCalls.map((call) => call.authenticated), [
      true,
      false,
    ]);
  });

  test(
    'detail visible anonymously but absent from list is under review',
    () async {
      final gateway = FakeGateway(
        mainResponses: [Success(ReplyData(replies: const []))],
        replyDetailResponses: [
          Success(ReplyReplyData(root: ReplyRoot(rpid: 200))),
          Success(ReplyReplyData(root: ReplyRoot(rpid: 200))),
        ],
      );

      final result = await service(gateway).check(request);

      expect(result.status, CommentAntifraudStatus.underReview);
    },
  );

  test('authenticated deleted code is classified as deleted', () async {
    final gateway = FakeGateway(
      mainResponses: [Success(ReplyData(replies: const []))],
      replyDetailResponses: [const Error('评论已删除', code: 12022)],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.deleted);
  });

  test('generic API failures never become moderation results', () async {
    final gateway = FakeGateway(
      mainResponses: [const Error('timeout')],
    );

    final result = await service(gateway).check(request);

    expect(result.status, CommentAntifraudStatus.unknown);
    expect(result.detail, contains('不作吞评判断'));
  });

  test(
    'root pagination limit returns unknown instead of a false ban',
    () async {
      final gateway = FakeGateway(
        mainResponses: [
          Success(
            ReplyData(
              replies: [ReplyItemModel(rpid: 1, ctime: 1100)],
              cursor: ReplyCursor(
                isEnd: false,
                paginationReply: PaginationReply(nextOffset: 'next'),
              ),
            ),
          ),
        ],
      );
      final limitedService = CommentAntifraudService(
        gateway: gateway,
        accountMid: 42,
        isLoggedIn: true,
        maxRootPages: 1,
        delay: (_) async {},
      );

      final result = await limitedService.check(request);

      expect(result.status, CommentAntifraudStatus.unknown);
      expect(result.detail, contains('翻页上限'));
      expect(gateway.replyDetailCalls, isEmpty);
    },
  );

  test('reply uses anonymous then authenticated seek_rpid', () async {
    const replyRequest = CommentAntifraudRequest(
      oid: 100,
      type: 1,
      rpid: 201,
      root: 200,
      parent: 200,
      ctime: 1000,
      uid: 42,
      message: 'reply',
      hasPictures: false,
    );
    final gateway = FakeGateway(
      mainResponses: [
        Success(ReplyData(replies: const [])),
        Success(
          ReplyData(
            replies: [
              ReplyItemModel(
                rpid: 200,
                replies: [ReplyItemModel(rpid: 201)],
              ),
            ],
          ),
        ),
      ],
    );

    final result = await service(gateway).check(replyRequest);

    expect(result.status, CommentAntifraudStatus.shadowBan);
    expect(gateway.mainCalls.map((call) => call.authenticated), [false, true]);
    expect(gateway.mainCalls.every((call) => call.seekRpid == 201), isTrue);
  });

  test('reply absent from two successful seek responses is deleted', () async {
    const replyRequest = CommentAntifraudRequest(
      oid: 100,
      type: 1,
      rpid: 201,
      root: 200,
      parent: 200,
      ctime: 1000,
      uid: 42,
      message: 'reply',
      hasPictures: false,
    );
    final gateway = FakeGateway(
      mainResponses: [
        Success(ReplyData(replies: const [])),
        Success(ReplyData(replies: const [])),
      ],
    );

    final result = await service(gateway).check(replyRequest);

    expect(result.status, CommentAntifraudStatus.deleted);
  });

  test('UID mismatch prevents authenticated comparison', () async {
    final gateway = FakeGateway(
      mainResponses: [Success(ReplyData(replies: const []))],
    );

    final result = await service(gateway, accountMid: 99).check(request);

    expect(result.status, CommentAntifraudStatus.unknown);
    expect(result.detail, contains('UID'));
    expect(gateway.replyDetailCalls, isEmpty);
  });
}

class FakeGateway implements CommentAntifraudGateway {
  final Queue<LoadingState<ReplyData>> _mainResponses;
  final Queue<LoadingState<ReplyReplyData>> _replyDetailResponses;
  final List<MainCall> mainCalls = [];
  final List<ReplyDetailCall> replyDetailCalls = [];

  FakeGateway({
    Iterable<LoadingState<ReplyData>> mainResponses = const [],
    Iterable<LoadingState<ReplyReplyData>> replyDetailResponses = const [],
  }) : _mainResponses = Queue.of(mainResponses),
       _replyDetailResponses = Queue.of(replyDetailResponses);

  @override
  Future<LoadingState<ReplyData>> fetchMainPage({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required String offset,
    int? seekRpid,
  }) async {
    mainCalls.add(
      MainCall(
        authenticated: authenticated,
        offset: offset,
        seekRpid: seekRpid,
      ),
    );
    return _mainResponses.removeFirst();
  }

  @override
  Future<LoadingState<ReplyReplyData>> fetchReplyDetail({
    required CommentAntifraudRequest request,
    required bool authenticated,
    required int rootRpid,
  }) async {
    replyDetailCalls.add(
      ReplyDetailCall(authenticated: authenticated, rootRpid: rootRpid),
    );
    return _replyDetailResponses.removeFirst();
  }
}

class MainCall {
  final bool authenticated;
  final String offset;
  final int? seekRpid;

  const MainCall({
    required this.authenticated,
    required this.offset,
    required this.seekRpid,
  });
}

class ReplyDetailCall {
  final bool authenticated;
  final int rootRpid;

  const ReplyDetailCall({
    required this.authenticated,
    required this.rootRpid,
  });
}
