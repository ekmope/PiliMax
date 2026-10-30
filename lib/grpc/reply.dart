import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliMax/grpc/bilibili/pagination.pb.dart';
import 'package:PiliMax/grpc/grpc_req.dart';
import 'package:PiliMax/grpc/url.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pilimax/utils/filter_pattern_compiler.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/global_data.dart';
import 'package:PiliMax/pilimax/utils/user_whitelist.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:fixnum/fixnum.dart';

abstract final class ReplyGrpc {
  static bool antiGoodsReply = Pref.antiGoodsReply;
  static final _initialFilter = FilterPatternCompiler.compileStoredSafely(
    Pref.banWordForReply,
    onError: (error, stackTrace) => Utils.reportError(
      error,
      stackTrace,
      'ReplyGrpc.invalidStoredPattern',
    ),
  );
  static CompiledFilterPattern replyRegExp = _initialFilter;
  static bool enableFilter = _initialFilter.isEnabled;
  static Map<int, String> replyBlockedMids = Pref.replyBlockedMids;
  static int replyMinLevel = Pref.replyMinLevel;
  static bool keepUpOwnerReply = Pref.keepUpOwnerReply;
  static bool keepUpTopReply = Pref.keepUpTopReply;
  static bool keepUpLikeReply = Pref.keepUpLikeReply;
  static bool keepUpReplyReply = Pref.keepUpReplyReply;
  static bool blockAtOnlyReply = Pref.blockAtOnlyReply;
  static int? blockReplyAtCount = Pref.blockReplyAtCount;

  // static Future replyInfo({required int rpid}) {
  //   return _request(
  //     GrpcUrl.replyInfo,
  //     ReplyInfoReq(rpid: Int64(rpid)),
  //     ReplyInfoReply.fromBuffer,
  //     onSuccess: (response) => response.reply,
  //   );
  // }

  static bool _hasGoods(Url url) =>
      url.hasExtra() &&
      (url.extra.goodsCmControl == Int64.ONE ||
          url.extra.hasGoodsItemId() ||
          url.extra.hasGoodsPrefetchedCache());

  // ref BiliRoamingX
  @pragma('vm:prefer-inline')
  static bool _needRemoveGoodGrpc(ReplyInfo reply) {
    return (reply.content.urls.isNotEmpty &&
            reply.content.urls.values.any(_hasGoods)) ||
        reply.content.message.contains(Constants.goodsUrlPrefix);
  }

  static bool needRemoveGoodGrpc(ReplyInfo reply) => _needRemoveGoodGrpc(reply);

  static bool _isReplyWhitespace(int codeUnit) => switch (codeUnit) {
    0x09 || 0x0A || 0x0B || 0x0C || 0x0D || 0x20 || 0xA0 || 0x1680 => true,
    >= 0x2000 && <= 0x200A ||
    0x2028 ||
    0x2029 ||
    0x202F ||
    0x205F ||
    0x3000 => true,
    _ => false,
  };

  static bool _isAtOnlyReply(ReplyInfo reply) {
    final content = reply.content;
    if (content.atNameToMid.isEmpty ||
        content.emotes.isNotEmpty ||
        content.pictures.isNotEmpty ||
        content.topics.isNotEmpty ||
        content.urls.isNotEmpty ||
        content.hasVote()) {
      return false;
    }

    var message = content.message;
    if (reply.root != reply.parent) {
      final colon = message.indexOf(':');
      if (colon <= 1) return false;
      message = message.substring(colon + 1);
    }

    message = message.trim();
    if (message.isEmpty) return false;

    final names = content.atNameToMid.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    var offset = 0;
    var hasAt = false;
    while (offset < message.length) {
      while (offset < message.length &&
          _isReplyWhitespace(message.codeUnitAt(offset))) {
        offset++;
      }
      if (offset == message.length) break;
      if (message.codeUnitAt(offset) != 0x40) return false;

      offset++;
      String? matchedName;
      for (final name in names) {
        if (name.isEmpty || !message.startsWith(name, offset)) continue;
        final end = offset + name.length;
        if (end == message.length ||
            _isReplyWhitespace(message.codeUnitAt(end)) ||
            message.codeUnitAt(end) == 0x40) {
          matchedName = name;
          break;
        }
      }
      if (matchedName == null) return false;
      offset += matchedName.length;
      hasAt = true;
    }
    return hasAt;
  }

  static bool _shouldBlockByAtCount(ReplyInfo reply) {
    final count = blockReplyAtCount;
    return count != null && reply.content.atNameToMid.length >= count;
  }

  static bool _shouldBlockAtOnly(ReplyInfo reply) =>
      blockAtOnlyReply && _isAtOnlyReply(reply);

  static bool needRemoveGrpc(
    ReplyInfo reply, {
    Int64? upMid,
  }) {
    final mid = reply.mid.toInt();
    if (GlobalData().blackMids.contains(mid)) return true;
    if (replyBlockedMids.isNotEmpty && replyBlockedMids.containsKey(mid)) {
      return true;
    }
    if (UserWhitelist.contains(mid)) return false;
    if (antiGoodsReply && needRemoveGoodGrpc(reply)) return true;
    final replyControl = reply.replyControl;
    if (keepUpOwnerReply && upMid != null && reply.mid == upMid) return false;
    if (keepUpTopReply && replyControl.isUpTop) return false;
    if (keepUpLikeReply && replyControl.upLike) return false;
    if (keepUpReplyReply && replyControl.upReply) return false;
    return _shouldBlockByAtCount(reply) ||
        _shouldBlockAtOnly(reply) ||
        (replyMinLevel > 0 && reply.member.level.toInt() < replyMinLevel) ||
        (enableFilter && replyRegExp.hasMatch(reply.content.message));
  }

  static Future<LoadingState<MainListReply>> mainList({
    required int type,
    required int oid,
    Int64? rpid,
    required Mode mode,
    required String? offset,
    required Int64? cursorNext,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.mainList,
      MainListReq(
        oid: Int64(oid),
        type: Int64(type),
        rpid: rpid,
        // cursor: CursorReq(
        //   mode: mode,
        //   next: cursorNext,
        // ),
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      MainListReply.fromBuffer,
    );
    if (res case Success(:final response)) {
      final upMid = response.subjectControl.upMid;
      // keyword filter
      if (response.hasUpTop() &&
          needRemoveGrpc(
            response.upTop,
            upMid: upMid,
          )) {
        response.clearUpTop();
      }

      if (response.replies.isNotEmpty) {
        response.replies.removeWhere((item) {
          final hasMatch = needRemoveGrpc(
            item,
            upMid: upMid,
          );
          if (!hasMatch && item.replies.isNotEmpty) {
            item.replies.removeWhere((item) {
              return needRemoveGrpc(item, upMid: upMid);
            });
          }
          return hasMatch;
        });
      }
    }
    return res;
  }

  static Future<LoadingState<DetailListReply>> detailList({
    required int type,
    required int oid,
    required int root,
    required int rpid,
    required Mode mode,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.detailList,
      DetailListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        rpid: Int64(rpid),
        scene: DetailListScene.REPLY,
        mode: mode,
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DetailListReply.fromBuffer,
    );
    if (res case Success(:final response)) {
      final upMid = response.subjectControl.upMid;
      response.root.replies.removeWhere((item) {
        return needRemoveGrpc(item, upMid: upMid);
      });
    }
    return res;
  }

  static Future<LoadingState<FoldListResp>> foldList({
    required int type,
    required int oid,
    required FeedPagination pagination,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.foldList,
      FoldListReq(
        oid: Int64(oid),
        type: Int64(type),
        pagination: pagination,
      ),
      FoldListResp.fromBuffer,
    );
    return res..dataOrNull?.replies.removeWhere(needRemoveGrpc);
  }

  static Future<LoadingState<DialogListReply>> dialogList({
    required int type,
    required int oid,
    required int root,
    required int dialog,
    required String? offset,
  }) async {
    final res = await GrpcReq.request(
      GrpcUrl.dialogList,
      DialogListReq(
        oid: Int64(oid),
        type: Int64(type),
        root: Int64(root),
        dialog: Int64(dialog),
        pagination: offset == null ? null : FeedPagination(offset: offset),
      ),
      DialogListReply.fromBuffer,
    );
    if (res case Success(:final response)) {
      final upMid = response.subjectControl.upMid;
      response.replies.removeWhere((item) {
        return needRemoveGrpc(item, upMid: upMid);
      });
    }
    return res;
  }

  static Future<LoadingState<SearchItemReply>> searchItem({
    required int page,
    required SearchItemType itemType,
    required int oid,
    required int type,
    String? keyword,
  }) {
    return GrpcReq.request(
      GrpcUrl.searchItem,
      SearchItemReq(
        cursor: SearchItemCursorReq(
          next: Int64(page),
          itemType: itemType,
        ),
        oid: Int64(oid),
        type: Int64(type),
        keyword: keyword,
      ),
      SearchItemReply.fromBuffer,
    );
  }

  static Future<LoadingState<TranslateReplyResp>> translateReply({
    required Int64 type,
    required Int64 oid,
    required Int64 rpid,
  }) {
    return GrpcReq.request(
      GrpcUrl.translateReply,
      TranslateReplyReq(
        type: type,
        oid: oid,
        rpids: [rpid],
      ),
      TranslateReplyResp.fromBuffer,
    );
  }
}
