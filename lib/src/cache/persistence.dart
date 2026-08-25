/// Storage abstraction for persisting cache entries to disk. The core
/// package ships no implementation — plug in `queryx_persistence` (Hive,
/// Isar, SQLite) or your own, so core stays dependency-free.
abstract class CacheStorage {
  Future<void> write(String key, Map<String, dynamic> value);
  Future<Map<String, dynamic>?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();

  /// Schema/version tag written alongside cached data. If the stored
  /// version doesn't match [CachePersistenceConfig.version] on hydration,
  /// the entry is treated as incompatible and dropped rather than crashing
  /// deserialization.
  Future<int?> readVersion();
  Future<void> writeVersion(int version);
}

/// Per-type encode/decode so the persistence layer never needs generated
/// code or reflection.
class Serializer<T> {
  const Serializer({required this.encode, required this.decode});

  final Map<String, dynamic> Function(T value) encode;
  final T Function(Map<String, dynamic> json) decode;
}

class CachePersistenceConfig {
  const CachePersistenceConfig({
    required this.storage,
    this.version = 1,
    this.encrypt = false,
  });

  final CacheStorage storage;

  /// Bump this when the shape of cached models changes. Mismatched
  /// versions invalidate old cache instead of throwing on deserialize.
  final int version;

  /// Whether [storage] should encrypt at rest. This is a hint for the
  /// storage adapter to act on — encryption is never mandatory, since it
  /// adds overhead not every app needs.
  final bool encrypt;
}
