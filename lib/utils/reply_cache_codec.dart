import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show Member, ParentReplyMember, ReplyInfo;
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// Compatibility at the local cache boundary, separate from the wire schema.
abstract final class ReplyCacheCodec {
  static const _legacyParentTag = 100;

  // Proto3 JSON omits unknown fields. Keep each original field-100 payload so
  // exports also retain Member fields that the new parent schema cannot hold.
  static const _legacyParentJsonKey = '_pilimaxLegacyParentReplyMember100';

  static ReplyInfo fromBuffer(List<int> bytes) {
    final reply = ReplyInfo.fromBuffer(bytes);
    _restoreParent(reply);
    return reply;
  }

  static Map<String, dynamic> toJson(ReplyInfo reply) {
    final json = Map<String, dynamic>.from(reply.toProto3Json() as Map);
    final legacy = _legacyParents(reply);
    if (legacy.isNotEmpty) {
      json[_legacyParentJsonKey] = legacy.map(base64Encode).toList();
    }
    if (reply.replies.isNotEmpty) {
      json['replies'] = reply.replies.map(toJson).toList();
    }
    return json;
  }

  static ReplyInfo fromJson(Map source) {
    final json = Map<String, dynamic>.from(source);
    final legacyBytes = json.remove(_legacyParentJsonKey);
    final children = json.remove('replies');
    if (json.containsKey('parentReplyMember') &&
        json.containsKey('parent_reply_member')) {
      throw const FormatException('Duplicate parent reply member fields');
    }
    final parentKey = json.containsKey('parentReplyMember')
        ? 'parentReplyMember'
        : 'parent_reply_member';
    final parent = json[parentKey];
    Member? legacyParent;
    if (parent is Map &&
        parent.keys.any((key) => key != 'mid' && key != 'name')) {
      // Old exports used a complete Member under the same JSON field name.
      // Parse it strictly rather than silently discarding its extra fields.
      legacyParent = Member()..mergeFromProto3Json(parent);
      json[parentKey] = {
        if (legacyParent.hasMid()) 'mid': legacyParent.mid.toString(),
        if (legacyParent.hasName()) 'name': legacyParent.name,
      };
    }
    final reply = ReplyInfo()..mergeFromProto3Json(json);
    if (legacyBytes != null) {
      if (legacyBytes is! List) {
        throw const FormatException('Invalid legacy parent cache data');
      }
      for (final bytes in legacyBytes) {
        if (bytes is! String) {
          throw const FormatException('Invalid legacy parent cache payload');
        }
        reply.unknownFields.mergeLengthDelimitedField(
          _legacyParentTag,
          base64Decode(bytes),
        );
      }
    }
    if (legacyParent != null) {
      reply.unknownFields.mergeLengthDelimitedField(
        _legacyParentTag,
        legacyParent.writeToBuffer(),
      );
    }
    if (children != null) {
      if (children is! List || children.any((child) => child is! Map)) {
        throw const FormatException('Invalid cached reply children');
      }
      reply.replies.addAll(children.cast<Map>().map(fromJson));
    }
    _restoreParent(reply);
    return reply;
  }

  /// Keep the existing cache trimming, without deleting the legacy parent.
  static Uint8List toCacheBuffer(
    ReplyInfo reply, {
    bool clearReplies = false,
  }) {
    final cached = reply.deepCopy();
    final legacy = _legacyParents(cached).toList();
    cached.unknownFields.clear();
    for (final bytes in legacy) {
      cached.unknownFields.mergeLengthDelimitedField(_legacyParentTag, bytes);
    }
    cached.clearTrackInfo();
    if (clearReplies) cached.replies.clear();
    return cached.writeToBuffer();
  }

  static List<List<int>> _legacyParents(ReplyInfo reply) =>
      reply.unknownFields.getField(_legacyParentTag)?.lengthDelimited ??
      const [];

  static void _restoreParent(ReplyInfo reply) {
    final legacy = _legacyParents(reply);
    if (!reply.hasParentReplyMember() && legacy.isNotEmpty) {
      final member = Member();
      for (final bytes in legacy) {
        member.mergeFromBuffer(bytes);
      }
      reply.parentReplyMember = ParentReplyMember(
        mid: member.hasMid() ? member.mid : null,
        name: member.hasName() ? member.name : null,
      );
    }
    for (final child in reply.replies) {
      _restoreParent(child);
    }
  }
}
