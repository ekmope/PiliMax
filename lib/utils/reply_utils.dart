import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliMax/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliMax/common/widgets/selectable_text.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_result.dart';
import 'package:PiliMax/services/comment_antifraud/comment_antifraud_service.dart';
import 'package:PiliMax/services/comment_antifraud/reply_http_comment_antifraud_gateway.dart';
import 'package:PiliMax/utils/accounts.dart';
import 'package:PiliMax/utils/android/android_helper.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/id_utils.dart';
import 'package:PiliMax/utils/theme_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

abstract final class ReplyUtils {
  static Future<void> _checkQueue = Future<void>.value();

  static Future<void> onCheckReply({
    required ReplyInfo replyInfo,
    required bool enableCommAntifraud,
    required bool biliSendCommAntifraud,
    required Object? sourceId,
    required bool isManual,
  }) async {
    try {
      final account = Accounts.main;
      final pictures = replyInfo.content.pictures
          .map((item) => item.toProto3Json())
          .toList();
      final request = CommentAntifraudRequest(
        oid: replyInfo.oid.toInt(),
        type: replyInfo.type.toInt(),
        rpid: replyInfo.id.toInt(),
        root: replyInfo.root.toInt(),
        parent: replyInfo.parent.toInt(),
        ctime: replyInfo.ctime.toInt(),
        uid: replyInfo.mid.toInt(),
        message: replyInfo.content.message,
        hasPictures: pictures.isNotEmpty,
      );
      final normalizedSourceId = sourceId?.toString() ?? request.oid.toString();
      final useExternalAutoMode =
          !isManual &&
          !enableCommAntifraud &&
          Platform.isAndroid &&
          biliSendCommAntifraud;

      if (useExternalAutoMode) {
        await _checkReply(
          request: request,
          pictures: pictures,
          accountMid: account.mid,
          accountIsLoggedIn: account.isLogin,
          accountGateway: ReplyHttpCommentAntifraudGateway(
            loginAccount: account,
          ),
          enableCommAntifraud: enableCommAntifraud,
          biliSendCommAntifraud: biliSendCommAntifraud,
          sourceId: normalizedSourceId,
          isManual: isManual,
          waitForProcessing: true,
        );
        return;
      }

      if (!isManual) {
        await Future<void>.delayed(
          request.hasPictures
              ? CommentAntifraudService.defaultPictureProcessingDelay
              : CommentAntifraudService.defaultTextProcessingDelay,
        );
      }

      final task = _checkQueue.then(
        (_) => _checkReply(
          request: request,
          pictures: pictures,
          accountMid: account.mid,
          accountIsLoggedIn: account.isLogin,
          accountGateway: ReplyHttpCommentAntifraudGateway(
            loginAccount: account,
          ),
          enableCommAntifraud: enableCommAntifraud,
          biliSendCommAntifraud: biliSendCommAntifraud,
          sourceId: normalizedSourceId,
          isManual: isManual,
          waitForProcessing: false,
        ),
      );
      _checkQueue = task.catchError((Object _, StackTrace _) {});
      await task;
    } catch (error, stackTrace) {
      Utils.reportError(error, stackTrace);
      SmartDialog.showNotify(
        msg: '评论检查启动失败，本次不作吞评判断。',
        notifyType: .warning,
      );
    }
  }

  static Future<void> _checkReply({
    required CommentAntifraudRequest request,
    required List<Object?> pictures,
    required int accountMid,
    required bool accountIsLoggedIn,
    required CommentAntifraudGateway accountGateway,
    required bool enableCommAntifraud,
    required bool biliSendCommAntifraud,
    required String sourceId,
    required bool isManual,
    required bool waitForProcessing,
  }) async {
    if (!isManual &&
        !enableCommAntifraud &&
        Platform.isAndroid &&
        biliSendCommAntifraud) {
      final launched = PiliAndroidHelper.biliSendCommAntifraud(
        0,
        request.oid,
        request.type,
        request.rpid,
        request.root,
        request.parent,
        request.ctime,
        request.message,
        pictures,
        sourceId,
        request.uid,
      );
      if (launched) {
        return;
      }
      SmartDialog.showToast('外部反诈不可用，已回退到 PiliMax 内部检查');
    }

    final service = CommentAntifraudService(
      gateway: accountGateway,
      accountMid: accountMid,
      isLoggedIn: accountIsLoggedIn,
    );

    late final CommentAntifraudResult result;
    try {
      result = await service.check(
        request,
        waitForProcessing: waitForProcessing,
      );
    } catch (e, s) {
      Utils.reportError(e, s);
      result = const CommentAntifraudResult.unknown(
        '检查过程中发生未预期错误，本次不作吞评判断。',
      );
    }
    _showReplyCheckResult(
      result: result,
      request: request,
      sourceId: sourceId,
      isManual: isManual,
    );
  }

  static void _showReplyCheckResult({
    required CommentAntifraudResult result,
    required CommentAntifraudRequest request,
    required String sourceId,
    required bool isManual,
  }) {
    if (!isManual && result.status == CommentAntifraudStatus.normal) {
      SmartDialog.showToast('评论检查通过：无账号状态下可见');
      return;
    }
    if (!isManual && result.isWarning) {
      SmartDialog.showNotify(
        msg: result.detail,
        notifyType: .warning,
      );
      return;
    }

    final context = Get.context;
    if (context == null) {
      SmartDialog.showNotify(
        msg: result.detail,
        notifyType: result.isProblem ? .failure : .warning,
      );
      return;
    }

    final theme = ThemeUtils.theme;
    final actions = <Widget>[
      if (_canAppeal(result.status))
        TextButton(
          onPressed: () {
            Get.back();
            final uri = switch (request.type) {
              1 => IdUtils.av2bv(request.oid),
              17 => 'https://www.bilibili.com/opus/${request.oid}',
              _ => sourceId,
            };
            if (uri.isNotEmpty) {
              Utils.copyText(uri);
            }
            Get.toNamed(
              '/webview',
              parameters: {
                'url':
                    'https://www.bilibili.com/h5/comment/appeal?${ThemeUtils.themeUrl(theme.isDark)}',
              },
            );
          },
          child: const Text('申诉'),
        ),
      TextButton(
        onPressed: Get.back,
        child: Text(
          '关闭',
          style: TextStyle(color: theme.colorScheme.outline),
        ),
      ),
    ];

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('评论检查结果'),
        content: SingleChildScrollView(
          child: SelectionText(
            '${result.detail}\n\n你的评论：${request.message}',
          ),
        ),
        actions: actions,
      ),
    );
  }

  static bool _canAppeal(CommentAntifraudStatus status) => switch (status) {
    CommentAntifraudStatus.invisible ||
    CommentAntifraudStatus.underReview ||
    CommentAntifraudStatus.shadowBan ||
    CommentAntifraudStatus.deleted => true,
    _ => false,
  };
}
