import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:PiliMax/services/logger.dart';
import 'package:PiliMax/tcp/live_protocol.dart';
import 'package:brotli/brotli.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef LiveSocketConnector = LiveSocketConnection Function(Uri uri);

abstract interface class LiveSocketConnection {
  Future<void> get ready;

  Stream<dynamic> get stream;

  void add(dynamic data);

  Future<void> close();
}

abstract interface class LiveScheduledTask {
  bool get isActive;

  void cancel();
}

abstract interface class LiveTimerScheduler {
  LiveScheduledTask schedule(Duration delay, void Function() callback);

  LiveScheduledTask schedulePeriodic(
    Duration interval,
    void Function() callback,
  );
}

final class _WebSocketLiveConnection implements LiveSocketConnection {
  const _WebSocketLiveConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void add(dynamic data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

final class _DartLiveScheduledTask implements LiveScheduledTask {
  const _DartLiveScheduledTask(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}

final class _DartLiveTimerScheduler implements LiveTimerScheduler {
  const _DartLiveTimerScheduler();

  @override
  LiveScheduledTask schedule(Duration delay, void Function() callback) =>
      _DartLiveScheduledTask(Timer(delay, callback));

  @override
  LiveScheduledTask schedulePeriodic(
    Duration interval,
    void Function() callback,
  ) => _DartLiveScheduledTask(Timer.periodic(interval, (_) => callback()));
}

LiveSocketConnection _connectLiveSocket(Uri uri) =>
    _WebSocketLiveConnection(WebSocketChannel.connect(uri));

class PackageHeader {
  final int protocolVer;
  final int operationCode;
  final int seq;

  @override
  String toString() {
    return 'PackageHeader{protocolVer: $protocolVer, operationCode: $operationCode, seq: $seq}';
  }

  const PackageHeader({
    required this.protocolVer,
    required this.operationCode,
    required this.seq,
  });

  Uint8List toBytes(int contentSize) {
    final bytes = ByteData(0x10)
      ..setInt32(0, 0x10 + contentSize, Endian.big)
      ..setInt16(4, 0x10, Endian.big)
      ..setInt16(6, protocolVer, Endian.big)
      ..setInt32(8, operationCode, Endian.big)
      ..setInt32(12, seq, Endian.big);
    return bytes.buffer.asUint8List();
  }
}

abstract class Message {
  String toJsonStr();
}

class AuthMessage implements Message {
  int roomid;
  int uid;
  int protover;
  String platform;
  int type;
  String key;

  AuthMessage({
    required this.roomid,
    required this.uid,
    required this.protover,
    required this.platform,
    required this.type,
    required this.key,
  });

  @override
  String toJsonStr() {
    final message = {
      'roomid': roomid,
      'uid': uid,
      'protover': protover,
      'platform': platform,
      'type': type,
      'key': key,
    };
    return jsonEncode(message);
  }
}

abstract class AbstractPackage<T> {
  PackageHeader header;
  T body;
  Uint8List marshal();
  AbstractPackage({required this.header, required this.body});
}

//认证包
class AuthPackage extends AbstractPackage<Message> {
  AuthPackage({required super.header, required super.body});

  @override
  Uint8List marshal() {
    final json = utf8.encode(body.toJsonStr());
    final buffer = BytesBuilder()
      ..add(header.toBytes(json.length))
      ..add(json);
    return buffer.toBytes();
  }
}

//心跳包
class HeartbeatPackage extends AbstractPackage<dynamic> {
  HeartbeatPackage({required super.header, super.body});

  @override
  Uint8List marshal() {
    return header.toBytes(0);
  }
}

class LiveMessageStream {
  LiveMessageStream({
    required this.streamToken,
    required this.roomId,
    required this.uid,
    required this.servers,
    this.reconnectPolicy = const LiveReconnectPolicy(),
    this.onReconnectExhausted,
    math.Random? random,
    LiveSocketConnector? connector,
    LiveTimerScheduler? timerScheduler,
  }) : _random = random ?? math.Random(),
       _connector = connector ?? _connectLiveSocket,
       _timerScheduler = timerScheduler ?? const _DartLiveTimerScheduler();

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _authenticationTimeout = Duration(seconds: 10);
  static const int _maxCompressedDepth = 4;
  static const int _maxDecompressedSize = 32 * 1024 * 1024;

  final String streamToken;
  final int roomId;
  final int uid;
  final List<String> servers;
  final LiveReconnectPolicy reconnectPolicy;
  final void Function()? onReconnectExhausted;
  final math.Random _random;
  final LiveSocketConnector _connector;
  final LiveTimerScheduler _timerScheduler;
  final List<void Function(dynamic obj)> _eventListeners = [];

  final LiveConnectionEpoch _connectionEpoch = LiveConnectionEpoch();
  bool _connecting = false;
  int _reconnectAttempt = 0;
  LiveSocketConnection? _channel;
  LiveSocketConnection? _pendingChannel;
  // Cancelled centrally by _disposeConnection() on disconnect and close().
  // ignore: cancel_subscriptions
  StreamSubscription? _socketSubscription;
  LiveScheduledTask? _connectTimeoutTask;
  Completer<void>? _connectWaitCancellation;
  LiveScheduledTask? _authenticationTimer;
  LiveScheduledTask? _heartbeatTimer;
  LiveScheduledTask? _reconnectTimer;
  final String logTag = 'LiveStreamService';

  Future<void> init() async {
    if (_connectionEpoch.isActive) return;
    _connectionEpoch.activate();
    _reconnectAttempt = 0;
    if (servers.isEmpty) {
      _connectionEpoch.deactivate();
      logger.w('$logTag has no connection endpoints');
      _notifyReconnectExhausted();
      return;
    }
    await _connect();
  }

  AuthPackage _buildAuthPackage() => AuthPackage(
    header: const PackageHeader(
      protocolVer: 1,
      operationCode: 7,
      seq: 1,
    ),
    body: AuthMessage(
      roomid: roomId,
      uid: uid,
      protover: 3,
      platform: 'web',
      type: 2,
      key: streamToken,
    ),
  );

  bool _isCurrentConnection(int generation) =>
      _connectionEpoch.isCurrent(generation);

  Future<void> _waitForConnectionReady(LiveSocketConnection channel) async {
    final cancellation = Completer<void>();
    final timeout = Completer<void>();
    final timeoutTask = _timerScheduler.schedule(_connectTimeout, () {
      if (!timeout.isCompleted) {
        timeout.completeError(
          TimeoutException('Live WebSocket connection timed out'),
        );
      }
    });
    _connectWaitCancellation = cancellation;
    _connectTimeoutTask = timeoutTask;
    try {
      await Future.any<void>([
        channel.ready,
        cancellation.future,
        timeout.future,
      ]);
    } finally {
      timeoutTask.cancel();
      if (identical(_connectTimeoutTask, timeoutTask)) {
        _connectTimeoutTask = null;
      }
      if (identical(_connectWaitCancellation, cancellation)) {
        _connectWaitCancellation = null;
      }
    }
  }

  void _cancelConnectionWait() {
    final cancellation = _connectWaitCancellation;
    _connectWaitCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _connectTimeoutTask?.cancel();
    _connectTimeoutTask = null;
  }

  Future<void> _connect() async {
    if (!_connectionEpoch.isActive || _connecting || servers.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = true;
    final generation = _connectionEpoch.advance();
    LiveSocketConnection? connectedChannel;

    try {
      for (final server in servers) {
        if (!_isCurrentConnection(generation)) return;
        LiveSocketConnection? candidate;
        try {
          candidate = _connector(Uri.parse(server));
          _pendingChannel = candidate;
          await _waitForConnectionReady(candidate);
          if (!_isCurrentConnection(generation)) {
            _closeChannel(candidate);
            return;
          }
          if (identical(_pendingChannel, candidate)) {
            _pendingChannel = null;
          }
          connectedChannel = candidate;
          break;
        } catch (_) {
          if (identical(_pendingChannel, candidate)) {
            _pendingChannel = null;
          }
          if (candidate != null) {
            _closeChannel(candidate);
          }
        }
      }

      if (connectedChannel == null) {
        _scheduleReconnect(generation);
        return;
      }

      _channel = connectedChannel;
      _socketSubscription = connectedChannel.stream.listen(
        (data) => _handleSocketData(data, generation),
        onDone: () => _handleTransportClosed(generation),
        onError: (_, _) => _handleTransportClosed(generation),
      );
      try {
        connectedChannel.add(_buildAuthPackage().marshal());
        _startAuthenticationTimer(generation);
      } catch (_) {
        _handleTransportClosed(generation);
      }
    } catch (_) {
      if (_isCurrentConnection(generation)) {
        _handleTransportClosed(generation);
      }
    } finally {
      if (generation == _connectionEpoch.generation) {
        _connecting = false;
      }
    }
  }

  void _handleTransportClosed(int generation) {
    if (!_isCurrentConnection(generation)) return;
    final nextGeneration = _connectionEpoch.advance();
    _connecting = false;
    _cancelAuthenticationTimer();
    _cancelHeartbeat();
    _disposePendingConnection();
    _disposeConnection();
    _scheduleReconnect(nextGeneration);
  }

  void _scheduleReconnect(int generation) {
    if (!_isCurrentConnection(generation) || _reconnectTimer != null) return;
    if (_reconnectAttempt >= reconnectPolicy.maxAttempts) {
      _connectionEpoch.deactivate();
      _connecting = false;
      _cancelAuthenticationTimer();
      _cancelHeartbeat();
      _disposePendingConnection();
      _disposeConnection();
      logger.w('$logTag reconnect limit reached');
      SmartDialog.showToast('直播弹幕连接已断开，请稍后重试');
      _notifyReconnectExhausted();
      return;
    }

    final attempt = _reconnectAttempt++;
    final delay = reconnectPolicy.delayForAttempt(
      attempt,
      randomValue: _random.nextDouble(),
    );
    if (kDebugMode) {
      logger.i(
        '$logTag reconnect scheduled attempt=${attempt + 1} '
        'delayMs=${delay.inMilliseconds}',
      );
    }
    _reconnectTimer = _timerScheduler.schedule(delay, () {
      _reconnectTimer = null;
      if (_isCurrentConnection(generation)) {
        unawaited(_connect());
      }
    });
  }

  void _notifyReconnectExhausted() {
    try {
      onReconnectExhausted?.call();
    } catch (_) {
      logger.w('$logTag reconnect exhaustion callback failed');
    }
  }

  void _ignoreFuture(Future<dynamic>? future) {
    if (future == null) return;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  void _closeChannel(LiveSocketConnection channel) {
    try {
      _ignoreFuture(channel.close());
    } catch (_) {}
  }

  void _disposePendingConnection() {
    _cancelConnectionWait();
    final channel = _pendingChannel;
    _pendingChannel = null;
    if (channel != null) {
      _closeChannel(channel);
    }
  }

  void _disposeConnection() {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      try {
        _ignoreFuture(subscription.cancel());
      } catch (_) {}
    }
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      _closeChannel(channel);
    }
  }

  void _cancelAuthenticationTimer() {
    _authenticationTimer?.cancel();
    _authenticationTimer = null;
  }

  void _startAuthenticationTimer(int generation) {
    _cancelAuthenticationTimer();
    _authenticationTimer = _timerScheduler.schedule(_authenticationTimeout, () {
      _authenticationTimer = null;
      if (_isCurrentConnection(generation)) {
        logger.w('$logTag authentication timed out');
        _handleTransportClosed(generation);
      }
    });
  }

  void _cancelHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _startHeartbeat(int generation) {
    if (!_isCurrentConnection(generation) || _channel == null) return;
    _cancelAuthenticationTimer();
    _reconnectAttempt = 0;
    _cancelHeartbeat();
    var heartbeatCount = 1;
    if (kDebugMode) logger.i('$logTag authenticated');
    _heartbeatTimer = _timerScheduler.schedulePeriodic(
      const Duration(seconds: 30),
      () {
        if (!_isCurrentConnection(generation)) {
          _cancelHeartbeat();
          return;
        }
        final package = HeartbeatPackage(
          header: PackageHeader(
            protocolVer: 1,
            operationCode: 2,
            seq: heartbeatCount++,
          ),
        );
        try {
          _channel?.add(package.marshal());
        } catch (_) {
          _handleTransportClosed(generation);
        }
      },
    );
  }

  void addEventListener(void Function(dynamic) func) {
    _eventListeners.add(func);
  }

  void _logMalformedPacket(
    LivePacketParseResult result,
    int byteLength,
  ) {
    logger.w(
      '$logTag dropped malformed packet '
      'reason=${result.error?.name ?? 'unknown'} '
      'offset=${result.errorOffset ?? -1} bytes=$byteLength',
    );
  }

  void _dispatchJson(Uint8List body) {
    if (body.isEmpty) return;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      for (final listener in List.of(_eventListeners)) {
        try {
          listener(decoded);
        } catch (_) {
          logger.w('$logTag event listener rejected a message');
        }
      }
    } catch (_) {
      logger.w('$logTag dropped invalid JSON payload bytes=${body.length}');
    }
  }

  Uint8List _decodeCompressed(
    Converter<List<int>, List<int>> decoder,
    Uint8List body,
  ) {
    final output = LiveBoundedBytesSink(_maxDecompressedSize);
    decoder.startChunkedConversion(output)
      ..add(body)
      ..close();
    return output.takeBytes();
  }

  void _processPacketBuffer(
    Uint8List data, {
    required int generation,
    int depth = 0,
  }) {
    if (!_isCurrentConnection(generation) || data.isEmpty) return;
    if (depth > _maxCompressedDepth || data.length > _maxDecompressedSize) {
      logger.w('$logTag dropped oversized or deeply nested payload');
      return;
    }

    final result = LivePacketParser.parse(data);
    for (final packet in result.packets) {
      if (!_isCurrentConnection(generation)) return;
      final header = packet.header;
      if (header.operationCode == 3) {
        continue;
      }
      if (header.operationCode == 8) {
        switch (LiveAuthReplyParser.parse(packet.body)) {
          case LiveAuthReplyStatus.accepted:
            _startHeartbeat(generation);
          case LiveAuthReplyStatus.rejected:
            logger.w('$logTag authentication rejected');
            _handleTransportClosed(generation);
            return;
          case LiveAuthReplyStatus.malformed:
            logger.w('$logTag dropped malformed authentication reply');
            _handleTransportClosed(generation);
            return;
        }
        continue;
      }
      if (header.operationCode != 5) {
        continue;
      }

      try {
        switch (header.protocolVersion) {
          case 0:
          case 1:
            _dispatchJson(packet.body);
          case 2:
            if (depth >= _maxCompressedDepth) {
              logger.w('$logTag dropped deeply nested compressed payload');
              continue;
            }
            final decompressed = _decodeCompressed(
              ZLibDecoder(),
              packet.body,
            );
            _processPacketBuffer(
              decompressed,
              generation: generation,
              depth: depth + 1,
            );
          case 3:
            if (depth >= _maxCompressedDepth) {
              logger.w('$logTag dropped deeply nested compressed payload');
              continue;
            }
            final decompressed = _decodeCompressed(
              const BrotliDecoder(),
              packet.body,
            );
            _processPacketBuffer(
              decompressed,
              generation: generation,
              depth: depth + 1,
            );
          default:
            logger.w(
              '$logTag dropped unsupported protocol '
              'version=${header.protocolVersion}',
            );
        }
      } on LivePayloadSizeLimitExceeded {
        logger.w(
          '$logTag dropped decompressed payload above limit '
          'protocol=${header.protocolVersion}',
        );
      } catch (_) {
        logger.w(
          '$logTag dropped undecodable payload '
          'protocol=${header.protocolVersion} bytes=${packet.body.length}',
        );
      }
    }
    if (result.isMalformed) {
      _logMalformedPacket(result, data.length);
    }
  }

  void _handleSocketData(dynamic data, int generation) {
    if (!_isCurrentConnection(generation)) return;
    final Uint8List? bytes = switch (data) {
      Uint8List value => value,
      List<int> value => Uint8List.fromList(value),
      _ => null,
    };
    if (bytes == null) {
      logger.w('$logTag dropped non-binary WebSocket message');
      return;
    }
    _processPacketBuffer(bytes, generation: generation);
  }

  @pragma('vm:notify-debugger-on-exception')
  void onData(dynamic data) {
    _handleSocketData(data, _connectionEpoch.generation);
  }

  /// User-initiated shutdown. Network failures use [_handleTransportClosed]
  /// and retain listeners while a bounded reconnect is pending.
  void close() {
    final shouldLog =
        _connectionEpoch.isActive ||
        _channel != null ||
        _pendingChannel != null ||
        _reconnectTimer != null;
    _connectionEpoch.deactivate();
    _connecting = false;
    _cancelAuthenticationTimer();
    _cancelHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disposePendingConnection();
    _disposeConnection();
    _eventListeners.clear();
    if (kDebugMode && shouldLog) logger.i('$logTag closed by user');
  }
}
