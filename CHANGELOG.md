# Changelog

## 0.1.1

Initial release of the core server-state engine.

- `QueryClient`, `Query<T>`, `Mutation<T,V,C>`, `InfiniteQuery<T,P>`.
- Deduplication, caching (staleTime/cacheTime), invalidation, garbage
  collection.
- Retry with exponential backoff + jitter.
- Optimistic updates with snapshot/rollback.
- Normalized `QueryError` + pluggable `ErrorMapper`.
- Single-flight auth-refresh coordination.
- Transport-agnostic `HttpClientAdapter`; persistence interfaces.
- Unit test suite covering the engine's core guarantees.

See `ROADMAP.md` for what's planned next (Dio/Riverpod/GetX/persistence
adapters, offline mutation queue, DevTools UI).
