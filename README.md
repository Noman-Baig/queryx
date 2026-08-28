<p align="center">
  <img
    src="https://raw.githubusercontent.com/Noman-Baig/queryx_dio/main/assets/logo.jpg"
    alt="QueryX"
    width="220"
    style="border-radius: 24px;"
  />
</p>

**QueryX**

It is a lightweight, framework-agnostic server-state engine built for Dart & Flutter applications.

queryx is not another state-management framework, and not "a Dio wrapper with
100 features." It solves one problem well: **server state + API lifecycle +
caching + synchronization.** You keep whatever you already use for UI state —
Riverpod, GetX, Bloc, Provider, `ChangeNotifier`, or plain `setState`.

```dart
final users = client.query(
  QueryKey(['users']),
  () => api.get('/users'),
);

await users.ensureFetched();
users.data;        // List<User>?
users.isLoading;    // bool
users.isFetching;   // bool
users.error;         // QueryError?
users.refetch();
users.invalidate();
```

That's it — no `loading`/`error` booleans to hand-roll, no duplicate requests
when three widgets ask for the same thing, no stale UI after a mutation.

## Architecture

```
             ┌──────────────┐
             │      UI      │
             └──────┬───────┘
                    │
       ┌────────────▼────────────┐
       │       Integration        │
       │ Riverpod / GetX / etc.   │   ← optional, thin adapters
       └────────────┬────────────┘
                    │
       ┌────────────▼────────────┐
       │       Query Engine       │
       │ Query · Mutation · Cache  │   ← this package (queryx)
       │ Dedup · Retry · Invalidate│
       │ Pagination · Sync         │
       └────────────┬────────────┘
                    │
       ┌────────────▼────────────┐
       │       Cache Engine        │
       │  Memory + Persistence     │
       └────────────┬────────────┘
                    │
       ┌────────────▼────────────┐
       │    Transport Adapter      │
       │  Dio / http / Custom      │   ← you bring the HTTP client
       └───────────────────────────┘
```

The core package (`lib/`) has **zero dependency on Flutter or Dio**. It's
pure Dart, so it's trivially unit-testable and usable outside Flutter too.
Transport, persistence, and UI-binding are all adapters that plug in from
the outside:

| Package                | Purpose                                     | Status                                                        |
| ---------------------- | ------------------------------------------- | ------------------------------------------------------------- |
| `queryx`             | Core engine (this package)                  | ✅ implemented                                                |
| `queryx_dio`         | `HttpClientAdapter` backed by Dio         | reference impl in`example/lib/dio_http_client_adapter.dart` |
| `queryx_persistence` | `CacheStorage` backed by Hive/Isar/SQLite | interface defined, adapters TODO                              |
| `queryx_riverpod`    | `queryProvider` bindings                  | TODO — see ROADMAP.md                                        |
| `queryx_getx`        | GetX controller bindings                    | TODO — see ROADMAP.md                                        |

## Core concepts

### Query keys

Keys are structured, not stringly-typed, and hash deterministically —
argument order in a map never affects cache identity:

```dart
QueryKey(['users']);
QueryKey(['user', userId]);
QueryKey(['orders', {'status': 'pending', 'page': 1}]);
```

### Deduplication + cache sharing

Every `client.query(key, fetcher)` call for an equivalent key shares one
underlying cache entry. Three widgets mounting at once still fire exactly
one HTTP request; all three receive the same result.

### Freshness

```dart
QueryOptions(
  staleTime: Duration(minutes: 5),  // how long data is "fresh"
  cacheTime: Duration(minutes: 30), // how long unused data stays cached
)
```

Stale data is still shown instantly while a background refetch runs — no
unnecessary spinners on every screen visit.

### Mutations + optimistic updates

`setQueryData`/`getQueryData`/`updateQueryData` are the primitives for
writing straight into the cache — this is what makes an optimistic update
show up instantly on every widget observing that query, not just the one
that triggered the mutation:

```dart
final likePost = client.mutation<int, void, int>(
  (_) => api.post('/posts/1/like'),
  options: MutationOptions(
    onMutate: (_) async {
      final snapshot = client.getQueryData<int>(likesKey)!;
      client.updateQueryData<int>(likesKey, (n) => (n ?? 0) + 1); // instant UI update
      return snapshot;
    },
    onSuccess: (serverCount, _, __) => client.setQueryData(likesKey, serverCount),
    onError: (error, _, snapshot) => client.setQueryData(likesKey, snapshot!), // rollback
  ),
);
await likePost.mutateAsync(null);
```

### Retry

Exponential backoff with jitter, and only for errors that are plausibly
transient (network, timeout, 5xx) — never 4xx/validation, never a cancelled
request, unless you override `shouldRetry` yourself:

```dart
RetryPolicy(
  maxRetries: 3,
  initialDelay: Duration(seconds: 1),
  maxDelay: Duration(seconds: 30),
  shouldRetry: (error, attempt) => error.statusCode == 429,
)
```

### Pagination

```dart
final feed = InfiniteQuery<Post, int>(
  key: QueryKey(['posts']),
  initialPageParam: 0,
  fetchPage: (page) => api.getPosts(page: page ?? 0),
);
await feed.fetchNextPage();
feed.items;         // flattened across all loaded pages
feed.hasNextPage;
```

### Errors

Raw transport exceptions never reach the UI. Every adapter maps its own
exceptions into a single `QueryError` shape (`type`, `statusCode`, `code`,
`message`, `details`) — see `example/lib/dio_http_client_adapter.dart` for a
full Dio → `QueryError` mapping, including custom backend error envelopes.

### Auth / token refresh

```dart
client.configureAuthRefresh(() => authRepo.refreshAccessToken());
```

If ten requests hit 401 simultaneously, queryx makes exactly one refresh
call and every caller awaits the same in-flight `Future` — never 3–10
concurrent refresh requests.

### DevTools

```dart
client.debugSnapshot().forEach(print);
// [users] status: success, observers: 2, cached: true, stale: false
```

## Installation

```yaml
dependencies:
  queryx: ^0.1.0
```

## Design principles

1. Easy things must be extremely easy: `query(['users'], fetcher)`.
2. Difficult things must be possible: custom cache, transport, retry,
   serialization, persistence, auth — all swappable.
3. No magic: retry, polling, background refetch, and offline queueing are
   all explicit, documented options — never surprise network traffic.
4. State-management agnostic: queryx never tells you how to build your UI.

See `ROADMAP.md` for what's implemented today versus what's planned from the
full specification.
