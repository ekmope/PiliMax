import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

enum LivePacketParseError {
  truncatedHeader,
  invalidHeaderSize,
  invalidTotalSize,
  packetTooLarge,
  tooManyPackets,
  packetOutOfBounds,
}

final class LivePacketHeader {
  static const int wireSize = 16;

  const LivePacketHeader({
    required this.totalSize,
    required this.headerSize,
    required this.protocolVersion,
    required this.operationCode,
    required this.sequence,
  });

  final int totalSize;
  final int headerSize;
  final int protocolVersion;
  final int operationCode;
  final int sequence;
}

final class LivePacketFrame {
  const LivePacketFrame({required this.header, required this.body});

  final LivePacketHeader header;
  final Uint8List body;
}

final class LivePacketParseResult {
  const LivePacketParseResult({
    required this.packets,
    this.error,
    this.errorOffset,
  });

  final List<LivePacketFrame> packets;
  final LivePacketParseError? error;
  final int? errorOffset;

  bool get isMalformed => error != null;
}

abstract final class LivePacketParser {
  static const int maxPacketSize = 16 * 1024 * 1024;
  static const int maxPacketsPerBuffer = 4096;

  static LivePacketParseResult parse(Uint8List data) {
    final packets = <LivePacketFrame>[];
    var offset = 0;

    LivePacketParseResult malformed(LivePacketParseError error) =>
        LivePacketParseResult(
          packets: packets,
          error: error,
          errorOffset: offset,
        );

    while (offset < data.length) {
      final remaining = data.length - offset;
      if (remaining < LivePacketHeader.wireSize) {
        return malformed(LivePacketParseError.truncatedHeader);
      }

      final headerData = ByteData.sublistView(
        data,
        offset,
        offset + LivePacketHeader.wireSize,
      );
      final totalSize = headerData.getUint32(0, Endian.big);
      final headerSize = headerData.getUint16(4, Endian.big);
      if (headerSize < LivePacketHeader.wireSize) {
        return malformed(LivePacketParseError.invalidHeaderSize);
      }
      if (totalSize < headerSize) {
        return malformed(LivePacketParseError.invalidTotalSize);
      }
      if (totalSize > maxPacketSize) {
        return malformed(LivePacketParseError.packetTooLarge);
      }
      if (totalSize > remaining) {
        return malformed(LivePacketParseError.packetOutOfBounds);
      }

      final bodyStart = offset + headerSize;
      final packetEnd = offset + totalSize;
      if (bodyStart > packetEnd || packetEnd > data.length) {
        return malformed(LivePacketParseError.packetOutOfBounds);
      }
      if (packets.length >= maxPacketsPerBuffer) {
        return malformed(LivePacketParseError.tooManyPackets);
      }

      packets.add(
        LivePacketFrame(
          header: LivePacketHeader(
            totalSize: totalSize,
            headerSize: headerSize,
            protocolVersion: headerData.getUint16(6, Endian.big),
            operationCode: headerData.getUint32(8, Endian.big),
            sequence: headerData.getUint32(12, Endian.big),
          ),
          body: Uint8List.sublistView(data, bodyStart, packetEnd),
        ),
      );
      offset = packetEnd;
    }

    return LivePacketParseResult(packets: packets);
  }
}

enum LiveAuthReplyStatus { accepted, rejected, malformed }

abstract final class LiveAuthReplyParser {
  static LiveAuthReplyStatus parse(Uint8List body) {
    if (body.isEmpty) {
      return LiveAuthReplyStatus.malformed;
    }
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map) {
        return LiveAuthReplyStatus.malformed;
      }
      final rawCode = decoded['code'];
      final code = switch (rawCode) {
        int value => value,
        num value when value.isFinite && value == value.truncate() =>
          value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
      if (code == null) {
        return LiveAuthReplyStatus.malformed;
      }
      return code == 0
          ? LiveAuthReplyStatus.accepted
          : LiveAuthReplyStatus.rejected;
    } catch (_) {
      return LiveAuthReplyStatus.malformed;
    }
  }
}

final class LiveConnectionEpoch {
  int _generation = 0;
  bool _active = false;

  int get generation => _generation;
  bool get isActive => _active;

  void activate() {
    _active = true;
    _generation++;
  }

  int advance() => ++_generation;

  void deactivate() {
    _active = false;
    _generation++;
  }

  bool isCurrent(int generation) => _active && generation == _generation;
}

final class LivePayloadSizeLimitExceeded implements Exception {
  const LivePayloadSizeLimitExceeded();
}

final class LiveBoundedBytesSink implements Sink<List<int>> {
  LiveBoundedBytesSink(this.maxBytes) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
    }
  }

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: true);
  int _length = 0;
  bool _closed = false;

  int get length => _length;

  @override
  void add(List<int> data) {
    if (_closed) {
      throw StateError('Cannot add bytes after the sink is closed');
    }
    if (data.length > maxBytes - _length) {
      throw const LivePayloadSizeLimitExceeded();
    }
    _builder.add(data);
    _length += data.length;
  }

  @override
  void close() {
    _closed = true;
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

final class LiveReconnectPolicy {
  const LiveReconnectPolicy({
    this.maxAttempts = 6,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.jitterRatio = 0.2,
  }) : assert(maxAttempts >= 0),
       assert(jitterRatio >= 0 && jitterRatio <= 1);

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final double jitterRatio;

  Duration delayForAttempt(int attempt, {required double randomValue}) {
    final safeAttempt = math.max(0, attempt);
    final baseDelayMs = math.max(0, baseDelay.inMilliseconds);
    final maxDelayMs = math.max(0, maxDelay.inMilliseconds);
    final exponentialMs = baseDelayMs * math.pow(2, safeAttempt).toDouble();
    final cappedMs = math.min(
      exponentialMs,
      maxDelayMs.toDouble(),
    );
    final normalizedRandom = randomValue.isFinite
        ? randomValue.clamp(0.0, 1.0)
        : 0.5;
    final safeJitterRatio = jitterRatio.isFinite
        ? jitterRatio.clamp(0.0, 1.0)
        : 0.0;
    final jitterMultiplier = 1 + ((normalizedRandom * 2) - 1) * safeJitterRatio;
    final jitteredMs = (cappedMs * jitterMultiplier).round().clamp(
      0,
      maxDelayMs,
    );
    return Duration(milliseconds: jitteredMs);
  }
}
