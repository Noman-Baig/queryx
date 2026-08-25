import 'dart:async';

import '../cache/cache_entry.dart';
import '../errors/query_error.dart';
import '../retry/retry_policy.dart';
import '../utils/logger.dart';
import '../utils/queryx_listenable.dart';
import 'query_key.dart';
import 'query_options.dart';

typedef Fetcher<T> = Future<T> Function();

/// Internal, per-key shared state. Every [Query] handle for the same
/// [QueryKey] reads/writes through the *same* [_QueryCore] instance — this
/// is what gives queryx cross-widget cache sharing, deduplication, and
/// "one refetch updates every observer" for free.
class QueryCore<T> {
  QueryCore(this.key, this.options, this.fetcher, this._logger)
      : entry = CacheEntry<T>(
          staleTime: options.staleTime ?? const Duration(minutes: 5),
          cacheTime: options.cacheTime ?? const Duration(minutes: 30),
        );

  final QueryKey key;
  QueryOptions<T> options;
  Fetcher<T> fetcher;
  final CacheEntry<T> entry;
  final listenable = QueryxListenable();
  final QueryxLogger _logger;

  Timer? gcTimer;
  Timer? pollTimer;
  int _fetchGeneration = 0;

  void addObserver() {
    entry.observerCount++;
    gcTimer?.cancel();
    gcTimer = null;
    _restartPolling();
  }

  void removeObserver() {
    entry.observerCount = (entry.observerCount - 1).clamp(0, 1 << 30);
    if (entry.observerCount == 0) {
      pollTimer?.cancel();
      pollTimer = null;
      gcTimer?.cancel();
      gcTimer = Timer(entry.cacheTime, onGarbageCollect ?? () {});
    }
  }

  /// Set by [QueryClient] to actually remove this core from its registry.
  void Function()? onGarbageCollect;

  void _restartPolling() {
    pollTimer?.cancel();
    final interval = options.pollingInterval;
    if (interval == null || entry.observerCount == 0) return;
    pollTimer = Timer.periodic(interval, (_) {
      if (entry.observerCount == 0) {
        pollTimer?.cancel();
        return;
      }
      unawaited(fetch(background: true));
    });
  }

  /// Runs [fetcher], deduplicating concurrent callers, retrying per
  /// [RetryPolicy], and updating [entry] + notifying observers on every
  /// meaningful transition. [background] fetches keep any existing data
  /// visible instead of flipping status back to `loading`.
  Future<T> fetch({bool background = false, bool force = false}) {
    if (!options.enabled) {
      return entry.data != null
          ? Future.value(entry.data as T)
          : Future.error(QueryError(
              type: QueryErrorType.unknown,
              message: 'Query "${key.id}" is disabled',
            ));
    }

    // Deduplication: attach to the in-flight request instead of firing a
    // second one, unless the caller explicitly forces a fresh fetch.
    if (!force && entry.inFlight != null) {
      _logger.log('QUERY', '${key.id} → deduplicated');
      return entry.inFlight!;
    }

    final generation = ++_fetchGeneration;
    entry.isFetching = true;
    entry.isRefreshing = background && entry.hasData;
    if (!background || !entry.hasData) {
      entry.status = QueryStatus.loading;
    }
    listenable.notifyListeners();
    _logger.log('QUERY', '${key.id} → fetching');

    final future = _runWithRetry(generation);
    entry.inFlight = future;
    return future;
  }

  Future<T> _runWithRetry(int generation) async {
    final policy = options.retryPolicy ?? RetryPolicy.none;
    final sw = Stopwatch()..start();
    var attempt = 0;
    while (true) {
      try {
        final result = await fetcher();
        if (generation != _fetchGeneration) {
          // A newer fetch superseded this one (spec §82: race protection) —
          // don't let a stale, slower response overwrite fresher data.
          throw QueryError.cancelled();
        }
        entry.setSuccess(result);
        entry.isFetching = false;
        entry.isRefreshing = false;
        entry.inFlight = null;
        listenable.notifyListeners();
        _logger.log('QUERY', '${key.id} → success ${sw.elapsedMilliseconds}ms');
        return result;
      } catch (e, st) {
        final error = e is QueryError ? e : defaultErrorMapper(e, st);
        if (error.type == QueryErrorType.cancelled) {
          entry.isFetching = false;
          entry.isRefreshing = false;
          entry.inFlight = null;
          listenable.notifyListeners();
          rethrow;
        }
        if (policy.shouldRetry(error, attempt)) {
          entry.retryCount = attempt + 1;
          final delay = policy.delayFor(attempt);
          _logger.log('QUERY',
              '${key.id} → retry ${attempt + 1}/${policy.maxRetries} in ${delay.inMilliseconds}ms');
          attempt++;
          await Future<void>.delayed(delay);
          continue;
        }
        entry.setError(error);
        entry.isFetching = false;
        entry.isRefreshing = false;
        entry.inFlight = null;
        listenable.notifyListeners();
        _logger.log('QUERY', '${key.id} → error: ${error.message}');
        rethrow;
      }
    }
  }

  void invalidate() {
    // A subsequent access will see stale data (dataFetchedAt untouched
    // would still look fresh, so we force it stale explicitly).
    entry.dataFetchedAt = null;
    if (entry.observerCount > 0) {
      unawaited(fetch(background: entry.hasData));
    } else {
      listenable.notifyListeners();
    }
    _logger.log('QUERY', '${key.id} → invalidated');
  }

  void reset() {
    entry.data = null;
    entry.error = null;
    entry.status = QueryStatus.idle;
    entry.dataFetchedAt = null;
    entry.retryCount = 0;
    listenable.notifyListeners();
  }

  void cancel() {
    _fetchGeneration++; // orphans any in-flight fetch's result handling
    entry.inFlight = null;
    entry.isFetching = false;
    entry.isRefreshing = false;
    listenable.notifyListeners();
  }

  void dispose() {
    gcTimer?.cancel();
    pollTimer?.cancel();
    listenable.dispose();
  }
}

/// The public, per-consumer handle to a query. Multiple [Query] instances
/// for the same key all read/write through one shared [QueryCore] — this is
/// what implements request deduplication and cross-widget cache sharing.
///
/// ```dart
/// final usersQuery = client.query(
///   QueryKey(['users']),
///   () => api.get('/users'),
/// );
/// await usersQuery.refetch();
/// print(usersQuery.data);
/// ```
class Query<T> {
  Query(this._core) {
    _core.addObserver();
  }

  final QueryCore<T> _core;
  bool _disposed = false;

  QueryKey get key => _core.key;

  T? get data => _core.entry.data;
  QueryError? get error => _core.entry.error;
  QueryStatus get status => _core.entry.status;

  bool get isLoading => _core.entry.status == QueryStatus.loading;
  bool get isFetching => _core.entry.isFetching;
  bool get isRefreshing => _core.entry.isRefreshing;
  bool get isError => _core.entry.hasError;
  bool get isSuccess => _core.entry.status == QueryStatus.success;
  bool get isStale => _core.entry.isStale;
  bool get isCached => _core.entry.data != null;
  bool get hasData => _core.entry.hasData;

  /// Broadcast stream of state changes, for `StreamBuilder` or other
  /// reactive integrations (spec §50).
  Stream<void> get stream => _core.listenable.stream;

  void addListener(void Function() listener) =>
      _core.listenable.addListener(listener);

  void removeListener(void Function() listener) =>
      _core.listenable.removeListener(listener);

  /// Fetches if there's no data yet, or the cached data is stale. Safe to
  /// call from every observer on mount — dedup means only one request
  /// actually goes out.
  Future<T> ensureFetched() {
    if (_core.entry.hasData && !_core.entry.isStale) {
      return Future.value(_core.entry.data as T);
    }
    return _core.fetch(background: _core.entry.hasData);
  }

  /// Forces a network request regardless of freshness.
  Future<T> refetch() => _core.fetch(force: true);

  /// Alias for [refetch], intended for `RefreshIndicator.onRefresh` —
  /// existing data stays visible while refreshing (spec §23).
  Future<T> refresh() => _core.fetch(force: true, background: true);

  /// Marks the cached data stale and, if this query currently has
  /// observers, triggers a background refetch.
  void invalidate() => _core.invalidate();

  /// Clears cached data/error and returns to the idle state.
  void reset() => _core.reset();

  /// Cancels any in-flight request for this query. Resolves lifecycle to a
  /// clean, non-loading state rather than hanging forever (spec §83).
  void cancel() => _core.cancel();

  /// Releases this observer. Once every [Query] handle for a key is
  /// disposed, the underlying cache entry starts its [cacheTime] countdown
  /// toward garbage collection.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _core.removeObserver();
  }
}
