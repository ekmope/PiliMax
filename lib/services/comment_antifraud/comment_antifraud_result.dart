import 'package:flutter/foundation.dart' show immutable;

enum CommentAntifraudStatus {
  normal,
  invisible,
  underReview,
  shadowBan,
  deleted,
  unknown,
}

@immutable
class CommentAntifraudRequest {
  final int oid;
  final int type;
  final int rpid;
  final int root;
  final int parent;
  final int ctime;
  final int uid;
  final String message;
  final bool hasPictures;

  const CommentAntifraudRequest({
    required this.oid,
    required this.type,
    required this.rpid,
    required this.root,
    required this.parent,
    required this.ctime,
    required this.uid,
    required this.message,
    required this.hasPictures,
  });

  bool get isRoot => root == 0;
}

@immutable
class CommentAntifraudResult {
  final CommentAntifraudStatus status;
  final String detail;
  final int? apiCode;

  const CommentAntifraudResult(
    this.status,
    this.detail, {
    this.apiCode,
  });

  const CommentAntifraudResult.normal()
    : this(
        CommentAntifraudStatus.normal,
        '无账号状态下可以找到该评论。',
      );

  const CommentAntifraudResult.invisible()
    : this(
        CommentAntifraudStatus.invisible,
        '接口可以获取该评论，但评论被标记为 invisible，前端可能不会展示。',
      );

  const CommentAntifraudResult.underReview()
    : this(
        CommentAntifraudStatus.underReview,
        '无账号评论列表暂时找不到该评论，但仍可通过评论详情获取，疑似审核中。建议稍后复查。',
      );

  const CommentAntifraudResult.shadowBan()
    : this(
        CommentAntifraudStatus.shadowBan,
        '无账号状态下不可见，但当前登录账号仍可找到，高概率为 ShadowBan（仅自己可见）。',
      );

  const CommentAntifraudResult.deleted()
    : this(
        CommentAntifraudStatus.deleted,
        '登录与无账号状态下均无法找到该评论，疑似已被删除。',
      );

  const CommentAntifraudResult.unknown(String detail, {int? apiCode})
    : this(CommentAntifraudStatus.unknown, detail, apiCode: apiCode);

  bool get isProblem => switch (status) {
    CommentAntifraudStatus.shadowBan || CommentAntifraudStatus.deleted => true,
    _ => false,
  };

  bool get isWarning => switch (status) {
    CommentAntifraudStatus.invisible ||
    CommentAntifraudStatus.underReview ||
    CommentAntifraudStatus.unknown => true,
    _ => false,
  };
}
