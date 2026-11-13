import 'dart:convert';

import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliMax/utils/reply_cache_codec.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

// Old ReplyInfo wire format: id=7, parentReplyMember (tag 100) is a full
// Member(mid=42, name=old, face=avatar, level=6, vipType=2, unknown tag 99).
const _oldWire = <int>[
  0x10,
  0x07,
  0xa2,
  0x06,
  0x18,
  0x08,
  0x2a,
  0x12,
  0x03,
  0x6f,
  0x6c,
  0x64,
  0x22,
  0x06,
  0x61,
  0x76,
  0x61,
  0x74,
  0x61,
  0x72,
  0x28,
  0x06,
  0x38,
  0x02,
  0x9a,
  0x06,
  0x02,
  0x0f,
  0x0e,
];

List<List<int>> _legacyBytes(ReplyInfo reply) =>
    reply.unknownFields.getField(100)!.lengthDelimited;

void main() {
  test(
    'old tag 100 supplies display parent and retains every original byte',
    () {
      final raw = ReplyInfo.fromBuffer(_oldWire);
      expect(raw.hasParentReplyMember(), isFalse);
      final reply = ReplyCacheCodec.fromBuffer(_oldWire);
      expect(reply.id, Int64(7));
      expect(reply.parentReplyMember.mid, Int64(42));
      expect(reply.parentReplyMember.name, 'old');
      expect(_legacyBytes(reply), _legacyBytes(raw));
      final saved = ReplyCacheCodec.fromBuffer(reply.writeToBuffer());
      expect(_legacyBytes(saved), _legacyBytes(raw));
      final member = Member.fromBuffer(_legacyBytes(saved).single);
      expect(member.face, 'avatar');
      expect(member.level, Int64(6));
      expect(member.vipType, Int64(2));
      expect(member.unknownFields.getField(99)!.lengthDelimited.single, [
        15,
        14,
      ]);
    },
  );

  test(
    'JSON export and import preserve binary legacy extras over repeat trips',
    () {
      var reply = ReplyCacheCodec.fromBuffer(_oldWire);
      final original = _legacyBytes(reply).single;
      for (var i = 0; i < 3; i++) {
        final json =
            jsonDecode(jsonEncode(ReplyCacheCodec.toJson(reply))) as Map;
        expect(json['parentReplyMember'], {'mid': '42', 'name': 'old'});
        reply = ReplyCacheCodec.fromJson(json);
        expect(_legacyBytes(reply), [original]);
        expect(reply.parentReplyMember.name, 'old');
      }
    },
  );

  test(
    'old full Member JSON retains fields and nested data, without mutation',
    () {
      final parent = {
        'mid': '42',
        'name': 'old',
        'sex': 'male',
        'face': 'avatar',
        'level': '6',
        'vipType': '2',
        'fansMedalName': 'medal',
        'nftInteraction': {
          'nftId': 'token',
          'region': {'icon': 'badge'},
        },
      };
      final source = {'id': '7', 'parentReplyMember': parent};
      final reply = ReplyCacheCodec.fromJson(source);
      final member = Member.fromBuffer(_legacyBytes(reply).single);
      expect(member.toProto3Json(), parent);
      expect(source['parentReplyMember'], same(parent));
      expect(reply.parentReplyMember.name, 'old');
      final imported = ReplyCacheCodec.fromJson(ReplyCacheCodec.toJson(reply));
      expect(_legacyBytes(imported), _legacyBytes(reply));
      expect(
        Member.fromBuffer(_legacyBytes(imported).single).toProto3Json(),
        parent,
      );
    },
  );

  test(
    'new tag 18 wins while incompatible legacy tag 100 is still preserved',
    () {
      final reply = ReplyInfo.fromBuffer(_oldWire)
        ..parentReplyMember = ParentReplyMember(mid: Int64(99), name: 'new');
      final imported = ReplyCacheCodec.fromBuffer(reply.writeToBuffer());
      expect(imported.parentReplyMember.mid, Int64(99));
      expect(imported.parentReplyMember.name, 'new');
      final jsonImported = ReplyCacheCodec.fromJson(
        ReplyCacheCodec.toJson(imported),
      );
      expect(jsonImported.parentReplyMember.name, 'new');
      expect(_legacyBytes(jsonImported), _legacyBytes(reply));
    },
  );

  test('old nested reply caches also survive binary and JSON imports', () {
    final root = ReplyInfo(
      id: Int64(1),
      replies: [ReplyInfo.fromBuffer(_oldWire)],
    );
    final reply = ReplyCacheCodec.fromBuffer(root.writeToBuffer());
    expect(reply.replies.single.parentReplyMember.name, 'old');
    final imported = ReplyCacheCodec.fromJson(ReplyCacheCodec.toJson(reply));
    expect(imported.replies.single.parentReplyMember.mid, Int64(42));
    expect(
      _legacyBytes(imported.replies.single),
      _legacyBytes(reply.replies.single),
    );
  });

  test(
    'multiple old wire segments retain protobuf merge semantics and bytes',
    () {
      final reply = ReplyInfo.fromBuffer(_oldWire);
      final override = Member(name: 'last').writeToBuffer();
      reply.unknownFields.mergeLengthDelimitedField(100, override);
      final imported = ReplyCacheCodec.fromBuffer(reply.writeToBuffer());
      expect(imported.parentReplyMember.mid, Int64(42));
      expect(imported.parentReplyMember.name, 'last');
      final jsonImported = ReplyCacheCodec.fromJson(
        ReplyCacheCodec.toJson(imported),
      );
      expect(_legacyBytes(jsonImported), _legacyBytes(reply));
    },
  );

  test(
    'normal current JSON and snake case old JSON both remain importable',
    () {
      final current = ReplyCacheCodec.fromJson({
        'id': '8',
        'parentReplyMember': {'mid': '9', 'name': 'current'},
      });
      expect(current.parentReplyMember.name, 'current');
      expect(current.unknownFields.hasField(100), isFalse);
      final old = ReplyCacheCodec.fromJson({
        'id': '7',
        'parent_reply_member': {'mid': '42', 'name': 'old', 'vip_type': '2'},
      });
      expect(Member.fromBuffer(_legacyBytes(old).single).vipType, Int64(2));
    },
  );

  test(
    'cache trimming keeps legacy parent while clearing transient fields',
    () {
      final reply = ReplyCacheCodec.fromBuffer(_oldWire)
        ..trackInfo = 'tracking';
      reply.replies.add(ReplyInfo(id: Int64(3)));
      reply.unknownFields.mergeVarintField(101, Int64(5));
      final cached = ReplyCacheCodec.fromBuffer(
        ReplyCacheCodec.toCacheBuffer(reply, clearReplies: true),
      );
      expect(cached.hasTrackInfo(), isFalse);
      expect(cached.replies, isEmpty);
      expect(cached.unknownFields.hasField(101), isFalse);
      expect(_legacyBytes(cached), _legacyBytes(reply));
      expect(reply.trackInfo, 'tracking');
      expect(reply.replies, hasLength(1));
      expect(reply.unknownFields.hasField(101), isTrue);
    },
  );

  test(
    'malformed legacy JSON fails explicitly instead of silently losing data',
    () {
      expect(
        () => ReplyCacheCodec.fromJson({
          'id': '7',
          '_pilimaxLegacyParentReplyMember100': ['!invalid!'],
        }),
        throwsFormatException,
      );
      expect(
        () => ReplyCacheCodec.fromJson({
          'id': '7',
          'parentReplyMember': {'mid': '42', 'unknownLegacyProperty': 'keep'},
        }),
        throwsFormatException,
      );
    },
  );
}
