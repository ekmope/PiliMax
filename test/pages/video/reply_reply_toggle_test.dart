import 'dart:io';

import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/pages/video/reply_reply/controller.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

ReplyInfo _reply(int id) => ReplyInfo(
  id: Int64(id),
  root: Int64(10),
  parent: Int64(10),
  dialog: Int64(id),
);

VideoReplyReplyController _controller(List<ReplyInfo> replies) {
  final controller = VideoReplyReplyController(
    hasRoot: true,
    id: null,
    oid: 1,
    rpid: 10,
    dialog: null,
    replyType: 1,
  );
  addTearDown(controller.onClose);
  controller.loadingState.value = Success(replies);
  controller.buildTree();
  return controller;
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pilimax-reply-tree-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox<dynamic>('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('tree display can be hidden and restored without losing its data', () {
    final reply = _reply(11);
    final controller = _controller([reply]);
    expect(controller.displayedReplyTree?.single.reply, same(reply));

    controller.index.value = 0;
    controller.toggleReplyTree();
    expect(controller.displayedReplyTree, isNull);
    expect(controller.replyTree.rawValue?.single.reply, same(reply));
    expect(controller.index.value, isNull);

    controller.toggleReplyTree();
    expect(controller.displayedReplyTree?.single.reply, same(reply));
  });

  test('restoring tree reflects additions and deletions made in flat mode', () {
    final removed = _reply(11);
    final retained = _reply(12);
    final added = _reply(13);
    final data = [removed, retained];
    final controller = _controller(data)..toggleReplyTree();

    data
      ..removeAt(0)
      ..add(added);
    controller.toggleReplyTree();
    expect(
      controller.displayedReplyTree!.map((node) => node.reply.id),
      [retained.id, added.id],
    );
  });

  for (final busyState in ['page request', 'fetch all']) {
    test('does not build or restore a tree during $busyState', () {
      final original = _reply(11);
      final replacement = _reply(12);
      final controller = _controller([original])..toggleReplyTree();
      controller.loadingState.value = Success([replacement]);
      if (busyState == 'page request') {
        controller.isLoading = true;
      } else {
        controller.isFetchingReplies.value = true;
      }

      controller
        ..toggleReplyTree()
        ..buildTree();
      expect(controller.displayedReplyTree, isNull);
      expect(controller.replyTree.rawValue?.single.reply, same(original));

      controller.isLoading = false;
      controller.isFetchingReplies.value = false;
      controller.toggleReplyTree();
      expect(controller.displayedReplyTree?.single.reply, same(replacement));
    });
  }
}
