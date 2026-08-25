# Roadmap

This tracks the full product spec against what's actually implemented in
`0.1.0`, so nothing is oversold. Contributions welcome on anything marked
TODO.

## ✅ Implemented in core (`queryx` 0.1.0)

- Query engine: `Query<T>`, structured `QueryKey` with order-independent
  hashing, states (`idle/loading/success/error` + `isFetching`/`isRefreshing`
  booleans), `refetch()`/`refresh()`/`invalidate()`/`reset()`/`cancel()`.
- Automatic request deduplication (in-flight future sharing per key).
- Smart caching: `staleTime`, `cacheTime`, background refetch-while-stale.
- Cache invalidation: exact key, prefix match, and predicate-based.
- Mutations with full lifecycle (`onMutate`/`onSuccess`/`onError`/
  `onSettled`) and optimistic-update snapshot/rollback pattern.
- **Direct cache writes**: `client.setQueryData()`, `client.getQueryData()`,
  `client.updateQueryData()` — the primitives optimistic updates and UI
  bindings (Riverpod/GetX) are built on. A mutation's optimistic update now
  writes straight into the shared cache entry, so every widget observing
  that query updates instantly, not just the one that triggered the
  mutation.
- Retry: exponential backoff + jitter, default transient-error
  classification, fully custom `shouldRetry` override.
- Race-condition protection: a stale, slower response can't overwrite a
  newer one for the same query.
- Cancellation: every code path resolves to a clean terminal state, nothing
  hangs in `loading` forever.
- Garbage collection: unused entries evicted after `cacheTime` once
  observer count hits zero.
- Normalized `QueryError` (never raw transport exceptions) with a pluggable
  `ErrorMapper`.
- Single-flight 401 → refresh → retry coordination
  (`configureAuthRefresh`/`handleUnauthorized`).
- Network-aware refetch-on-reconnect via the `NetworkMonitor` abstraction.
- Pagination: both traditional (page/limit/offset) and cursor-style via
  `InfiniteQuery<T, P>`, with `fetchNextPage`/`fetchPreviousPage`, dedup
  against concurrent page requests.
- Transport-agnostic `HttpClientAdapter` (no hard Dio dependency in core).
- Persistence *interfaces* (`CacheStorage`, `Serializer<T>`,
  `CachePersistenceConfig` with `version` for schema migration).
- Reactive `Stream<void>` + synchronous listener API on `Query`/`Mutation`
  for building any UI-binding on top.
- Debug snapshot (`client.debugSnapshot()`) for basic DevTools-style
  inspection.
- Sanitizing dev-mode logger (`QueryxLogger`) that redacts tokens/passwords.
- Unit tests for key hashing, retry/backoff, dedup, caching, invalidation,
  mutations + rollback, and infinite pagination.

## 🚧 Designed but not yet built

- **`queryx_dio`** as its own published package (today: reference adapter
  in `example/lib/dio_http_client_adapter.dart`, not yet extracted).
- **`queryx_persistence`**: concrete `CacheStorage` adapters for Hive,
  Isar, and SQLite, plus disk→memory cache hydration on startup.
- **`queryx_riverpod`** / **`queryx_getx`**: idiomatic `queryProvider`- and
  controller-style bindings. Core already exposes everything needed
  (`Query.stream`, `addListener`) — these are thin wrappers.
- **Offline mutation queue**: persisting mutations made while offline and
  replaying them on reconnect, with idempotency keys.
- **Request queueing** for poor-connectivity conditions (distinct from the
  offline mutation queue).
- **App-lifecycle awareness** (`refetchOnResume`, pause polling when
  backgrounded) — `QueryOptions.refetchOnResume`/`pollingInterval` exist,
  but the actual `AppLifecycleState` hook lives in the Flutter-facing
  package, not core.
- **Request priority** (high/normal/low scheduling) — deferred until
  benchmarks show it's actually needed, per the spec's own guidance.
- **Isolate-based JSON parsing** for large payloads.
- **Visual DevTools panel** (today: `debugSnapshot()` returns structured
  data; no UI yet).
- **Debounced query helper** for search/autocomplete (composable today via
  a debounce wrapper around `refetch()`; not yet a first-class API).
- Full CI pipeline (analyze/format/test/build-matrix across
  Android/iOS/Web/macOS/Windows/Linux) and pub.dev publishing checklist.
