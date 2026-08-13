import 'package:PiliMax/pilimax/http/single_flight.dart';

final class AccountActivationCoordinator<K> {
  final SingleFlight<K> _inFlight = SingleFlight<K>();

  Future<void> activate({
    required K key,
    required bool Function() isActivated,
    required Future<void> Function() request,
    required void Function(bool value) setActivated,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) {
    if (isActivated()) return Future<void>.value();
    return _inFlight.run(key, () async {
      if (isActivated()) return;
      try {
        await request();
        setActivated(true);
      } catch (error, stackTrace) {
        setActivated(false);
        onError(error, stackTrace);
      }
    });
  }
}
