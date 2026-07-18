import 'dart:typed_data';

import 'package:PiliMax/tcp/live_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _packet(
  List<int> body, {
  int headerSize = LivePacketHeader.wireSize,
  int? declaredTotalSize,
}) {
  final actualSize = headerSize + body.length;
  final data = ByteData(actualSize)
    ..setUint32(0, declaredTotalSize ?? actualSize, Endian.big)
    ..setUint16(4, headerSize, Endian.big)
    ..setUint16(6, 1, Endian.big)
    ..setUint32(8, 5, Endian.big)
    ..setUint32(12, 1, Endian.big);
  return data.buffer.asUint8List()..setRange(headerSize, actualSize, body);
}

void main() {
  group('LivePacketParser', () {
    test('parses multiple bounded packets', () {
      final builder = BytesBuilder(copy: false)
        ..add(_packet([1, 2, 3]))
        ..add(_packet([4, 5]));

      final result = LivePacketParser.parse(builder.toBytes());

      expect(result.isMalformed, isFalse);
      expect(result.packets, hasLength(2));
      expect(result.packets[0].body, orderedEquals([1, 2, 3]));
      expect(result.packets[1].body, orderedEquals([4, 5]));
    });

    test('accepts an extended header and respects its boundary', () {
      final result = LivePacketParser.parse(_packet([7, 8], headerSize: 20));

      expect(result.isMalformed, isFalse);
      expect(result.packets.single.header.headerSize, 20);
      expect(result.packets.single.body, orderedEquals([7, 8]));
    });

    test('rejects a truncated 16-byte header', () {
      final result = LivePacketParser.parse(Uint8List(15));

      expect(result.error, LivePacketParseError.truncatedHeader);
    });

    test('rejects a header smaller than the wire header', () {
      final data = _packet(const []);
      ByteData.sublistView(data).setUint16(4, 15, Endian.big);

      final result = LivePacketParser.parse(data);

      expect(result.error, LivePacketParseError.invalidHeaderSize);
    });

    test('rejects total size smaller than header size', () {
      final result = LivePacketParser.parse(
        _packet(const [], declaredTotalSize: 15),
      );

      expect(result.error, LivePacketParseError.invalidTotalSize);
    });

    test('rejects a packet extending past the received buffer', () {
      final result = LivePacketParser.parse(
        _packet(const [], declaredTotalSize: 32),
      );

      expect(result.error, LivePacketParseError.packetOutOfBounds);
    });

    test('rejects a declared packet above the hard size limit', () {
      final data = _packet(const []);
      ByteData.sublistView(data).setUint32(
        0,
        LivePacketParser.maxPacketSize + 1,
        Endian.big,
      );

      final result = LivePacketParser.parse(data);

      expect(result.error, LivePacketParseError.packetTooLarge);
    });

    test('keeps valid leading packets and rejects a malformed tail', () {
      final builder = BytesBuilder(copy: false)
        ..add(_packet([1]))
        ..add(Uint8List(4));

      final result = LivePacketParser.parse(builder.toBytes());

      expect(result.packets, hasLength(1));
      expect(result.packets.single.body, orderedEquals([1]));
      expect(result.error, LivePacketParseError.truncatedHeader);
      expect(result.errorOffset, LivePacketHeader.wireSize + 1);
    });

    test('bounds the number of packet objects created from one buffer', () {
      final packet = _packet(const []);
      final builder = BytesBuilder(copy: false);
      for (
        var index = 0;
        index <= LivePacketParser.maxPacketsPerBuffer;
        index++
      ) {
        builder.add(packet);
      }

      final result = LivePacketParser.parse(builder.toBytes());

      expect(result.packets, hasLength(LivePacketParser.maxPacketsPerBuffer));
      expect(result.error, LivePacketParseError.tooManyPackets);
    });
  });

  group('LiveAuthReplyParser', () {
    test('accepts only an explicit zero code', () {
      expect(
        LiveAuthReplyParser.parse(Uint8List.fromList('{"code":0}'.codeUnits)),
        LiveAuthReplyStatus.accepted,
      );
      expect(
        LiveAuthReplyParser.parse(
          Uint8List.fromList('{"code":-101}'.codeUnits),
        ),
        LiveAuthReplyStatus.rejected,
      );
    });

    test('rejects missing, empty, and invalid authentication payloads', () {
      expect(
        LiveAuthReplyParser.parse(Uint8List(0)),
        LiveAuthReplyStatus.malformed,
      );
      expect(
        LiveAuthReplyParser.parse(Uint8List.fromList('{}'.codeUnits)),
        LiveAuthReplyStatus.malformed,
      );
      expect(
        LiveAuthReplyParser.parse(
          Uint8List.fromList('{"code":0.5}'.codeUnits),
        ),
        LiveAuthReplyStatus.malformed,
      );
      expect(
        LiveAuthReplyParser.parse(Uint8List.fromList([0xff])),
        LiveAuthReplyStatus.malformed,
      );
    });
  });

  group('LiveConnectionEpoch', () {
    test('close invalidates an in-flight connection generation', () {
      final epoch = LiveConnectionEpoch()..activate();
      final inFlight = epoch.advance();

      expect(epoch.isCurrent(inFlight), isTrue);

      epoch.deactivate();

      expect(epoch.isActive, isFalse);
      expect(epoch.isCurrent(inFlight), isFalse);
    });

    test('a restarted lifecycle never accepts callbacks from the old one', () {
      final epoch = LiveConnectionEpoch()..activate();
      final oldGeneration = epoch.advance();

      epoch
        ..deactivate()
        ..activate();
      final newGeneration = epoch.advance();

      expect(epoch.isCurrent(oldGeneration), isFalse);
      expect(epoch.isCurrent(newGeneration), isTrue);
    });

    test('advancing for a replacement connection invalidates the old one', () {
      final epoch = LiveConnectionEpoch()..activate();
      final oldGeneration = epoch.advance();
      final replacementGeneration = epoch.advance();

      expect(epoch.isCurrent(oldGeneration), isFalse);
      expect(epoch.isCurrent(replacementGeneration), isTrue);
    });
  });

  group('LiveBoundedBytesSink', () {
    test('accepts output exactly at the configured limit', () {
      final sink = LiveBoundedBytesSink(4)
        ..add([1, 2])
        ..add([3, 4])
        ..close();

      expect(sink.length, 4);
      expect(sink.takeBytes(), orderedEquals([1, 2, 3, 4]));
    });

    test('rejects decompressed output as soon as it crosses the limit', () {
      final sink = LiveBoundedBytesSink(3)..add([1, 2]);

      expect(
        () => sink.add([3, 4]),
        throwsA(isA<LivePayloadSizeLimitExceeded>()),
      );
    });

    test('copies decoder chunks that may reuse their backing buffer', () {
      final chunk = Uint8List.fromList([1, 2]);
      final sink = LiveBoundedBytesSink(4)..add(chunk);
      chunk[0] = 9;
      sink
        ..add(chunk)
        ..close();

      expect(sink.takeBytes(), orderedEquals([1, 2, 9, 2]));
    });
  });

  group('LiveReconnectPolicy', () {
    test('uses capped exponential backoff without jitter at midpoint', () {
      const policy = LiveReconnectPolicy();

      final delays = List.generate(
        7,
        (attempt) => policy.delayForAttempt(
          attempt,
          randomValue: 0.5,
        ),
      );

      expect(
        delays,
        const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 16),
          Duration(seconds: 30),
          Duration(seconds: 30),
        ],
      );
    });

    test('jitter never exceeds the configured maximum', () {
      const policy = LiveReconnectPolicy(
        baseDelay: Duration(seconds: 20),
        maxDelay: Duration(seconds: 30),
        jitterRatio: 0.5,
      );

      expect(
        policy.delayForAttempt(5, randomValue: 1),
        const Duration(seconds: 30),
      );
      expect(
        policy.delayForAttempt(0, randomValue: 0),
        const Duration(seconds: 10),
      );
    });

    test('normalizes invalid random input and negative attempts', () {
      const policy = LiveReconnectPolicy(jitterRatio: 0.5);

      expect(
        policy.delayForAttempt(-5, randomValue: double.nan),
        const Duration(seconds: 1),
      );
      expect(
        policy.delayForAttempt(0, randomValue: double.negativeInfinity),
        const Duration(seconds: 1),
      );
    });
  });
}
