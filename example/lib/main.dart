// Run with: dart run example/lib/main.dart
//
// A fake, in-memory "backend" stands in for a real API so this example runs
// with zero network dependency. Swap `fakeApi.*` calls for
// `dio.get(...)` / `httpClientAdapter.request(...)` in a real app.
// ignore_for_file: avoid_print
import 'package:queryx/queryx.dart';

Future<void> main() async {
  final client = QueryClient(
    defaultStaleTime: const Duration(seconds: 30),
    defaultCacheTime: const Duration(minutes: 5),
    defaultRetryPolicy: const RetryPolicy(maxRetries: 3),
    logger: QueryxLogger(enabled: true),
  );

  await basicQueryExample(client);
  await dedupExample(client);
  await mutationWithOptimisticUpdateExample(client);
  await infiniteQueryExample();
}

/// §2/§4 — the "instead of loading/error booleans everywhere" experience.
Future<void> basicQueryExample(QueryClient client) async {
  print('\n--- basic query ---');
  final users = client.query(
    QueryKey(['users']),
    () => FakeApi.getUsers(),
  );
  print('isLoading: ${users.isLoading}');
  await users.ensureFetched();
  print('data: ${users.data}');
  print('isStale: ${users.isStale}');
  users.dispose();
}

/// §6 — three "screens" asking for the same resource only trigger one
/// network call.
Future<void> dedupExample(QueryClient client) async {
  print('\n--- deduplication ---');
  FakeApi.requestCount = 0;
  final screenA = client.query(QueryKey(['dashboard']), FakeApi.getDashboard);
  final screenB = client.query(QueryKey(['dashboard']), FakeApi.getDashboard);
  final screenC = client.query(QueryKey(['dashboard']), FakeApi.getDashboard);

  await Future.wait([
    screenA.ensureFetched(),
    screenB.ensureFetched(),
    screenC.ensureFetched(),
  ]);
  print('network requests fired: ${FakeApi.requestCount} (expect 1)');

  screenA.dispose();
  screenB.dispose();
  screenC.dispose();
}

/// §13 — optimistic update with snapshot/rollback, plus §8 cache
/// invalidation on success.
Future<void> mutationWithOptimisticUpdateExample(QueryClient client) async {
  print('\n--- optimistic mutation ---');
  final likes = client.query(QueryKey(['post', 1, 'likes']), () async => 41);
  await likes.ensureFetched();
  print('likes before: ${likes.data}');

  final likePost = client.mutation<int, void, int>(
    (_) => FakeApi.likePost(postId: 1),
    options: MutationOptions<int, void, int>(
      onMutate: (_) async {
        final snapshot = client.getQueryData<int>(likes.key)!;
        client.updateQueryData<int>(likes.key, (current) => (current ?? 0) + 1);
        print('optimistic: cache now shows ${likes.data}');
        return snapshot;
      },
      onSuccess: (serverCount, _, __) {
        client.setQueryData<int>(likes.key, serverCount);
        print('server confirmed: ${likes.data} likes');
      },
      onError: (error, _, snapshot) {
        if (snapshot != null) client.setQueryData<int>(likes.key, snapshot);
        print('like failed, rolled back to ${likes.data}');
      },
    ),
  );

  await likePost.mutateAsync(null);
  likes.dispose();
}

/// §21/§22 — cursor-style infinite pagination.
Future<void> infiniteQueryExample() async {
  print('\n--- infinite query ---');
  final feed = InfiniteQuery<String, int>(
    key: QueryKey(['feed']),
    initialPageParam: 0,
    fetchPage: FakeApi.getFeedPage,
  );

  await feed.fetchNextPage();
  print('page 1: ${feed.items}');
  await feed.fetchNextPage();
  print('page 2: ${feed.items}');
  print('hasNextPage: ${feed.hasNextPage}');
}

/// Stand-in "backend". Real apps replace this with Dio/http calls through
/// an [HttpClientAdapter] — see dio_http_client_adapter.dart.
class FakeApi {
  static int requestCount = 0;

  static Future<List<String>> getUsers() async {
    requestCount++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return ['ada', 'linus', 'grace'];
  }

  static Future<Map<String, int>> getDashboard() async {
    requestCount++;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return {'activeUsers': 128, 'errors': 0};
  }

  static Future<int> likePost({required int postId}) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    return 42; // server's authoritative count
  }

  static Future<InfinitePage<String, int>> getFeedPage(int? page) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final p = page ?? 0;
    final items = List.generate(3, (i) => 'post-${p * 3 + i}');
    return InfinitePage(items: items, nextParam: p < 2 ? p + 1 : null);
  }
}
