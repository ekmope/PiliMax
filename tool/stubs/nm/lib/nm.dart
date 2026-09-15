/// Stub implementation of nm (NetworkManager client) for Android builds.
/// The real nm package's hook/build.dart references objective_c which
/// breaks Android builds with iOS-only Architecture.arm64e.
library nm;

class NetworkManagerClient {}
class NetworkManagerSettings {}
