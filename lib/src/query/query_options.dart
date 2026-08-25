import '../retry/retry_policy.dart';

/// Configuration for a single [Query]. Any field left `null` falls back to
/// the [QueryClient]'s default. Nothing here is "magic" — every behavior
/// that affects network traffic (retry, polling, background refetch) is an
/// explicit, documented option (spec §91: No Magic).
class QueryOptions<T> {
  const QueryOptions({
    this.staleTime,
    this.cacheTime,
    this.retryPolicy,
    this.enabled = true,
    this.refetchOnResume = false,
    this.pollingInterval,
    this.keepPreviousData = false,
  });

  /// How long data is considered fresh after a successful fetch.
  final Duration? staleTime;

  /// How long an entry with zero observers stays cached before GC.
  final Duration? cacheTime;

  final RetryPolicy? retryPolicy;

  /// Whether this query is allowed to run. Set to `false` to implement
  /// dependent queries, e.g. `enabled: userQuery.hasData`.
  final bool enabled;

  /// Refetch automatically when the app returns to the foreground.
  final bool refetchOnResume;

  /// If set, the query refetches on this interval while it has observers.
  /// Automatically stops when observers reach zero, when the app is
  /// backgrounded (if configured), or when connectivity is lost.
  final Duration? pollingInterval;

  /// While a new key's data is loading, keep showing the previous key's
  /// data instead of flashing to a loading state (useful for paginated
  /// or filtered queries).
  final bool keepPreviousData;

  QueryOptions<T> mergeWithDefaults({
    required Duration defaultStaleTime,
    required Duration defaultCacheTime,
    required RetryPolicy defaultRetryPolicy,
  }) {
    return QueryOptions<T>(
      staleTime: staleTime ?? defaultStaleTime,
      cacheTime: cacheTime ?? defaultCacheTime,
      retryPolicy: retryPolicy ?? defaultRetryPolicy,
      enabled: enabled,
      refetchOnResume: refetchOnResume,
      pollingInterval: pollingInterval,
      keepPreviousData: keepPreviousData,
    );
  }
}
