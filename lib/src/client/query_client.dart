import 'dart:async';

import '../errors/query_error.dart';
import '../mutation/mutation.dart';
import '../network/network_monitor.dart';
import '../query/query.dart';
import '../query/query_key.dart';
import '../query/query_options.dart';
import '../retry/retry_policy.dart';
import '../utils/logger.dart';

/// The single object that coordinates cache, queries, mutations, network
/// state, and (optionally) auth token refresh for an app — or a portion of
/// one; large apps can run [multiple clients][], one per backend.
///
/// [multiple clients]: for example a `mainApiClient` and an `adminApiClient`
/// so their caches never collide.
///
/// ```dart
/// final queryClient = QueryClient(
///   defaultStaleTime: const Duration(minutes: 5),
///   defaultCacheTime: const Duration(minutes: 30),
///   defaultRetryPolicy: const RetryPolicy(maxRetries: 3),
/// );
/// ```
class QueryClient {
  QueryClient({
    this.defaultStaleTime = const Duration(minutes: 5),
    this.defaultCacheTime = const Duration(minutes: 30),
    this.defaultRetryPolicy = const RetryPolicy(maxRetries: 3),
    NetworkMonitor? networkMonitor,
    QueryxLogger? logger,
    this.onUnauthorized,
  })  : networkMonitor = networkMonitor ?? AlwaysOnlineNetworkMonitor(),
        logger = logger ?? QueryxLogger() {
    _networkSub = this.networkMonitor.onStatusChange.listen(_onNetworkChange);
  }

  final Duration defaultStaleTime;
  final Duration defaultCacheTime;
  final RetryPolicy defaultRetryPolicy;
  final NetworkMonitor networkMonitor;
  final QueryxLogger logger;

  /// Called on a 401 that can't be resolved by [refreshTokens]. Typically
  /// wired to log the user out / navigate to a login screen.
  final void Function()? onUnauthorized;

  final Map<String, QueryCore<dynamic>> _registry = {};
  StreamSubscription<NetworkStatus>? _networkSub;

  /// Single-flight guard for token refresh: if several requests hit 401 at
  /// once, only one refresh call is made and every caller awaits it
  /// (spec §15 — never fire 3–10 refresh requests simultaneously).
  Future<void> Function()? _refreshTokens;
  Future<void>? _refreshInFlight;

  /// Registers the function used to refresh the access token. Call this
  /// once during app/auth setup; adapters call [handleUnauthorized] when a
  /// request comes back 401.
  void configureAuthRefresh(Future<void> Function() refresh) {
    _refreshTokens = refresh;
  }

  /// Coordinates a single in-flight token refresh across concurrent 401s.
  /// Returns normally if refresh succeeded (caller should retry its
  /// original request); rethrows if refresh itself failed.
  Future<void> handleUnauthorized() {
    if (_refreshTokens == null) {
      onUnauthorized?.call();
      return Future.error(
        QueryError(
          type: QueryErrorType.unauthorized,
          message: 'Unauthorized and no refresh handler configured',
        ),
      );
    }
    _refreshInFlight ??= _refreshTokens!().whenComplete(() {
      _refreshInFlight = null;
    }).catchError((Object e) {
      onUnauthorized?.call();
      throw e;
    });
    return _refreshInFlight!;
  }

  /// Gets or creates the shared [Query] handle for [key]. Every call with
  /// an equivalent key — from any widget, anywhere — shares one
  /// [QueryCore], which is what makes deduplication and cache-sharing work.
  Query<T> query<T>(
    QueryKey key,
    Fetcher<T> fetcher, {
    QueryOptions<T>? options,
  }) {
    final resolved = (options ?? const QueryOptions()).mergeWithDefaults(
      defaultStaleTime: defaultStaleTime,
      defaultCacheTime: defaultCacheTime,
      defaultRetryPolicy: defaultRetryPolicy,
    );

    final existing = _registry[key.id];
    late final QueryCore<T> core;
    if (existing != null) {
      core = existing as QueryCore<T>;
      core.options = resolved;
      core.fetcher = fetcher;
    } else {
      core = QueryCore<T>(key, resolved, fetcher, logger);
      core.onGarbageCollect = () {
        _registry.remove(key.id);
        core.dispose();
        logger.log('QUERY', '${key.id} → garbage collected');
      };
      _registry[key.id] = core;
    }
    return Query<T>(core);
  }

  /// Directly writes [data] into the cache for [key] and notifies every
  /// current observer immediately. This is the primitive optimistic
  /// updates (and UI bindings like `queryx_riverpod`/`queryx_getx`) are
  /// built on — e.g. flipping a "liked" count in the cache the instant a
  /// mutation starts, before the server has responded.
  ///
  /// If no query has been registered for [key] yet, a cache entry is
  /// created holding just this data; a later `client.query(key, fetcher)`
  /// call attaches a real fetcher without clobbering the data written here.
  void setQueryData<T>(QueryKey key, T data) {
    final existing = _registry[key.id];
    if (existing != null) {
      final core = existing as QueryCore<T>;
      core.entry.setSuccess(data);
      core.listenable.notifyListeners();
      logger.log('QUERY', '${key.id} → data set manually');
      return;
    }

    final resolved = QueryOptions<T>().mergeWithDefaults(
      defaultStaleTime: defaultStaleTime,
      defaultCacheTime: defaultCacheTime,
      defaultRetryPolicy: defaultRetryPolicy,
    );
    final core = QueryCore<T>(key, resolved, () => Future.value(data), logger)
      ..entry.setSuccess(data);
    core.onGarbageCollect = () {
      _registry.remove(key.id);
      core.dispose();
    };
    _registry[key.id] = core;
    logger.log('QUERY', '${key.id} → data set manually (no prior query)');
  }

  /// Functional variant of [setQueryData]: receives the current cached
  /// value (`null` if none) and writes back whatever it returns. Handy for
  /// optimistic updates that need to read-then-modify, e.g.
  /// `client.updateQueryData<int>(key, (likes) => (likes ?? 0) + 1)`.
  void updateQueryData<T>(QueryKey key, T Function(T? current) updater) {
    setQueryData<T>(key, updater(getQueryData<T>(key)));
  }

  /// Reads the currently cached value for [key] without creating an
  /// observer or triggering a fetch. Returns `null` if nothing is cached.
  T? getQueryData<T>(QueryKey key) {
    final core = _registry[key.id];
    if (core == null) return null;
    return core.entry.data as T?;
  }

  /// Creates a mutation. Mutations aren't cached/deduplicated by key —
  /// each call site owns its own [Mutation] instance.
  Mutation<T, V, C> mutation<T, V, C>(
    MutationFn<T, V> fn, {
    MutationOptions<T, V, C>? options,
  }) =>
      Mutation<T, V, C>(fn, options: options);

  /// Marks [key] (and, if [exact] is false, every key it prefixes) stale.
  /// Queries with active observers refetch in the background immediately;
  /// queries with none simply refetch next time they're observed.
  void invalidateQueries(QueryKey key, {bool exact = true}) {
    for (final core in _registry.values) {
      final matches = exact ? core.key == key : core.key.isPrefixedBy(key);
      if (matches) core.invalidate();
    }
  }

  /// Invalidates every query whose key satisfies [predicate] — for
  /// pattern-based invalidation beyond simple prefix matching.
  void invalidateWhere(bool Function(QueryKey key) predicate) {
    for (final core in _registry.values) {
      if (predicate(core.key)) core.invalidate();
    }
  }

  /// Preloads [key] into the cache without any observer attached, so a
  /// later screen opening it finds data already there.
  Future<T> prefetch<T>(
    QueryKey key,
    Fetcher<T> fetcher, {
    QueryOptions<T>? options,
  }) {
    final resolved = (options ?? const QueryOptions()).mergeWithDefaults(
      defaultStaleTime: defaultStaleTime,
      defaultCacheTime: defaultCacheTime,
      defaultRetryPolicy: defaultRetryPolicy,
    );
    final existing = _registry[key.id];
    QueryCore<T> core;
    if (existing != null) {
      core = existing as QueryCore<T>;
    } else {
      core = QueryCore<T>(key, resolved, fetcher, logger);
      core.onGarbageCollect = () {
        _registry.remove(key.id);
        core.dispose();
      };
      _registry[key.id] = core;
      // No observer is attached, so start the cacheTime GC clock now —
      // prefetched-but-never-viewed data shouldn't live forever.
      core.gcTimer = Timer(core.entry.cacheTime, core.onGarbageCollect!);
    }
    if (core.entry.hasData && !core.entry.isStale) {
      return Future.value(core.entry.data as T);
    }
    return core.fetch(background: core.entry.hasData);
  }

  /// Removes a query from the registry entirely, including its cached data.
  void removeQueries(QueryKey key, {bool exact = true}) {
    final toRemove = _registry.entries
        .where(
            (e) => exact ? e.value.key == key : e.value.key.isPrefixedBy(key))
        .map((e) => e.key)
        .toList();
    for (final id in toRemove) {
      _registry.remove(id)?.dispose();
    }
  }

  /// Snapshot of cache state for every registered query — powers DevTools
  /// (spec §62).
  List<QueryDebugInfo> debugSnapshot() {
    return _registry.values.map((core) {
      return QueryDebugInfo(
        keyId: core.key.id,
        status: core.entry.status.name,
        observers: core.entry.observerCount,
        isCached: core.entry.data != null,
        isStale: core.entry.isStale,
        retryCount: core.entry.retryCount,
        lastError: core.entry.error?.message,
        updatedAt: core.entry.updatedAt,
      );
    }).toList();
  }

  void _onNetworkChange(NetworkStatus status) {
    if (status != NetworkStatus.online) return;
    // Connection just returned: refetch every stale, currently-observed
    // query. Queries with no observers are left alone until next viewed.
    for (final core in _registry.values) {
      if (core.entry.observerCount > 0 && core.entry.isStale) {
        unawaited(core.fetch(background: core.entry.hasData));
      }
    }
  }

  /// Disposes every cached query and stops listening to connectivity.
  /// Call when the client itself is being torn down (rare — usually a
  /// [QueryClient] lives for the app's lifetime).
  void dispose() {
    for (final core in _registry.values) {
      core.dispose();
    }
    _registry.clear();
    _networkSub?.cancel();
    networkMonitor.dispose();
  }
}

class QueryDebugInfo {
  QueryDebugInfo({
    required this.keyId,
    required this.status,
    required this.observers,
    required this.isCached,
    required this.isStale,
    required this.retryCount,
    required this.lastError,
    required this.updatedAt,
  });

  final String keyId;
  final String status;
  final int observers;
  final bool isCached;
  final bool isStale;
  final int retryCount;
  final String? lastError;
  final DateTime? updatedAt;

  @override
  String toString() =>
      '[$keyId] status: $status, observers: $observers, cached: $isCached, stale: $isStale';
}
