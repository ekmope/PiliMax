import 'dart:async';

import 'package:PiliMax/http/account_activation_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('coalesces concurrent activation and marks success once', () async {
    final coordinator = AccountActivationCoordinator<String>();
    final release = Completer<void>();
    var activated = false;
    var requests = 0;
    var errors = 0;

    Future<void> activate() => coordinator.activate(
      key: 'account',
      isActivated: () => activated,
      request: () async {
        requests++;
        await release.future;
      },
      setActivated: (value) => activated = value,
      onError: (_, _) => errors++,
    );

    final first = activate();
    final second = activate();

    expect(identical(first, second), isTrue);
    expect(requests, 1);
    expect(activated, isFalse);

    release.complete();
    await Future.wait([first, second]);

    expect(activated, isTrue);
    expect(errors, 0);
  });

  test('keeps failure retryable and activates on the next request', () async {
    final coordinator = AccountActivationCoordinator<String>();
    var activated = false;
    var requests = 0;
    var errors = 0;

    Future<void> activate() => coordinator.activate(
      key: 'account',
      isActivated: () => activated,
      request: () async {
        requests++;
        if (requests == 1) throw StateError('rejected');
      },
      setActivated: (value) => activated = value,
      onError: (_, _) => errors++,
    );

    await activate();
    expect(activated, isFalse);
    expect(errors, 1);

    await activate();
    expect(requests, 2);
    expect(activated, isTrue);
  });
}
