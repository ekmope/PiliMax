import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:PiliMax/tcp/live.dart';
import 'package:PiliMax/tcp/live_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user close cancels a queued reconnect and never reconnects', () async {
    final scheduler = _FakeTimerScheduler();
    final first = _FakeSocketConnection();
    final connector = _FakeSocketConnector([
      first,
      _FakeSocketConnection(),
    ]);
    final stream = _liveStream(
      connector: connector.call,
      scheduler: scheduler,
    );

    await stream.init();
    expect(connector.callCount, 1);

    await first.disconnect();
    await _flushAsyncCallbacks();
    expect(scheduler.nextOneShotDelay, const Duration(seconds: 1));

    stream.close();
    expect(scheduler.activeTaskCount, 0);

    scheduler.elapse(const Duration(hours: 1));
    await _flushAsyncCallbacks();

    expect(connector.callCount, 1);
    expect(scheduler.activeTaskCount, 0);
  });

  test('network disconnects reconnect with exponential backoff', () async {
    final scheduler = _FakeTimerScheduler();
    final first = _FakeSocketConnection();
    final second = _FakeSocketConnection();
    final third = _FakeSocketConnection();
    final connector = _FakeSocketConnector([first, second, third]);
    final stream = _liveStream(
      connector: connector.call,
      scheduler: scheduler,
    );

    await stream.init();
    await first.disconnect();
    await _flushAsyncCallbacks();

    expect(scheduler.nextOneShotDelay, const Duration(seconds: 1));
    scheduler.elapse(const Duration(milliseconds: 999));
    await _flushAsyncCallbacks();
    expect(connector.callCount, 1);

    scheduler.elapse(const Duration(milliseconds: 1));
    await _flushAsyncCallbacks();
    expect(connector.callCount, 2);

    await second.disconnect();
    await _flushAsyncCallbacks();
    expect(scheduler.nextOneShotDelay, const Duration(seconds: 2));

    scheduler.elapse(const Duration(seconds: 2));
    await _flushAsyncCallbacks();
    expect(connector.callCount, 3);

    stream.close();
    expect(scheduler.activeTaskCount, 0);
  });

  test('close aborts a pending connection and its timeout', () async {
    final scheduler = _FakeTimerScheduler();
    final pending = _FakeSocketConnection(readyImmediately: false);
    final connector = _FakeSocketConnector([pending]);
    final stream = _liveStream(
      connector: connector.call,
      scheduler: scheduler,
    );

    final initFuture = stream.init();
    await _flushAsyncCallbacks();
    expect(connector.callCount, 1);
    expect(scheduler.nextOneShotDelay, const Duration(seconds: 10));

    stream.close();
    await initFuture;

    expect(pending.closeCount, greaterThanOrEqualTo(1));
    expect(pending.sent, isEmpty);
    expect(scheduler.activeTaskCount, 0);

    pending.completeReady();
    scheduler.elapse(const Duration(minutes: 1));
    await _flushAsyncCallbacks();

    expect(connector.callCount, 1);
    expect(pending.sent, isEmpty);
    expect(scheduler.activeTaskCount, 0);
  });

  test('close cancels authentication and heartbeat timers', () async {
    final scheduler = _FakeTimerScheduler();
    final socket = _FakeSocketConnection();
    final connector = _FakeSocketConnector([socket]);
    final stream = _liveStream(
      connector: connector.call,
      scheduler: scheduler,
    );

    await stream.init();
    expect(socket.sent, hasLength(1));
    expect(scheduler.activeOneShotTaskCount, 1);

    socket.emit(_authReplyPacket());
    await _flushAsyncCallbacks();
    expect(scheduler.activeOneShotTaskCount, 0);
    expect(scheduler.activePeriodicTaskCount, 1);

    scheduler.elapse(const Duration(seconds: 30));
    await _flushAsyncCallbacks();
    expect(socket.sent, hasLength(2));

    stream.close();
    final sentAtClose = socket.sent.length;
    expect(scheduler.activeTaskCount, 0);

    scheduler.elapse(const Duration(minutes: 5));
    await _flushAsyncCallbacks();

    expect(socket.sent, hasLength(sentAtClose));
    expect(connector.callCount, 1);
    expect(scheduler.activeTaskCount, 0);
  });
}

LiveMessageStream _liveStream({
  required LiveSocketConnector connector,
  required LiveTimerScheduler scheduler,
}) => LiveMessageStream(
  streamToken: 'token',
  roomId: 1,
  uid: 2,
  servers: const ['wss://live.test/sub'],
  reconnectPolicy: const LiveReconnectPolicy(
    maxAttempts: 4,
    baseDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 8),
    jitterRatio: 0,
  ),
  connector: connector,
  timerScheduler: scheduler,
);

Uint8List _authReplyPacket() {
  final body = utf8.encode('{"code":0}');
  final totalSize = LivePacketHeader.wireSize + body.length;
  final bytes = ByteData(totalSize)
    ..setUint32(0, totalSize, Endian.big)
    ..setUint16(4, LivePacketHeader.wireSize, Endian.big)
    ..setUint16(6, 1, Endian.big)
    ..setUint32(8, 8, Endian.big)
    ..setUint32(12, 1, Endian.big);
  return bytes.buffer.asUint8List()
    ..setRange(LivePacketHeader.wireSize, totalSize, body);
}

Future<void> _flushAsyncCallbacks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeSocketConnector {
  _FakeSocketConnector(this._connections);

  final List<_FakeSocketConnection> _connections;
  final List<Uri> requestedUris = [];
  int callCount = 0;

  LiveSocketConnection call(Uri uri) {
    requestedUris.add(uri);
    if (callCount >= _connections.length) {
      throw StateError('Unexpected connection attempt ${callCount + 1}');
    }
    return _connections[callCount++];
  }
}

final class _FakeSocketConnection implements LiveSocketConnection {
  _FakeSocketConnection({bool readyImmediately = true}) {
    if (readyImmediately) {
      _ready.complete();
    }
  }

  final Completer<void> _ready = Completer<void>();
  final StreamController<dynamic> _incoming = StreamController<dynamic>(
    sync: true,
  );
  final List<dynamic> sent = [];
  int closeCount = 0;

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  void add(dynamic data) {
    if (_incoming.isClosed) {
      throw StateError('Socket is closed');
    }
    sent.add(data);
  }

  @override
  Future<void> close() {
    closeCount++;
    return _incoming.isClosed ? Future<void>.value() : _incoming.close();
  }

  void completeReady() {
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  void emit(dynamic data) {
    if (_incoming.isClosed) {
      throw StateError('Socket is closed');
    }
    _incoming.add(data);
  }

  Future<void> disconnect() => close();
}

final class _FakeTimerScheduler implements LiveTimerScheduler {
  final List<_FakeScheduledTask> _tasks = [];
  int _nowMicroseconds = 0;

  int get activeTaskCount => _tasks.where((task) => task.isActive).length;

  int get activeOneShotTaskCount =>
      _tasks.where((task) => task.isActive && !task.isPeriodic).length;

  int get activePeriodicTaskCount =>
      _tasks.where((task) => task.isActive && task.isPeriodic).length;

  Duration? get nextOneShotDelay {
    final active =
        _tasks.where((task) => task.isActive && !task.isPeriodic).toList()
          ..sort(
            (left, right) => left.dueMicroseconds.compareTo(
              right.dueMicroseconds,
            ),
          );
    if (active.isEmpty) return null;
    return Duration(
      microseconds: active.first.dueMicroseconds - _nowMicroseconds,
    );
  }

  @override
  LiveScheduledTask schedule(Duration delay, void Function() callback) {
    final task = _FakeScheduledTask(
      dueMicroseconds: _nowMicroseconds + _nonNegative(delay.inMicroseconds),
      intervalMicroseconds: null,
      callback: callback,
    );
    _tasks.add(task);
    return task;
  }

  @override
  LiveScheduledTask schedulePeriodic(
    Duration interval,
    void Function() callback,
  ) {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    final intervalMicroseconds = interval.inMicroseconds;
    final task = _FakeScheduledTask(
      dueMicroseconds: _nowMicroseconds + intervalMicroseconds,
      intervalMicroseconds: intervalMicroseconds,
      callback: callback,
    );
    _tasks.add(task);
    return task;
  }

  void elapse(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    final target = _nowMicroseconds + duration.inMicroseconds;
    while (true) {
      _FakeScheduledTask? next;
      for (final task in _tasks) {
        if (!task.isActive || task.dueMicroseconds > target) continue;
        if (next == null || task.dueMicroseconds < next.dueMicroseconds) {
          next = task;
        }
      }
      if (next == null) break;
      _nowMicroseconds = next.dueMicroseconds;
      next.fire();
    }
    _nowMicroseconds = target;
  }

  static int _nonNegative(int value) => value < 0 ? 0 : value;
}

final class _FakeScheduledTask implements LiveScheduledTask {
  _FakeScheduledTask({
    required this.dueMicroseconds,
    required this.intervalMicroseconds,
    required this.callback,
  });

  int dueMicroseconds;
  final int? intervalMicroseconds;
  final void Function() callback;
  bool _isActive = true;

  bool get isPeriodic => intervalMicroseconds != null;

  @override
  bool get isActive => _isActive;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) return;
    final interval = intervalMicroseconds;
    if (interval == null) {
      _isActive = false;
    } else {
      dueMicroseconds += interval;
    }
    callback();
  }
}
