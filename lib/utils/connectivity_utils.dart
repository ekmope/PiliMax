import 'package:PiliMax/utils/platform_utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

abstract final class ConnectivityUtils {
  static Future<bool> get isWiFi async {
    try {
      return PlatformUtils.isMobile &&
          (await Connectivity().checkConnectivity()).contains(
            ConnectivityResult.wifi,
          );
    } catch (_) {
      return true;
    }
  }

  /// Returns false when the platform cannot determine the active network.
  ///
  /// The regular [isWiFi] getter intentionally fails open for existing
  /// quality-selection behavior. A user-enabled Wi-Fi-only autoplay rule must
  /// fail closed instead, leaving playback available through the manual action.
  static Future<bool> get isWiFiStrict async {
    if (!PlatformUtils.isMobile) return false;
    try {
      return (await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 3),
      )).contains(
        ConnectivityResult.wifi,
      );
    } catch (_) {
      return false;
    }
  }
}
