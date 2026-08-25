import '../errors/query_error.dart';

enum QueryStatus { idle, loading, success, error }

/// A single cached resource plus everything needed to decide freshness and
/// eviction. One [CacheEntry] is shared by every observer of the same
/// query key — this is what makes deduplication and cross-widget cache
/// sharing work.
class CacheEntry<T> {
  CacheEntry({
    required this.staleTime,
    required this.cacheTime,
  });

  T? data;
  QueryError? error;
  QueryStatus status = QueryStatus.idle;

  DateTime? updatedAt;
  DateTime? dataFetchedAt;

  /// How long data is considered fresh after [dataFetchedAt].
  Duration staleTime;

  /// How long an entry with zero observers stays in memory before GC.
  Duration cacheTime;

  bool isFetching = false;
  bool isRefreshing = false;
  int retryCount = 0;

  /// In-flight request future, used for deduplication: concurrent callers
  /// for the same key attach to this instead of issuing a new request.
  Future<T>? inFlight;

  /// Widgets/controllers currently observing this entry. Managed by
  /// [QueryClient]; when this drops to zero, garbage collection begins.
  int observerCount = 0;

  bool get hasData => data != null && status == QueryStatus.success;
  bool get hasError => error != null && status == QueryStatus.error;

  bool get isStale {
    if (dataFetchedAt == null) return true;
    return DateTime.now().difference(dataFetchedAt!) > staleTime;
  }

  void setSuccess(T value) {
    data = value;
    error = null;
    status = QueryStatus.success;
    updatedAt = DateTime.now();
    dataFetchedAt = updatedAt;
    retryCount = 0;
  }

  void setError(QueryError err) {
    error = err;
    status = QueryStatus.error;
    updatedAt = DateTime.now();
  }
}
