import 'dart:async';

import 'package:PiliMax/http/single_flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SingleFlight', () {
    test('coalesces concurrent operations for the same key', () async {
      final singleFlight = SingleFlight<String>();
      final release = Completer<void>();
      var runs = 0;

      Future<void> operation() async {
        runs++;
        await release.future;
      }

      final first = singleFlight.run('account', operation);
      final second = singleFlight.run('account', operation);

      expect(identical(first, second), isTrue);
      expect(runs, 1);

      release.complete();
      await Future.wait([first, second]);
      expect(runs, 1);
    });

    test('allows a retry after the first operation fails', () async {
      final singleFlight = SingleFlight<String>();
      var runs = 0;

      Future<void> operation() async {
        runs++;
        if (runs == 1) {
          throw StateError('first attempt failed');
        }
      }

      await expectLater(
        singleFlight.run('account', operation),
        throwsStateError,
      );
      await singleFlight.run('account', operation);

      expect(runs, 2);
    });

    test('does not coalesce different keys', () async {
      final singleFlight = SingleFlight<String>();
      final release = Completer<void>();
      var runs = 0;

      Future<void> operation() async {
        runs++;
        await release.future;
      }

      final first = singleFlight.run('first', operation);
      final second = singleFlight.run('second', operation);

      expect(runs, 2);
      release.complete();
      await Future.wait([first, second]);
    });
  });
}
