/// Stub implementation of objective_c for Android builds.
/// The real objective_c package's hook/build.dart references iOS-only
/// Architecture.arm64e which breaks Android builds.
library objective_c;

class ObjCObject {}
class ObjCClass {}
class ObjCSelector {}

// Stub types used by jni package's iOS code paths
class NSURL extends ObjCObject {}
class NSArray<T> extends ObjCObject {}
class NSString extends ObjCObject {}
class NSDictionary<K, V> extends ObjCObject {}
class NSData extends ObjCObject {}
class NSError extends ObjCObject {}
class NSDate extends ObjCObject {}
class NSNumber extends ObjCObject {}
class NSNull extends ObjCObject {}
