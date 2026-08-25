/// A structured, deterministic identity for a query.
///
/// Two [QueryKey]s that contain the same logical parts — including nested
/// maps whose entries are in a different order — resolve to the same cache
/// identity. This is what lets `['orders', {'status': 'pending', 'page': 1}]`
/// and `['orders', {'page': 1, 'status': 'pending'}]` share one cache entry.
///
/// A key is any list of primitives, and/or `Map<String, dynamic>` fragments,
/// e.g.:
/// ```dart
/// QueryKey(['users']);
/// QueryKey(['user', userId]);
/// QueryKey(['orders', {'status': 'pending', 'page': 1}]);
/// ```
class QueryKey {
  QueryKey(this.parts);

  final List<Object?> parts;

  /// Stable string identity used for cache lookups, equality, and logging.
  /// Computed lazily and cached on first access.
  String get id => _id ??= _stableId(parts);
  String? _id;

  /// Returns true if [other] is a prefix of this key — used by
  /// `invalidateQueries`/`removeQueries` style partial matching, e.g.
  /// `QueryKey(['users']).isPrefixOf(QueryKey(['users', 1]))`.
  bool isPrefixedBy(QueryKey prefix) {
    if (prefix.parts.length > parts.length) return false;
    for (var i = 0; i < prefix.parts.length; i++) {
      if (_stableValue(parts[i]) != _stableValue(prefix.parts[i])) {
        return false;
      }
    }
    return true;
  }

  static String _stableId(List<Object?> parts) =>
      parts.map(_stableValue).join('/');

  /// Produces a canonical string for a single key segment. Maps are sorted
  /// by key so that argument order never affects the cache identity.
  static String _stableValue(Object? value) {
    if (value == null) return 'null';
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final buf = StringBuffer('{');
      for (final k in sortedKeys) {
        buf.write('$k:${_stableValue(value[k])},');
      }
      buf.write('}');
      return buf.toString();
    }
    if (value is Iterable) {
      return '[${value.map(_stableValue).join(',')}]';
    }
    return value.toString();
  }

  @override
  bool operator ==(Object other) => other is QueryKey && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'QueryKey($id)';
}
