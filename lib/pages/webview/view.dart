import 'dart:io';

import 'package:PiliMax/pilimax/forks/common/widgets/flutter/popup_menu.dart';
import 'package:PiliMax/pilimax/common/widgets/selectable_text.dart';
import 'package:PiliMax/common/widgets/route_aware_mixin.dart';
import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/main.dart';
import 'package:PiliMax/models/common/enum_with_label.dart';
import 'package:PiliMax/models/common/webview_menu_type.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/cache_manager.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/linux_cookie_manager.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart' as dww;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

final _prefixRegex = RegExp(r'^(?!(https?://))\S+://', caseSensitive: false);

enum _DWWState implements EnumWithLabel {
  active('已在新窗口中打开'),
  loading('正在启动窗口'),
  closed('窗口已关闭'),
  none(''),
  ;

  @override
  final String label;
  const _DWWState(this.label);
}

class WebviewPage extends StatefulWidget {
  const WebviewPage({
    super.key,
    this.url,
    this.oid,
    this.title,
    this.userAgent,
  });

  final String? url;

  // note
  final int? oid;
  final String? title;
  final String? userAgent;

  static Future<dww.Webview?> openLinux({
    required String url,
    String? title,
    int? oid,
    bool inApp = false,
    bool off = false,
    VoidCallback? onClose,
    VoidCallback? onFinish,
  }) async {
    if (!Platform.isLinux) return null;
    final shouldInjectCookie = LinuxCookieManager.isBiliDomain(url);
    final cookieJs = shouldInjectCookie
        ? LinuxCookieManager.generateCookieInjectionJs()
        : '';

    final userScripts = <dww.UserScript>[
      if (cookieJs.isNotEmpty)
        dww.UserScript(
          source: cookieJs,
          injectionTime: dww.UserScriptInjectionTime.documentStart,
          forAllFrames: true,
        ),
      if (url.startsWith('https://www.bilibili.com/h5/note-app'))
        const dww.UserScript(
          source: """
document.addEventListener('click', function(e) {
  var finishBtn = e.target && e.target.closest ? e.target.closest('.finish-btn') : null;
  if (finishBtn) {
    window.webkit.messageHandlers.msgToNative.postMessage('finishButtonClicked');
    return;
  }
  var infoBar = e.target && e.target.closest ? e.target.closest('.info-bar') : null;
  if (infoBar) {
    window.webkit.messageHandlers.msgToNative.postMessage('infoBarClicked');
    return;
  }
}, true);
""",
          injectionTime: dww.UserScriptInjectionTime.documentEnd,
          forAllFrames: true,
        ),
      if (url.startsWith('https://live.bilibili.com'))
        const dww.UserScript(
          source: """
(function() {
  function injectStyle() {
    if (document.getElementById('pili-live-style')) return;
    var s = document.createElement('style');
    s.id = 'pili-live-style';
    s.textContent = 'div.open-app-btn.bili-btn-warp {display:none !important;} #app__display-area > div.control-panel {display:none !important;}';
    (document.head || document.documentElement).appendChild(s);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', injectStyle);
  } else {
    injectStyle();
  }
})();
""",
          injectionTime: dww.UserScriptInjectionTime.documentStart,
          forAllFrames: true,
        ),
    ];

    var closeNotified = false;
    void notifyClose() {
      if (closeNotified) return;
      closeNotified = true;
      onClose?.call();
    }

    try {
      final webview = await dww.WebviewWindow.create(
        configuration: dww.CreateConfiguration(
          windowWidth: 1080,
          windowHeight: 760,
          title: title ?? url,
          userScripts: userScripts,
        ),
      );

      webview
        ..setOnUrlRequestCallback((u) {
          if (u == url) {
            return false;
          }
          final uri = Uri.tryParse(u);
          final isCustomScheme = _prefixRegex.hasMatch(u);

          if (!inApp && uri != null) {
            PiliScheme.routePush(uri, selfHandle: true, off: off).then((
              hasMatch,
            ) {
              if (!hasMatch && isCustomScheme) {
                PageUtils.launchURL(u);
              }
            });
            if (isCustomScheme) {
              return true;
            }
          } else if (isCustomScheme) {
            PageUtils.launchURL(u);
            return true;
          }
          return false;
        })
        ..addOnWebMessageReceivedCallback((msg) {
          final msgStr = msg.toString();
          if (msgStr == 'finishButtonClicked') {
            if (onFinish != null) {
              onFinish();
            } else {
              webview.close();
            }
          } else if (msgStr == 'infoBarClicked') {
            final uri = Uri.tryParse(url);
            final targetOid = uri?.queryParameters['oid'] ?? oid?.toString();
            final parsedOid = int.tryParse(targetOid ?? '');
            if (parsedOid != null) {
              PiliScheme.videoPush(parsedOid, null);
            }
          }
        });

      webview.onClose.whenComplete(notifyClose);

      webview.launch(url);
      return webview;
    } catch (e) {
      if (kDebugMode) debugPrint('Linux Webview open error: $e');
      SmartDialog.showToast('无法启动网页窗口: $e');
      return null;
    }
  }

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage>
    with RouteAware, RouteAwareMixin {
  late final String _url =
      (widget.url ?? Get.parameters['url'])?.http2https ?? '';
  late final String userAgent;
  final RxString title = ''.obs;
  final RxDouble progress = 1.0.obs;
  bool _inApp = false;
  bool _off = false;
  bool _isPopping = false;

  InAppWebViewController? _webViewController;

  dww.Webview? _linuxWebview;
  late final Rx<_DWWState> _dwwState = Rx(.none);
  bool _linuxCloseRequested = false;

  @override
  void initState() {
    super.initState();
    userAgent =
        widget.userAgent ??
        switch (Get.parameters['uaType']) {
          'pc' => BrowserUa.pc,
          'mob' => BrowserUa.mob,
          _ => BrowserUa.platform,
        };
    if (Get.arguments case final Map map) {
      _inApp = map['inApp'] ?? false;
      _off = map['off'] ?? false;
    }
    if (Platform.isLinux) _initLinuxWebview();
  }

  @override
  void dispose() {
    if (Platform.isLinux) _closeLinuxWebview();
    _webViewController = null;
    super.dispose();
  }

  @override
  void didPop() {
    if (Platform.isAndroid) {
      if (mounted) {
        setState(() {
          _webViewController = null;
          _isPopping = true;
        });
      } else {
        _webViewController = null;
        _isPopping = true;
      }
    }
    super.didPop();
  }

  void _closeLinuxWebview({bool close = true}) {
    if (close) {
      _linuxCloseRequested = true;
      _linuxWebview?.close();
    }
    _linuxWebview = null;
    _dwwState.value = .closed;
  }

  Future<void> _initLinuxWebview() async {
    _dwwState.value = .loading;

    var webview = await WebviewPage.openLinux(
      url: _url,
      title: widget.title ?? title.value,
      oid: widget.oid,
      inApp: _inApp,
      off: _off,
      onFinish: () {
        if (mounted) Get.back();
      },
      onClose: () {
        final shouldPop = !_linuxCloseRequested;
        _linuxCloseRequested = false;
        _closeLinuxWebview(close: false);
        if (shouldPop && mounted) Get.back();
      },
    );

    if (!mounted) {
      webview?.close();
      webview = null;
      return;
    }

    _linuxWebview = webview;
    _dwwState.value = webview != null ? .active : .closed;
  }

  List<Widget> get _actions {
    return [
      StaticPopupMenuButton<WebviewMenuItem>(
        onSelected: _handleMenuItem,
        itemBuilder: (context) => <PopupMenuEntry<WebviewMenuItem>>[
          ...WebviewMenuItem.values
              .take(WebviewMenuItem.values.length - 1)
              .map(
                (item) => PopupMenuItem(
                  value: item,
                  child: Text(item.title),
                ),
              ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: WebviewMenuItem.goBack,
            child: Text(
              WebviewMenuItem.goBack.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _handleMenuItem(WebviewMenuItem item) async {
    switch (item) {
      case WebviewMenuItem.refresh:
        if (Platform.isLinux) {
          _linuxWebview?.reload();
        } else {
          _webViewController?.reload();
        }
        break;
      case WebviewMenuItem.copy:
        if (Platform.isLinux) {
          Utils.copyText(_url);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            Utils.copyText(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.openInBrowser:
        if (Platform.isLinux) {
          PageUtils.launchURL(_url);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            PageUtils.launchURL(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.clearCache:
        try {
          // desktop_webview_window 的 clearAll 方法会销毁所有 GTK 窗口
          if (Platform.isLinux) {
            await LinuxCookieManager.deleteAllCookies();
            _closeLinuxWebview();
            SmartDialog.showToast('已清理缓存并关闭窗口');
            if (mounted) {
              Get.back();
            }
          } else {
            await InAppWebViewController.clearAllCache();
            await _webViewController?.clearHistory();
            SmartDialog.showToast('已清理');
          }
        } catch (e) {
          SmartDialog.showToast(e.toString());
        }
        break;
      case WebviewMenuItem.goBack:
        if (Platform.isLinux) {
          _linuxWebview?.back();
        } else {
          if (await _webViewController?.canGoBack() == true) {
            _webViewController?.goBack();
          } else {
            Get.back();
          }
        }
        break;
      case WebviewMenuItem.resetCookie:
        if (Platform.isLinux) {
          if (LinuxCookieManager.isBiliDomain(_url)) {
            final js = LinuxCookieManager.generateCookieInjectionJs();
            if (js.isNotEmpty) {
              await _linuxWebview?.evaluateJavaScript(js);
            }
          }
          _linuxWebview?.reload();
        } else {
          await LoginUtils.setWebCookie();
        }
        SmartDialog.showToast('设置成功，刷新或重新打开网页');
        break;
    }
  }

  Widget _buildLinuxView(BuildContext context) {
    // 记笔记页
    if (widget.url != null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: Obx(
          () => Text(
            title.value.isNotEmpty ? title.value : _url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: _actions,
      ),
      body: Center(
        child: Obx(
          () => Text(
            _dwwState.value.label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isLinux) {
      return _buildLinuxView(context);
    }
    return Scaffold(
      appBar: widget.url != null
          ? null
          : AppBar(
              title: Obx(
                () => Text(
                  title.value.isNotEmpty ? title.value : _url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: Size.zero,
                child: Obx(
                  () => progress.value < 1
                      ? LinearProgressIndicator(value: progress.value)
                      : const SizedBox.shrink(),
                ),
              ),
              actions: _isPopping ? null : _actions,
            ),
      body: _isPopping
          ? null
          : SafeArea(
              child: InAppWebView(
                webViewEnvironment: webViewEnvironment,
                initialSettings: InAppWebViewSettings(
                  clearCache: true,
                  javaScriptEnabled: true,
                  forceDark: ForceDark.AUTO,
                  useHybridComposition: false,
                  algorithmicDarkeningAllowed: true,
                  useShouldOverrideUrlLoading: true,
                  userAgent: userAgent,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                ),
                initialUrlRequest: URLRequest(
                  url: WebUri.uri(Uri.tryParse(_url) ?? Uri()),
                ),
                onWebViewCreated: (InAppWebViewController controller) {
                  _webViewController = controller;
                  controller
                    ..addJavaScriptHandler(
                      handlerName: 'finishButtonClicked',
                      callback: (args) {
                        Get.back();
                      },
                    )
                    ..addJavaScriptHandler(
                      handlerName: 'infoBarClicked',
                      callback: (args) async {
                        WebUri? uri = await controller.getUrl();
                        if (uri != null) {
                          String? oid = uri.queryParameters['oid'];
                          if (oid != null) {
                            PiliScheme.videoPush(int.parse(oid), null);
                          }
                        }
                      },
                    );
                },
                onProgressChanged: (controller, progress) {
                  this.progress.value = progress / 100;
                },
                onTitleChanged: (controller, title) {
                  this.title.value = title ?? '';
                },
                onCloseWindow: (controller) => Get.back(),
                onLoadStop: (controller, uri) {
                  final url = uri.toString();
                  if (url.startsWith('https://www.bilibili.com/h5/note-app')) {
                    controller
                      ..evaluateJavascript(
                        source: """
  document.querySelector('.finish-btn').addEventListener('click', function() {
      window.flutter_inappwebview.callHandler('finishButtonClicked');
  });
""",
                      )
                      ..evaluateJavascript(
                        source: """
  document.querySelector('.info-bar').addEventListener('click', function() {
      window.flutter_inappwebview.callHandler('infoBarClicked');
  });
""",
                      );
                  } else if (url.startsWith('https://live.bilibili.com')) {
                    controller.evaluateJavascript(
                      source: '''
                  document.styleSheets[0].insertRule('div.open-app-btn.bili-btn-warp {display:none;}', 0);
                  document.styleSheets[0].insertRule('#app__display-area > div.control-panel {display:none;}', 0);
                  ''',
                    );
                  }
                  // _webViewController?.evaluateJavascript(
                  //   source: '''
                  //     document.querySelector('#internationalHeader').remove();
                  //     document.querySelector('#message-navbar').remove();
                  //   ''',
                  // );
                },
                onDownloadStartRequest: Platform.isAndroid
                    ? (controller, request) {
                        showDialog(
                          context: context,
                          builder: (context) {
                            String suggestedFilename = request.suggestedFilename
                                .toString();
                            String fileSize = CacheManager.formatSize(
                              request.contentLength.toDouble(),
                            );
                            try {
                              suggestedFilename = Uri.decodeComponent(
                                suggestedFilename,
                              );
                            } catch (e) {
                              if (kDebugMode) debugPrint(e.toString());
                            }
                            return AlertDialog(
                              title: Text(
                                '下载文件: $suggestedFilename ?',
                                style: const TextStyle(fontSize: 18),
                              ),
                              content: SelectionText(request.url.toString()),
                              actions: [
                                TextButton(
                                  onPressed: Get.back,
                                  child: Text(
                                    '取消',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Get.back();
                                    PageUtils.launchURL(request.url.toString());
                                  },
                                  child: Text('确定 ($fileSize)'),
                                ),
                              ],
                            );
                          },
                        );
                        progress.value = 1;
                      }
                    : null,
                shouldInterceptAjaxRequest: (controller, ajaxRequest) async {
                  String url = ajaxRequest.url.toString();
                  if (url.startsWith('//api.bilibili.com/x/note/add') &&
                      widget.title != null) {
                    return ajaxRequest
                      ..data = ajaxRequest.data.toString().replaceFirst(
                        '&title=--&',
                        '&title=${widget.title}&',
                      );
                  }
                  return null;
                },
                shouldInterceptRequest: (controller, request) async {
                  String url = request.url.toString();
                  if (url.startsWith(
                    'https://passport.bilibili.com/x/passport-login/web',
                  )) {
                    progress.value = 1;
                    return WebResourceResponse();
                  }
                  return null;
                },
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  if (!_inApp) {
                    final hasMatch = await PiliScheme.routePush(
                      navigationAction.request.url?.uriValue ?? Uri(),
                      selfHandle: true,
                      off: _off,
                    );
                    // if (kDebugMode) debugPrint('webview: [$url], [$hasMatch]');
                    if (hasMatch) {
                      progress.value = 1;
                      return .CANCEL;
                    }
                  }
                  final url = navigationAction.request.url.toString();
                  if (_prefixRegex.hasMatch(url)) {
                    if (context.mounted) {
                      final snackBar = SnackBar(
                        persist: false,
                        showCloseIcon: true,
                        content: const Text('当前网页将要打开外部链接，是否打开'),
                        action: SnackBarAction(
                          label: '打开',
                          onPressed: () => PageUtils.launchURL(url),
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(snackBar);
                    }
                    progress.value = 1;
                    return .CANCEL;
                  }

                  return .ALLOW;
                },
              ),
            ),
    );
  }
}
