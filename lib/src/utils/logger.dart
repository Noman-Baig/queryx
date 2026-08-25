/// Fields that must never appear in debug logs, regardless of where they
/// show up in a request/response (headers, body, etc.).
const List<String> sensitiveFieldNames = [
  'authorization',
  'password',
  'refresh_token',
  'refreshtoken',
  'access_token',
  'accesstoken',
  'token',
  'secret',
  'api_key',
  'apikey',
];

typedef QueryxLogSink = void Function(String message);

/// Development-mode logger. Disabled by default in production — enable
/// explicitly via `QueryClient(logger: QueryxLogger(enabled: true))`.
class QueryxLogger {
  QueryxLogger({this.enabled = false, QueryxLogSink? sink})
      : _sink = sink ?? _defaultSink;

  bool enabled;
  final QueryxLogSink _sink;

  static void _defaultSink(String message) {
    // ignore: avoid_print
    print(message);
  }

  void log(String tag, String message) {
    if (!enabled) return;
    _sink('[$tag] $message');
  }

  /// Redacts sensitive keys before logging a headers/body map. Non-map
  /// values are returned as a plain, non-sensitive string.
  static Object? sanitize(Object? value) {
    if (value is Map) {
      return value.map((k, v) {
        final key = k.toString().toLowerCase();
        final isSensitive = sensitiveFieldNames.any((f) => key.contains(f));
        return MapEntry(k, isSensitive ? '***' : sanitize(v));
      });
    }
    if (value is Iterable) {
      return value.map(sanitize).toList();
    }
    return value;
  }
}
