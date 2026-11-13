import 'package:PiliMax/pilimax/http/single_flight.dart';

final class AccountActivationCoordinator<K> {
  final SingleFlight<(K, int?)> _inFlight = SingleFlight<(K, int?)>();

  Future<void> activate({
    required K key,
    required bool Function() isActivated,
    required Future<void> Function() request,
    required void Function(bool value) setActivated,
    required void Function(Object error, StackTrace stackTrace) onError,
    int Function()? generation,
  }) {
    if (isActivated()) return Future<void>.value();
    final revision = generation?.call();
    bool isCurrent() => revision == generation?.call();
    return _inFlight.run((key, revision), () async {
      if (isActivated()) return;
      try {
        await request();
        if (isCurrent()) setActivated(true);
      } catch (error, stackTrace) {
        if (!isCurrent()) return;
        setActivated(false);
        onError(error, stackTrace);
      }
    });
  }
}
