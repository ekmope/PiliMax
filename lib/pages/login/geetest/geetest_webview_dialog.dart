import 'dart:async' show unawaited;
import 'dart:convert' show base64, jsonDecode, jsonEncode, utf8;
import 'dart:io' show Platform;

import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/http/init.dart';
import 'package:PiliMax/http/loading_state.dart';
import 'package:PiliMax/main.dart';
import 'package:PiliMax/pages/login/geetest/geetest_security.dart';
import 'package:PiliMax/utils/accounts/account.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class GeetestWebviewDialog extends StatefulWidget {
  const GeetestWebviewDialog(this.gt, this.challenge, {super.key});

  final String gt;
  final String challenge;

  @override
  State<GeetestWebviewDialog> createState() => _GeetestWebviewDialogState();

  static Future<Map<String, String>?> geetest(String gt, String challenge) {
    return showDialog<Map<String, String>>(
      context: Get.context!,
      builder: (context) => GeetestWebviewDialog(gt, challenge),
    );
  }
}

class _GeetestWebviewDialogState extends State<GeetestWebviewDialog> {
  static const _geetestJsUri =
      'https://static.geetest.com/static/js/fullpage.0.0.0.js';
  static const _contentSecurityPolicy =
      "default-src 'none'; "
      "script-src 'unsafe-inline' 'unsafe-eval' https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com; "
      "connect-src https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com; "
      "img-src data: https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com; "
      "style-src 'unsafe-inline' https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com; "
      "font-src https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com; "
      "frame-src https://geetest.com https://*.geetest.com https://geevisit.com https://*.geevisit.com";

  late final Future<LoadingState<String>> _future;
  Webview? _linuxWebview;
  late bool _linuxWebviewLoading = true;
  bool _completed = false;
  bool _scriptStarted = false;

  static String _showJs(String response) =>
      't=Geetest($response).onSuccess(()=>R("success",t.getValidate())).onError(o=>R("error",o)).onClose(o=>R("close",o));t.onReady(()=>t.verify())';

  @override
  void initState() {
    super.initState();
    _future = _getConfig(widget.gt, widget.challenge);
    if (Platform.isLinux) {
      unawaited(_initLinuxWebview());
    }
  }

  static Future<LoadingState<String>> _getConfig(
    String gt,
    String challenge,
  ) async {
    if (!GeetestSecurity.isValidBootstrapToken(gt) ||
        !GeetestSecurity.isValidBootstrapToken(challenge)) {
      return const Error('极验参数无效');
    }
    try {
      final res = await Request().get<String>(
        'https://api.geetest.com/gettype.php',
        queryParameters: {'gt': gt},
        options: Options(
          responseType: ResponseType.plain,
          extra: {'account': const NoAccount()},
        ),
      );
      final data = res.data;
      if (data == null ||
          data.length > GeetestSecurity.maxConfigResponseLength ||
          !data.startsWith('(') ||
          !data.endsWith(')')) {
        return const Error('极验配置响应无效');
      }

      final Object? decoded;
      try {
        decoded = jsonDecode(data.substring(1, data.length - 1));
      } on FormatException {
        return const Error('极验配置 JSON 无效');
      }
      if (decoded is! Map<String, dynamic> ||
          decoded['status'] != 'success' ||
          decoded['data'] is! Map) {
        return const Error('极验配置加载失败');
      }
      final config = Map<String, dynamic>.from(decoded['data'] as Map)
        ..addAll({
          'gt': gt,
          'challenge': challenge,
          'offline': false,
          'new_captcha': true,
          'product': 'bind',
          'width': '100%',
          'https': true,
          'protocol': 'https://',
        });
      return Success(jsonEncode(config));
    } catch (error) {
      debugPrint('geetest config request failed: ${error.runtimeType}');
      return const Error('极验配置请求失败');
    }
  }

  Future<void> _initLinuxWebview() async {
    try {
      final config = await _future;
      if (!mounted || _completed) {
        return;
      }
      if (config case Error()) {
        _finish(errorMessage: config.toString());
        return;
      }
      final response = (config as Success<String>).response;

      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          windowWidth: 300,
          windowHeight: 400,
          title: '验证码',
        ),
      );
      if (!mounted || _completed) {
        webview.close();
        return;
      }
      _linuxWebview = webview
        ..setOnUrlRequestCallback(
          (url) => GeetestSecurity.isAllowedRemoteUri(Uri.tryParse(url)),
        )
        ..addOnWebMessageReceivedCallback(_handleLinuxMessage);
      unawaited(webview.onClose.whenComplete(_finish));

      final html = _buildHtml(
        bridge:
            "(n,o)=>webkit.messageHandlers.msgToNative.postMessage(n+':'+JSON.stringify(o))",
        response: response,
      );
      webview.launch(
        'data:text/html;base64,${base64.encode(utf8.encode(html))}',
        triggerOnUrlRequestEvent: false,
      );

      if (mounted && !_completed) {
        setState(() => _linuxWebviewLoading = false);
      }
    } catch (error) {
      debugPrint('geetest linux webview failed: ${error.runtimeType}');
      _finish(errorMessage: '验证码窗口加载失败');
    }
  }

  static String _buildHtml({
    required String bridge,
    String? response,
  }) =>
      '''
<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width">
<meta http-equiv="Content-Security-Policy" content="$_contentSecurityPolicy">
</head><body>
<script src="$_geetestJsUri"></script>
<script>R=$bridge;${response == null ? '' : _showJs(response)}</script>
</body></html>
''';

  void _handleLinuxMessage(String message) {
    if (_completed) {
      return;
    }
    if (message.length > GeetestSecurity.maxLinuxMessageLength) {
      _finish(errorMessage: '验证码返回数据过大');
      return;
    }
    if (message.startsWith('success:')) {
      try {
        final result = GeetestSecurity.decodeLinuxResult(
          message.substring('success:'.length),
          expectedChallenge: widget.challenge,
        );
        _finish(result: result);
      } on GeetestValidationException catch (error) {
        debugPrint('geetest invalid result: $error');
        _finish(errorMessage: '验证码返回结果无效');
      }
    } else if (message.startsWith('error:')) {
      debugPrint('geetest reported an error');
      _finish(errorMessage: '验证码校验失败');
    } else if (message.startsWith('close:')) {
      _finish();
    } else {
      _finish(errorMessage: '验证码回调无效');
    }
  }

  void _handleResult(Object? value) {
    if (_completed) {
      return;
    }
    try {
      final result = GeetestSecurity.validateResult(
        value,
        expectedChallenge: widget.challenge,
      );
      _finish(result: result);
    } on GeetestValidationException catch (error) {
      debugPrint('geetest invalid result: $error');
      _finish(errorMessage: '验证码返回结果无效');
    }
  }

  void _finish({
    Map<String, String>? result,
    String? errorMessage,
  }) {
    if (_completed) {
      return;
    }
    _completed = true;
    if (errorMessage?.isNotEmpty == true) {
      SmartDialog.showToast(errorMessage!);
    }
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  void _closeLinuxWebview() {
    final webview = _linuxWebview;
    _linuxWebview = null;
    webview?.close();
  }

  @override
  void dispose() {
    _completed = true;
    _closeLinuxWebview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return AlertDialog(
        title: const Text('验证码'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Center(
            child: _linuxWebviewLoading
                ? const CircularProgressIndicator()
                : const Text('请在弹出的新窗口中完成验证'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _finish,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            clearCache: true,
            javaScriptEnabled: true,
            forceDark: ForceDark.AUTO,
            useHybridComposition: false,
            algorithmicDarkeningAllowed: true,
            useShouldOverrideUrlLoading: true,
            useShouldInterceptRequest: true,
            userAgent: BrowserUa.mob,
            mixedContentMode: .MIXED_CONTENT_NEVER_ALLOW,

            incognito: true,
            allowFileAccess: false,
            allowsLinkPreview: false,
            allowContentAccess: false,
            useOnDownloadStart: false,
            geolocationEnabled: false,
            thirdPartyCookiesEnabled: false,
            enterpriseAuthenticationAppLinkPolicyEnabled: false,
            saveFormData: false,
            safeBrowsingEnabled: true,
            isFraudulentWebsiteWarningEnabled: true,
            upgradeKnownHostsToHTTPS: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
            allowFileAccessFromFileURLs: false,
            allowUniversalAccessFromFileURLs: false,
            domStorageEnabled: false,
            databaseEnabled: false,
            cacheEnabled: false,
            cacheMode: .LOAD_NO_CACHE,

            horizontalScrollBarEnabled: false,
            verticalScrollBarEnabled: false,
            overScrollMode: .NEVER,

            pageZoom: Platform.isIOS ? 3 : 1,
          ),
          initialData: InAppWebViewInitialData(
            data: _buildHtml(bridge: 'flutter_inappwebview.callHandler'),
            baseUrl: WebUri('https://static.geetest.com/'),
          ),
          onWebViewCreated: (ctr) {
            ctr
              ..addJavaScriptHandler(
                handlerName: 'success',
                callback: (args) {
                  if (_completed) {
                    return;
                  }
                  _handleResult(args.isEmpty ? null : args.first);
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'error',
                callback: (args) {
                  if (_completed) {
                    return;
                  }
                  debugPrint('geetest reported an error');
                  _finish(errorMessage: '验证码校验失败');
                },
              )
              ..addJavaScriptHandler(
                handlerName: 'close',
                callback: (args) {
                  if (!_completed) {
                    _finish();
                  }
                },
              );
          },
          shouldOverrideUrlLoading: (_, navigationAction) async {
            final uri = navigationAction.request.url?.uriValue;
            return GeetestSecurity.isAllowedRemoteUri(uri)
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          },
          shouldInterceptRequest: (_, request) async {
            return GeetestSecurity.isAllowedRemoteUri(request.url.uriValue)
                ? null
                : WebResourceResponse();
          },
          onLoadStop: (ctr, url) async {
            if (_completed || _scriptStarted) {
              return;
            }
            if (!GeetestSecurity.isAllowedRemoteUri(url?.uriValue)) {
              _finish(errorMessage: '验证码页面地址无效');
              return;
            }
            final config = await _future;
            if (!mounted || _completed || _scriptStarted) return;
            if (config case Success(:final response)) {
              _scriptStarted = true;
              await ctr.evaluateJavascript(source: _showJs(response));
            } else {
              _finish(errorMessage: config.toString());
            }
          },
        ),
        Positioned(
          left: 8,
          top: 8,
          child: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _finish,
            tooltip: '关闭',
          ),
        ),
      ],
    );
  }
}
