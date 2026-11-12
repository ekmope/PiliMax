import 'package:PiliMax/pilimax/live/live_message_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounds sustained socket ingestion without a rendered frame', () {
    final buffer = LiveMessageBuffer<int>();
    for (var i = 0; i < 100000; i++) {
      buffer.add(i);
      expect(buffer.length, lessThanOrEqualTo(550));
    }
    expect(buffer.snapshot.last, 99999);
    expect(
      buffer.snapshot,
      orderedEquals(
        List.generate(buffer.length, (i) => 100000 - buffer.length + i),
      ),
    );
  });

  test('trims in batches and keeps the latest messages', () {
    final buffer = LiveMessageBuffer<int>()
      ..addAll(List.generate(550, (i) => i));
    expect(buffer.length, 550);
    expect(buffer.add(550), 51);
    expect(buffer.length, 500);
    expect(buffer.snapshot.first, 51);
    expect(buffer.snapshot.last, 550);
  });

  test(
    'a paused sliver snapshot keeps valid indices after background trims',
    () {
      final buffer = LiveMessageBuffer<int>()
        ..addAll(List.generate(550, (i) => i));
      final rendered = buffer.snapshot;
      buffer.addAll(List.generate(10000, (i) => i + 550));
      expect(rendered, orderedEquals(List.generate(550, (i) => i)));
      expect(() => rendered[549], returnsNormally);
      expect(buffer.snapshot.last, 10549);
      expect(identical(rendered, buffer.snapshot), isFalse);
      expect(() => rendered.add(-1), throwsUnsupportedError);
    },
  );

  test('equal lengths still have distinct revisions for resume refresh', () {
    final buffer = LiveMessageBuffer<int>()
      ..addAll(List.generate(500, (i) => i));
    final renderedRevision = buffer.revision;
    buffer.addAll(List.generate(51, (i) => i + 500));
    expect(buffer.length, 500);
    expect(buffer.revision, isNot(renderedRevision));
    expect(buffer.snapshot.first, 51);
  });

  test('filter and clear invalidate snapshots without retaining old data', () {
    final buffer = LiveMessageBuffer<int>()..addAll([1, 2, 3]);
    final rendered = buffer.snapshot;
    final revision = buffer.revision;
    buffer.removeWhere((item) => item == 2);
    expect(buffer.revision, greaterThan(revision));
    expect(buffer.snapshot, [1, 3]);
    expect(rendered, [1, 2, 3]);
    buffer.clear();
    expect(buffer.isEmpty, isTrue);
    expect(buffer.snapshot, isEmpty);
    buffer.add(4);
    expect(buffer.snapshot, [4]);
  });
}
