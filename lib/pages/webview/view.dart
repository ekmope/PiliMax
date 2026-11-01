import 'dart:async';
import 'dart:io' show Platform;

import 'package:PiliMax/pilimax/forks/common/widgets/flutter/popup_menu.dart';
import 'package:PiliMax/pilimax/common/widgets/selectable_text.dart';
import 'package:PiliMax/common/widgets/route_aware_mixin.dart';
import 'package:PiliMax/http/browser_ua.dart';
import 'package:PiliMax/main.dart';
import 'package:PiliMax/models/common/webview_menu_type.dart';
import 'package:PiliMax/plugin/linux_webview.dart';
import 'package:PiliMax/utils/app_scheme.dart';
import 'package:PiliMax/utils/extension/num_ext.dart';
import 'package:PiliMax/utils/extension/string_ext.dart';
import 'package:PiliMax/utils/linux_cookie_manager.dart';
import 'package:PiliMax/utils/login_utils.dart';
import 'package:PiliMax/utils/page_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart'
    hide WebResourceResponse;

final _prefixRegex = RegExp(r'^(?!(https?://))\S+://', caseSensitive: false);

class WebviewPage extends StatefulWidget {
  const WebviewPage({
    super.key,
    this.url,
    this.oid,
    this.title,
  });

  final String? url;

  // note
  final int? oid;
  final String? title;

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
  LinuxWebViewController? _linuxController;
  late String _linuxCurrentUrl;

  @override
  void initState() {
    super.initState();
    userAgent = switch (Get.parameters['uaType']) {
      'pc' => BrowserUa.pc,
      'mob' => BrowserUa.mob,
      _ => BrowserUa.platform,
    };
    _linuxCurrentUrl = _url;
    if (Get.arguments case final Map map) {
      _inApp = map['inApp'] ?? false;
      _off = map['off'] ?? false;
    }
  }

  @override
  void dispose() {
    _linuxController = null;
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

  /// GtkMenu 创建下拉栏，防止被 WebKitWebView 遮住
  List<Widget> get _linuxActions {
    final entries = <WebviewMenuItem?>[
      ...WebviewMenuItem.values.take(WebviewMenuItem.values.length - 1),
      null,
      WebviewMenuItem.goBack,
    ];
    return [
      _LinuxContextMenuButton(
        items: entries.map((entry) => entry?.title).toList(),
        onSelected: (index) {
          if (entries[index] case final item?) _handleMenuItem(item);
        },
      ),
    ];
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
          _linuxController?.reload();
        } else {
          _webViewController?.reload();
        }
        break;
      case WebviewMenuItem.copy:
        if (Platform.isLinux) {
          Utils.copyText(_linuxCurrentUrl);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            Utils.copyText(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.openInBrowser:
        if (Platform.isLinux) {
          PageUtils.launchURL(_linuxCurrentUrl);
        } else {
          WebUri? uri = await _webViewController?.getUrl();
          if (uri != null) {
            PageUtils.launchURL(uri.toString());
          }
        }
        break;
      case WebviewMenuItem.clearCache:
        try {
          if (Platform.isLinux) {
            await LinuxCookieManager.clearAllWebsiteData();
            _linuxController?.reload();
            SmartDialog.showToast('已清理缓存并刷新', alignment: Alignment.topCenter);
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
          _linuxController?.goBack();
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
          final currentUrl = _linuxCurrentUrl;
          if (LinuxCookieManager.isBiliDomain(currentUrl)) {
            final js = LinuxCookieManager.generateCookieInjectionJs();
            if (js.isNotEmpty) {
              await _linuxController?.runJavaScript(js);
            }
          }
          _linuxController?.reload();
          SmartDialog.showToast(
            '设置成功，正在刷新网页',
            alignment: Alignment.topCenter,
          );
        } else {
          await LoginUtils.setWebCookie();
          SmartDialog.showToast('设置成功，刷新或重新打开网页');
        }
        break;
    }
  }

  List<WebViewUserScript> _getLinuxUserScripts() {
    final shouldInjectCookie = LinuxCookieManager.isBiliDomain(
      _linuxCurrentUrl,
    );
    final cookieJs = shouldInjectCookie
        ? LinuxCookieManager.generateCookieInjectionJs()
        : '';

    return [
      if (cookieJs.isNotEmpty)
        WebViewUserScript(source: cookieJs, forMainFrameOnly: false),
      if (_linuxCurrentUrl.startsWith('https://www.bilibili.com/h5/note-app'))
        const WebViewUserScript(
          source: """
document.addEventListener('click', function(e) {
  var finishBtn = e.target && e.target.closest ? e.target.closest('.finish-btn') : null;
  if (finishBtn) {
    window.PiliMax.postMessage('finishButtonClicked');
    return;
  }
  var infoBar = e.target && e.target.closest ? e.target.closest('.info-bar') : null;
  if (infoBar) {
    window.PiliMax.postMessage('infoBarClicked');
    return;
  }
}, true);
""",
          forMainFrameOnly: false,
        ),
      if (_linuxCurrentUrl.startsWith('https://live.bilibili.com'))
        const WebViewUserScript(
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
          forMainFrameOnly: false,
        ),
    ];
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
            title.value.isNotEmpty ? title.value : _linuxCurrentUrl,
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
        actions: _linuxActions,
      ),
      body: LinuxWebview(
        initialUrl: _linuxCurrentUrl,
        userAgent: userAgent,
        userScripts: _getLinuxUserScripts(),
        onWebViewCreated: (ctr) {
          _linuxController = ctr;
        },
        onUrlChanged: (u) {
          final previousUrl = _linuxCurrentUrl;
          _linuxCurrentUrl = u;
          if (title.value.isEmpty || title.value == previousUrl) {
            title.value = u;
          }
        },
        onTitleChanged: (t) {
          title.value = t;
        },
        onProgress: (p) {
          progress.value = p;
        },
        onWebMessageReceived: (msg) {
          final msgStr = msg.toString();
          if (msgStr == 'finishButtonClicked') {
            if (mounted) Get.back();
          } else if (msgStr == 'infoBarClicked') {
            final uri = Uri.tryParse(_linuxCurrentUrl);
            final targetOid =
                uri?.queryParameters['oid'] ?? widget.oid?.toString();
            if (targetOid != null) {
              PiliScheme.videoPush(int.parse(targetOid), null);
            }
          }
        },
        onNavigationRequest: (request) async {
          final url = request.url;
          final uri = Uri.tryParse(url);
          if (!request.isMainFrame ||
              uri == null ||
              url == _linuxCurrentUrl ||
              const {
                'about',
                'data',
                'blob',
              }.contains(uri.scheme)) {
            return NavigationDecision.navigate;
          }
          if (!_inApp) {
            final handled = await PiliScheme.routePush(
              uri,
              selfHandle: true,
              off: _off,
            );
            if (handled) return NavigationDecision.prevent;
          }
          if (!_prefixRegex.hasMatch(url)) return NavigationDecision.navigate;
          if (mounted) PageUtils.launchURL(url);
          return NavigationDecision.prevent;
        },
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
                            String fileSize = request.contentLength.formatSize;
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

/// Opens a GTK menu above the native WebView.
class _LinuxContextMenuButton extends StatefulWidget {
  const _LinuxContextMenuButton({
    required this.items,
    required this.onSelected,
  });

  final List<String?> items;
  final ValueChanged<int> onSelected;

  @override
  State<_LinuxContextMenuButton> createState() =>
      _LinuxContextMenuButtonState();
}

class _LinuxContextMenuButtonState extends State<_LinuxContextMenuButton> {
  static const _channel = MethodChannel(
    'com.PiliMax.android/linux_context_menu',
  );
  static int _nextRequestId = 0;
  int? _requestId;

  Future<void> _show() async {
    if (_requestId != null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    RenderObject? ancestor = box;
    while (ancestor != null && ancestor is! RenderView) {
      ancestor = ancestor.parent;
    }
    if (ancestor is! RenderView || ancestor.child == null) return;

    // Include app UI scaling without applying the display pixel ratio twice.
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(ancestor.child),
      Offset.zero & box.size,
    );
    final scale =
        ancestor.configuration.devicePixelRatio /
        ancestor.flutterView.devicePixelRatio;
    final requestId = ++_nextRequestId;
    _requestId = requestId;
    final int? index;
    try {
      index = await _channel.invokeMethod<int>('show', {
        'requestId': requestId,
        'items': widget.items,
        'x': rect.left * scale,
        'y': rect.top * scale,
        'width': rect.width * scale,
        'height': rect.height * scale,
      });
    } catch (error) {
      debugPrint('LinuxContextMenu.show failed: $error');
      return;
    } finally {
      _requestId = null;
    }
    if (mounted && index != null && index >= 0 && index < widget.items.length) {
      widget.onSelected(index);
    }
  }

  @override
  void dispose() {
    if (_requestId case final requestId?) {
      unawaited(
        _channel
            .invokeMethod<void>('dismiss', {'requestId': requestId})
            .catchError(
              (Object error) {
                debugPrint('LinuxContextMenu dismiss failed: $error');
              },
            ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.more_vert),
    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
    onPressed: _show,
  );
}
