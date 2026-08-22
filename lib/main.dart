import 'dart:async';
import 'dart:io';

import 'package:PiliMax/build_config.dart';
import 'package:PiliMax/common/constants.dart';
import 'package:PiliMax/common/widgets/back_detector.dart';
import 'package:PiliMax/common/widgets/custom_toast.dart';
import 'package:PiliMax/common/widgets/route_aware_mixin.dart';
import 'package:PiliMax/common/widgets/scale_app.dart';
import 'package:PiliMax/common/widgets/scroll_behavior.dart';
import 'package:PiliMax/pilimax/forks/http/init.dart';
import 'package:PiliMax/models/common/theme/theme_color_type.dart';
import 'package:PiliMax/pilimax/pages/storage_recovery/view.dart';
import 'package:PiliMax/pilimax/pages/setting/pages/crash_report.dart';
import 'package:PiliMax/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliMax/router/app_pages.dart';
import 'package:PiliMax/services/account_service.dart';
import 'package:PiliMax/pilimax/services/crash/crash_breadcrumbs.dart';
import 'package:PiliMax/pilimax/services/crash/crash_context.dart';
import 'package:PiliMax/pilimax/services/crash/crash_report.dart';
import 'package:PiliMax/pilimax/services/crash/crash_report_handler.dart';
import 'package:PiliMax/pilimax/services/crash/crash_reporter.dart';
import 'package:PiliMax/pilimax/services/download/download_collection_service.dart';
import 'package:PiliMax/services/download/download_service.dart';
import 'package:PiliMax/services/logger.dart';
import 'package:PiliMax/pilimax/services/route_restore_service.dart';
import 'package:PiliMax/services/service_locator.dart';
import 'package:PiliMax/pilimax/utils/app_font.dart';
import 'package:PiliMax/pilimax/utils/android/android_mmkv_box.dart';
import 'package:PiliMax/pilimax/utils/android/android_mmkv_recovery.dart';
import 'package:PiliMax/pilimax/forks/utils/accounts.dart';
import 'package:PiliMax/utils/cache_manager.dart';
import 'package:PiliMax/utils/calc_window_position.dart';
import 'package:PiliMax/pilimax/utils/danmaku_font.dart';
import 'package:PiliMax/utils/date_utils.dart';
import 'package:PiliMax/utils/extension/core_palettes_ext.dart';
import 'package:PiliMax/utils/extension/theme_ext.dart';
import 'package:PiliMax/utils/json_file_handler.dart';
import 'package:PiliMax/utils/max_screen_size.dart';
import 'package:PiliMax/utils/path_utils.dart';
import 'package:PiliMax/utils/platform_utils.dart';
import 'package:PiliMax/utils/request_utils.dart';
import 'package:PiliMax/pilimax/forks/utils/storage.dart';
import 'package:PiliMax/utils/storage_key.dart';
import 'package:PiliMax/utils/storage_pref.dart';
import 'package:PiliMax/utils/theme_utils.dart';
import 'package:PiliMax/utils/utils.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:dynamic_color/dynamic_color.dart' show DynamicColorPlugin;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:window_manager/window_manager.dart' hide calcWindowPosition;

WebViewEnvironment? webViewEnvironment;

EdgeInsets? tmpPadding;

Future<void> _initDownPath() async {
  if (PlatformUtils.isDesktop) {
    final customDownPath = Pref.downloadPath;
    if (customDownPath != null && customDownPath.isNotEmpty) {
      try {
        final dir = Directory(customDownPath);
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
        downloadPath = customDownPath;
      } catch (e) {
        downloadPath = defDownloadPath;
        await GStorage.setting.delete(SettingBoxKey.downloadPath);
        if (kDebugMode) {
          debugPrint('download path error: $e');
        }
      }
    } else {
      downloadPath = defDownloadPath;
    }
  } else if (Platform.isAndroid) {
    final externalStorageDirPath = (await getExternalStorageDirectory())?.path;
    downloadPath = externalStorageDirPath != null
        ? path.join(externalStorageDirPath, PathUtils.downloadDir)
        : defDownloadPath;
  } else {
    downloadPath = defDownloadPath;
  }
}

Future<void> _initTmpPath() async {
  final systemTemporaryDirectory = await getTemporaryDirectory();
  final appTemporaryDirectory = Directory(
    path.join(systemTemporaryDirectory.path, PathUtils.temporaryRootDir),
  );
  await appTemporaryDirectory.create(recursive: true);
  tmpDirPath = appTemporaryDirectory.path;
}

Future<void> _initAppPath() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory(path.join(appData, Constants.appName));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      appSupportDirPath = dir.path;
      return;
    }
  }

  appSupportDirPath = (await getApplicationSupportDirectory()).path;
}

void main() {
  var startupCompleted = false;
  runZonedGuarded(
    () async {
      CrashReporter.install();
      await _main();
      startupCompleted = true;
    },
    (error, stackTrace) {
      CrashReporter.recordErrorSync(
        error,
        stackTrace,
        source: CrashSource.platformDispatcher,
        severity: startupCompleted
            ? CrashSeverity.unhandled
            : CrashSeverity.fatal,
        operation: 'mainZone',
        reason: 'uncaught_zone_error',
      );
      if (!startupCompleted) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      try {
        // Keep Catcher2's existing JSON/console handlers in the chain for
        // errors which reach the outer zone after startup.
        Catcher2.reportCheckedError(error, stackTrace);
      } catch (_) {
        // A reporting failure must never become a second uncaught error.
      }
    },
  );
}

Future<void> _main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized();
  final startupCrashReport = await CrashReporter.ensureInitialized();
  await _initAppPath();
  CrashBreadcrumbs.record('main.start');
  MediaKit.ensureInitialized();
  try {
    await GStorage.init();
  } on AndroidMmkvMigrationException catch (e, stackTrace) {
    CrashReporter.recordErrorSync(
      e,
      stackTrace,
      severity: CrashSeverity.fatal,
      operation: 'GStorage.init',
      reason: 'android_mmkv_migration_failed',
    );
    final recoveryController = AndroidMmkvRecoveryController(
      failure: e,
      retryStorage: GStorage.init,
      resetStorage: (failure) async {
        await GStorage.backupAndResetAndroidMmkvFailure(failure);
      },
      closeApplication: () => exit(0),
      reportCallbackError: (error, stackTrace, operation) {
        final reason = switch (error) {
          AndroidMmkvMigrationException(:final code) => code,
          AndroidMmkvRecoveryException(:final code) => code,
          _ => 'unexpected_callback_failure',
        };
        CrashReporter.recordErrorSync(
          StateError('Storage recovery callback failed'),
          stackTrace,
          severity: CrashSeverity.handled,
          operation: 'GStorage.recovery.$operation',
          reason: reason,
        );
      },
    );
    runApp(AndroidMmkvRecoveryApp(controller: recoveryController));
    await recoveryController.recovered;
  } catch (e, stackTrace) {
    CrashReporter.recordErrorSync(
      e,
      stackTrace,
      severity: CrashSeverity.fatal,
      operation: 'GStorage.init',
      reason: 'startup_storage_initialization_failed',
    );
    await Utils.copyText(e.toString());
    if (kDebugMode) debugPrint('GStorage init error: $e');
    exit(0);
  }
  CrashBreadcrumbs.record('GStorage initialized');
  await AppFont.init();
  await DanmakuFont.init();
  ScaledWidgetsFlutterBinding.instance.scaleFactor = Pref.uiScale;
  await Future.wait([
    _initDownPath(),
    _initTmpPath(),
    CacheManager.ensureInitialized(),
  ]);
  Get
    ..lazyPut(AccountService.new)
    ..lazyPut(DownloadCollectionService.new)
    ..lazyPut(DownloadService.new);
  HttpOverrides.global = _CustomHttpOverrides();

  if (PlatformUtils.isMobile) {
    if (Platform.isAndroid) MaxScreenSize.init();
    await Future.wait([
      if (Pref.horizontalScreen) ?fullMode() else ?portraitUpMode(),
      setupServiceLocator(),
    ]);
  } else if (Platform.isWindows) {
    if (await WebViewEnvironment.getAvailableVersion() != null) {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: path.join(appSupportDirPath, 'flutter_inappwebview'),
        ),
      );
    }
    await setupServiceLocator();
  } else if (Platform.isMacOS) {
    await setupServiceLocator();
  }

  Request();
  await Request.setCookie();
  unawaited(
    RequestUtils.syncHistoryStatus().catchError(
      (Object error, StackTrace stackTrace) {
        CrashReporter.recordErrorSync(
          StateError(
            'Startup history status sync failed (${error.runtimeType})',
          ),
          stackTrace,
          severity: CrashSeverity.handled,
          operation: 'RequestUtils.syncHistoryStatus',
          reason: 'startup_sync_failed',
        );
      },
    ),
  );
  unawaited(CacheManager.clearExpiredCache());

  SmartDialog.config.toast = SmartConfigToast(displayType: .onlyRefresh);

  // ESC 全平台注册：平板/手机外接键盘也可用（PageRoute 默认不消费 escape）
  FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);

  if (PlatformUtils.isMobile) {
    SystemChrome.setEnabledSystemUIMode(.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (Platform.isAndroid) {
      FlutterDisplayMode.supported.then((mode) {
        final String? storageDisplay = GStorage.setting.get(
          SettingBoxKey.displayMode,
          defaultValue: '#1 1264x2780 @ 120Hz',
        );
        DisplayMode? displayMode;
        if (storageDisplay != null) {
          displayMode = mode.firstWhereOrNull(
            (e) => e.toString() == storageDisplay,
          );
        }
        FlutterDisplayMode.setPreferredMode(displayMode ?? DisplayMode.auto);
      });
    } else {
      ScreenBrightnessPlatform.instance.setAutoReset(false);
    }
  } else if (PlatformUtils.isDesktop) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      minimumSize: const Size(400, 720),
      skipTaskbar: false,
      titleBarStyle: Pref.showWindowTitleBar
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      title: Constants.appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      final windowSize = Pref.windowSize;
      await windowManager.setBounds(
        await calcWindowPosition(windowSize) & windowSize,
      );
      if (Pref.isWindowMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  if (Pref.dynamicColor) {
    await MyApp.initPlatformState();
  }

  if (Pref.enableLog) {
    // 异常捕获 logo记录
    final customParameters = {
      'Build Time': DateFormatUtils.format(
        BuildConfig.buildTime,
        format: DateFormatUtils.longFormatDs,
      ),
      'Commit Hash': BuildConfig.commitHash,
      'MPV Api Version':
          '${NativePlayer.apiVersion >> 16}.${NativePlayer.apiVersion & 0xFFFF}',
    };
    final fileHandler = await JsonFileHandler.init();

    Catcher2(
      [?fileHandler, CrashReportHandler(), const ConsoleHandler()],
      MyApp(startupCrashReport: startupCrashReport),
      logger: logger,
      customParameters: customParameters,
      excludedParameters: const [
        'id',
        'androidId',
        'machineId',
        'computerName',
        'hostName',
        'fingerprint',
        'name',
      ],
    );
    // Catcher2 installs its own Flutter handler. Re-chain CrashReporter after it
    // so both the existing JSON logs and the bounded crash archive are retained.
    CrashReporter.install(force: true);
  } else {
    runApp(MyApp(startupCrashReport: startupCrashReport));
  }
}

KeyEventResult _onKeyEvent(KeyEvent event) {
  if (event.logicalKey == .escape && event is KeyDownEvent) {
    _onBack();
    return .handled;
  }
  return .ignored;
}

void _onBack() {
  if (SmartDialog.checkExist()) {
    SmartDialog.dismiss();
    return;
  }

  final route = Get.routing.route;
  if (route is GetPageRoute) {
    if (route.popDisposition == .doNotPop) {
      route.onPopInvokedWithResult(false, null);
      return;
    }
  }

  final navigator = Get.key.currentState!;
  if (navigator.canPop()) {
    navigator.pop();
  }
}

class MyApp extends StatelessWidget {
  final CrashReport? startupCrashReport;

  const MyApp({this.startupCrashReport, super.key});

  static ColorScheme? _light, _dark;

  static (ThemeData, ThemeData) getAllTheme() {
    final dynamicColor = _light != null && _dark != null && Pref.dynamicColor;
    late final brandColor = colorThemeTypes[Pref.customColor].color;
    late final variant = Pref.schemeVariant;
    return (
      ThemeUtils.lightTheme = ThemeUtils.getThemeData(
        colorScheme: dynamicColor
            ? _light!
            : brandColor.asColorSchemeSeed(variant, .light),
        isDynamic: dynamicColor,
      ),
      ThemeUtils.darkTheme = ThemeUtils.getThemeData(
        isDark: true,
        colorScheme: dynamicColor
            ? _dark!
            : brandColor.asColorSchemeSeed(variant, .dark),
        isDynamic: dynamicColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (light, dark) = getAllTheme();
    return _AccountReauthenticationNotice(
      required: Accounts.reauthenticationRequired,
      child: GetMaterialApp(
        title: Constants.appName,
        theme: light,
        darkTheme: dark,
        themeMode: ThemeUtils.themeMode = Pref.themeMode,
        localizationsDelegates: const [
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        locale: const Locale("zh", "CN"),
        fallbackLocale: const Locale("zh", "CN"),
        supportedLocales: const [Locale("zh", "CN"), Locale("en", "US")],
        initialRoute: '/',
        getPages: Routes.getPages,
        routingCallback: RouteRestoreService.onRouteChanged,
        defaultTransition: Pref.effectivePageTransition,
        builder: FlutterSmartDialog.init(
          toastBuilder: CustomToast.new,
          loadingBuilder: LoadingWidget.new,
          notifyStyle: const FlutterSmartNotifyStyle(
            warningBuilder: NotifyWarning.new,
          ),
          builder: (context, child) =>
              _builder(context, child, startupCrashReport),
        ),
        navigatorObservers: [
          routeObserver,
          CrashBreadcrumbNavigatorObserver(),
          FlutterSmartDialog.observer,
        ],
        scrollBehavior: PlatformUtils.isDesktop
            ? const CustomScrollBehavior()
            : null,
      ),
    );
  }

  // 修复后的 Builder 方法
  static Widget _builder(
    BuildContext context,
    Widget? child,
    CrashReport? startupCrashReport,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final uiScale = Pref.uiScale;
    final textScaler = TextScaler.linear(Pref.defaultTextScale);

    // --- Fix for Flutter SDK bug on HyperOS windowed mode (Android only) ---
    // https://github.com/flutter/flutter/issues/164092
    // https://github.com/flutter/flutter/issues/161086
    EdgeInsets effectiveViewPadding = mediaQuery.viewPadding;
    EdgeInsets effectivePadding = mediaQuery.padding;

    if (Platform.isAndroid) {
      // Fallback padding values based on typical Android status/navigation bar heights
      const fallbackPadding = EdgeInsets.only(top: 25, bottom: 35);

      // Threshold for detecting abnormal padding:
      // - Normal status bars are typically 20-48 dp
      // - Values > 50 indicate the Flutter SDK bug on HyperOS windowed mode
      // - Values == 0 are valid in fullscreen/immersive mode
      // - Check both top AND bottom to avoid misdetecting during orientation changes
      const maxNormalPadding = 50.0;

      final hasAbnormalPadding =
          mediaQuery.viewPadding.top > maxNormalPadding &&
          mediaQuery.viewPadding.bottom > maxNormalPadding;

      if (hasAbnormalPadding) {
        effectiveViewPadding = fallbackPadding;
        effectivePadding = fallbackPadding;
      }
    }
    // -----------------------------------------------------------------------

    if (uiScale != 1.0) {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          size: mediaQuery.size / uiScale,
          padding: tmpPadding ?? mediaQuery.padding / uiScale,
          viewInsets: mediaQuery.viewInsets / uiScale,
          viewPadding: tmpPadding ?? mediaQuery.viewPadding / uiScale,
          devicePixelRatio: mediaQuery.devicePixelRatio * uiScale,
        ),
        child: child!,
      );
    } else {
      child = MediaQuery(
        data: mediaQuery.copyWith(
          textScaler: textScaler,
          padding: tmpPadding ?? effectivePadding,
          viewPadding: tmpPadding ?? effectiveViewPadding,
        ),
        child: child!,
      );
    }
    child = BackDetector(
      onBack: _onBack,
      child: child,
    );
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        debugPrint(
          '[PiliMax-PB] NavigationNotification canHandlePop=${notification.canHandlePop}',
        );
        return false;
      },
      child: CrashReportStartupGate(
        initialReport: startupCrashReport,
        child: child,
      ),
    );
  }

  /// from [DynamicColorBuilderState.initPlatformState]
  static Future<bool> initPlatformState() async {
    if (_light != null || _dark != null) return true;
    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      final colors = await DynamicColorPlugin.channel.invokeMethod(
        DynamicColorPlugin.methodName,
      );

      if (colors != null) {
        final corePalettes = CorePalettesExt.fromList(colors.toList());
        if (kDebugMode) {
          debugPrint('dynamic_color: Core palette detected.');
        }
        _light = corePalettes.toColorScheme();
        _dark = corePalettes.toColorScheme(brightness: Brightness.dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain core palette.');
      }
    }

    try {
      final Color? accentColor = await DynamicColorPlugin.getAccentColor();

      if (accentColor != null) {
        if (kDebugMode) {
          debugPrint('dynamic_color: Accent color detected.');
        }
        final variant = Pref.schemeVariant;
        _light = accentColor.asColorSchemeSeed(variant, .light);
        _dark = accentColor.asColorSchemeSeed(variant, .dark);
        return true;
      }
    } on PlatformException {
      if (kDebugMode) {
        debugPrint('dynamic_color: Failed to obtain accent color.');
      }
    }
    if (kDebugMode) {
      debugPrint('dynamic_color: Dynamic color not detected on this device.');
    }
    GStorage.setting.put(SettingBoxKey.dynamicColor, false);
    return false;
  }
}

final class _AccountReauthenticationNotice extends StatefulWidget {
  final bool required;
  final Widget child;

  const _AccountReauthenticationNotice({
    required this.required,
    required this.child,
  });

  @override
  State<_AccountReauthenticationNotice> createState() =>
      _AccountReauthenticationNoticeState();
}

final class _AccountReauthenticationNoticeState
    extends State<_AccountReauthenticationNotice> {
  @override
  void initState() {
    super.initState();
    if (widget.required) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          SmartDialog.showToast('账号安全密钥已失效，请重新登录');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // ..maxConnectionsPerHost = 32
    /// The default value is 15 seconds.
    //   ..idleTimeout = const Duration(seconds: 15);
    if (kDebugMode || Pref.badCertificateCallback) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }
}
