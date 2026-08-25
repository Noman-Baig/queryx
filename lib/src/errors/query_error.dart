/// Category of a normalized [QueryError]. Kept intentionally small and
/// UI-actionable rather than mirroring every possible transport exception.
enum QueryErrorType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  validation,
  server,
  parsing,
  cancelled,
  unknown,
}

/// The single error shape that ever reaches application code. Adapters
/// (Dio, http, custom) are responsible for translating their own exceptions
/// into a [QueryError] via an [ErrorMapper] — the engine never leaks raw
/// transport exceptions to the UI layer.
class QueryError implements Exception {
  QueryError({
    required this.type,
    required this.message,
    this.statusCode,
    this.code,
    this.details,
    this.originalError,
    this.stackTrace,
  });

  final QueryErrorType type;
  final String message;
  final int? statusCode;
  final String? code;
  final Object? details;
  final Object? originalError;
  final StackTrace? stackTrace;

  factory QueryError.cancelled([Object? original]) => QueryError(
        type: QueryErrorType.cancelled,
        message: 'Request was cancelled',
        originalError: original,
      );

  factory QueryError.network(Object? original, [StackTrace? st]) => QueryError(
        type: QueryErrorType.network,
        message: 'Network error',
        originalError: original,
        stackTrace: st,
      );

  factory QueryError.timeout(Object? original, [StackTrace? st]) => QueryError(
        type: QueryErrorType.timeout,
        message: 'Request timed out',
        originalError: original,
        stackTrace: st,
      );

  factory QueryError.unknown(Object? original, [StackTrace? st]) => QueryError(
        type: QueryErrorType.unknown,
        message: original?.toString() ?? 'Unknown error',
        originalError: original,
        stackTrace: st,
      );

  bool get isRetryable {
    switch (type) {
      case QueryErrorType.network:
      case QueryErrorType.timeout:
      case QueryErrorType.server:
        return true;
      case QueryErrorType.unauthorized:
      case QueryErrorType.forbidden:
      case QueryErrorType.notFound:
      case QueryErrorType.validation:
      case QueryErrorType.parsing:
      case QueryErrorType.cancelled:
      case QueryErrorType.unknown:
        return false;
    }
  }

  @override
  String toString() =>
      'QueryError(type: $type, statusCode: $statusCode, code: $code, message: $message)';
}

/// Converts a raw transport-layer exception (Dio, http, custom) into a
/// normalized [QueryError]. Supply a custom mapper to [QueryClient] to
/// support backend-specific error envelopes, e.g.:
/// ```dart
/// {"success": false, "message": "Invalid request", "code": "INVALID_REQUEST"}
/// {"error": {"message": "...", "code": "..."}}
/// ```
typedef ErrorMapper = QueryError Function(Object error, StackTrace stackTrace);

QueryError defaultErrorMapper(Object error, StackTrace stackTrace) {
  if (error is QueryError) return error;
  return QueryError.unknown(error, stackTrace);
}
