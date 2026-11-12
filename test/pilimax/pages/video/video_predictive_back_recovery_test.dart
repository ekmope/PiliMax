import 'package:PiliMax/pilimax/pages/video/video_detail_back_progress.dart';
import 'package:PiliMax/pilimax/pages/video/video_page_transitions_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingStartRoute extends MaterialPageRoute<void> {
  _ThrowingStartRoute(Map<String, dynamic> arguments)
    : super(
        settings: RouteSettings(name: '/videoV', arguments: arguments),
        builder: (_) => const Scaffold(body: Text('video')),
      );

  bool throwBeforeStart = false;

  @override
  void handleStartBackGesture({double progress = 0}) {
    if (throwBeforeStart) {
      throwBeforeStart = false;
      throw StateError('route start failed');
    }
    super.handleStartBackGesture(progress: progress);
  }
}

class _ThrowingGestureObserver extends NavigatorObserver {
  bool throwOnNextStart = false;
  int stops = 0;

  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    if (throwOnNextStart) {
      throwOnNextStart = false;
      throw StateError('observer start failed');
    }
  }

  @override
  void didStopUserGesture() {
    stops++;
  }
}

Future<void> _sendBackEvent(
  WidgetTester tester,
  String method, {
  double progress = 0.25,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        method == 'startBackGesture'
            ? <String, dynamic>{
                'touchOffset': <double>[5, 300],
                'progress': progress,
                'swipeEdge': 0,
              }
            : null,
      ),
    ),
    (_) {},
  );
}

Future<void> _showVideo(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
  NavigatorObserver observer,
  _ThrowingStartRoute route,
) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [observer],
      theme: ThemeData(
        platform: TargetPlatform.android,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: AppPredictiveBackPageTransitionsBuilder(),
          },
        ),
      ),
      home: const Scaffold(body: Text('home')),
    ),
  );
  navigatorKey.currentState!.push(route);
  await tester.pumpAndSettle();
}

void main() {
  for (final throwFromObserver in [false, true]) {
    testWidgets(
      'recovers a failed ${throwFromObserver ? 'observer' : 'route'} start '
      'and permits subsequent cancel and commit',
      (tester) async {
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _ThrowingGestureObserver();
        final arguments = <String, dynamic>{};
        final route = _ThrowingStartRoute(arguments);
        final errors = <FlutterErrorDetails>[];

        await _showVideo(tester, navigatorKey, observer, route);

        if (throwFromObserver) {
          observer.throwOnNextStart = true;
        } else {
          route.throwBeforeStart = true;
        }
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = errors.add;
        try {
          await _sendBackEvent(tester, 'startBackGesture');
        } finally {
          FlutterError.onError = previousErrorHandler;
        }
        await tester.pumpAndSettle();

        expect(errors, hasLength(1));
        expect(
          errors.single.exception.toString(),
          contains(
            throwFromObserver ? 'observer start failed' : 'route start failed',
          ),
        );
        expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
        expect(observer.stops, throwFromObserver ? 1 : 0);
        expect(route.animation!.value, 1);
        final backProgress =
            arguments[videoDetailBackProgressKey] as VideoDetailBackProgress;
        expect(backProgress.value, const VideoDetailBackSnapshot.idle());

        await _sendBackEvent(tester, 'startBackGesture');
        await tester.pump();
        expect(navigatorKey.currentState!.userGestureInProgress, isTrue);
        expect(backProgress.value.phase, VideoDetailBackPhase.predicting);
        expect(backProgress.value.exitProgress, 0.25);
        await _sendBackEvent(tester, 'cancelBackGesture');
        await tester.pumpAndSettle();
        expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
        expect(backProgress.value, const VideoDetailBackSnapshot.idle());
        expect(find.text('video'), findsOneWidget);

        await _sendBackEvent(tester, 'startBackGesture');
        await tester.pump();
        await _sendBackEvent(tester, 'commitBackGesture');
        await tester.pumpAndSettle();
        expect(navigatorKey.currentState!.userGestureInProgress, isFalse);
        expect(find.text('home'), findsOneWidget);
        expect(find.text('video'), findsNothing);
        expect(errors, hasLength(1));
      },
    );
  }

  testWidgets('does not acquire or stop an existing Navigator gesture', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final observer = _ThrowingGestureObserver();
    final arguments = <String, dynamic>{};
    final route = _ThrowingStartRoute(arguments);
    await _showVideo(tester, navigatorKey, observer, route);

    final navigator = navigatorKey.currentState!..didStartUserGesture();
    await _sendBackEvent(tester, 'startBackGesture');
    await tester.pump();
    expect(navigator.userGestureInProgress, isTrue);
    expect(observer.stops, 0);
    expect(route.animation!.value, 1);
    final backProgress =
        arguments[videoDetailBackProgressKey] as VideoDetailBackProgress;
    expect(backProgress.value, const VideoDetailBackSnapshot.idle());

    navigator.didStopUserGesture();
    await _sendBackEvent(tester, 'startBackGesture');
    await tester.pump();
    expect(backProgress.value.phase, VideoDetailBackPhase.predicting);
    await _sendBackEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(navigator.userGestureInProgress, isFalse);
    expect(backProgress.value, const VideoDetailBackSnapshot.idle());
  });
}
