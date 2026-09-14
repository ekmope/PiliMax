import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 用隐藏 WebView 打开剧集页，按源配置的正则嗅探视频直链。
/// （animeko WebViewVideoExtractor / bv 网页嗅探的 Dart 实现）
class VideoUrlSniffer {
  VideoUrlSniffer._();

  /// [pageUrl] 剧集播放页；[matchVideoUrl] 直链匹配正则；
  /// [matchNestedUrl] 嵌套播放页匹配正则（命中后继续等待跳转）。
  static Future<String?> sniff({
    required String pageUrl,
    String? matchVideoUrl,
    String? matchNestedUrl,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 25),
  }) async {
    if (matchVideoUrl == null || matchVideoUrl.isEmpty) return null;

    final completer = Completer<String?>();
    HeadlessInAppWebView? headless;
    Timer? timeoutTimer;

    Future<void> finish(String? url) async {
      if (completer.isCompleted) return;
      completer.complete(url);
      timeoutTimer?.cancel();
      try {
        await headless?.dispose();
      } catch (_) {}
    }

    timeoutTimer = Timer(timeout, () => finish(null));

    final videoPattern = RegExp(matchVideoUrl);
    final nestedPattern =
        matchNestedUrl != null && matchNestedUrl.isNotEmpty
        ? RegExp(matchNestedUrl)
        : null;

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      supportZoom: false,
      userAgent:
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      incognito: true,
    );

    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(pageUrl),
        headers: headers,
      ),
      initialSettings: settings,
      androidShouldInterceptRequest: (controller, request) async {
        final url = request.url.toString();
        try {
          if (videoPattern.hasMatch(url)) {
            await finish(url);
          }
        } catch (_) {}
        return null;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url.toString();
        // 嵌套播放页放行，其余跳转拦截以加速嗅探
        if (nestedPattern != null && nestedPattern.hasMatch(url)) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onReceivedError: (controller, request, error) {
        // 主文档加载失败直接结束
        if (request.url.toString() == pageUrl) {
          finish(null);
        }
      },
    );

    try {
      await headless.run();
    } catch (_) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) completer.complete(null);
      try {
        await headless.dispose();
      } catch (_) {}
    }

    return completer.future;
  }
}
