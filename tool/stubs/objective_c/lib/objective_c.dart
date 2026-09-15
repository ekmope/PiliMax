/// Stub implementation of objective_c for Android builds.
/// The real objective_c package's hook/build.dart references iOS-only
/// Architecture.arm64e which breaks Android builds.
library objective_c;

class ObjCObject {}
class ObjCClass {}
class ObjCSelector {}
