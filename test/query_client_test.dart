import 'dart:async';

import 'package:queryx/queryx.dart';
import 'package:test/test.dart';

void main() {
  test(
      'older failed optimistic mutation does not rollback newer successful mutation',
      () async {
    final client = QueryClient();

    final key = QueryKey(['counter']);

    client.setQueryData<int>(key, 0);

    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();

    final firstFail = Completer<void>();
    final secondSuccess = Completer<void>();

    final mutation = client.mutation<int, int, int>(
      (value) async {
        if (value == 1) {
          firstStarted.complete();
          await firstFail.future;
          throw QueryError.network('first failed');
        }

        secondStarted.complete();
        await secondSuccess.future;
        return 2;
      },
      options: MutationOptions<int, int, int>(
        onMutate: (value) async {
          final snapshot = client.getQueryData<int>(key)!;

          client.setQueryData<int>(key, value);

          return snapshot;
        },
        onSuccess: (data, _, __) {
          client.setQueryData<int>(key, data);
        },
        onError: (_, __, snapshot) {
          client.setQueryData<int>(key, snapshot!);
        },
      ),
    );

    final first = mutation.mutateAsync(1);

    await firstStarted.future;

    final second = mutation.mutateAsync(2);

    await secondStarted.future;

    // Second optimistic value.
    expect(client.getQueryData<int>(key), 2);

    // Second mutation succeeds first.
    secondSuccess.complete();
    await second;

    expect(client.getQueryData<int>(key), 2);

    // First mutation fails afterwards.
    firstFail.complete();

    await expectLater(first, throwsA(isA<QueryError>()));

    // This is the important assertion.
    expect(client.getQueryData<int>(key), 2);
  });
  group('QueryClient', () {
    test('concurrent observers for the same key deduplicate to one fetch',
        () async {
      var callCount = 0;
      final client = QueryClient();
      Future<String> fetcher() async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'users-data';
      }

      final a = client.query(QueryKey(['users']), fetcher);
      final b = client.query(QueryKey(['users']), fetcher);
      final c = client.query(QueryKey(['users']), fetcher);

      final results = await Future.wait([
        a.ensureFetched(),
        b.ensureFetched(),
        c.ensureFetched(),
      ]);

      expect(callCount, 1, reason: 'only one network request should fire');
      expect(results, everyElement('users-data'));
      expect(a.data, 'users-data');
      expect(b.data, 'users-data');
      expect(c.data, 'users-data');
    });

    test('cached data is reused within staleTime without refetching', () async {
      var callCount = 0;
      final client = QueryClient();
      final q = client.query<String>(
        QueryKey(['profile']),
        () async {
          callCount++;
          return 'v$callCount';
        },
        options: const QueryOptions(staleTime: Duration(minutes: 5)),
      );

      await q.ensureFetched();
      await q.ensureFetched();
      await q.ensureFetched();

      expect(callCount, 1);
      expect(q.data, 'v1');
    });

    test('invalidateQueries forces the next access to refetch', () async {
      var callCount = 0;
      final client = QueryClient();
      final q = client.query<String>(
        QueryKey(['profile']),
        () async {
          callCount++;
          return 'v$callCount';
        },
      );

      await q.ensureFetched();
      client.invalidateQueries(QueryKey(['profile']));
      await q.ensureFetched();

      expect(callCount, 2);
      expect(q.data, 'v2');
    });

    test('failed fetch surfaces a normalized QueryError', () async {
      final client = QueryClient();
      final q = client.query<String>(
        QueryKey(['broken']),
        () async => throw Exception('network down'),
      );

      await expectLater(q.refetch(), throwsA(isA<QueryError>()));
      expect(q.isError, isTrue);
      expect(q.error, isA<QueryError>());
    });

    test('retry policy retries transient errors before succeeding', () async {
      var attempts = 0;
      final client = QueryClient();
      final q = client.query<String>(
        QueryKey(['flaky']),
        () async {
          attempts++;
          if (attempts < 3) {
            throw QueryError.network('temporary');
          }
          return 'ok';
        },
        options: const QueryOptions(
          retryPolicy: RetryPolicy(
            maxRetries: 5,
            initialDelay: Duration(milliseconds: 1),
            jitter: false,
          ),
        ),
      );

      final result = await q.refetch();
      expect(result, 'ok');
      expect(attempts, 3);
    });

    test('disposing all observers eventually garbage collects the entry',
        () async {
      final client = QueryClient();
      final q = client.query<String>(
        QueryKey(['temp']),
        () async => 'data',
        options: const QueryOptions(cacheTime: Duration(milliseconds: 10)),
      );
      await q.ensureFetched();
      q.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      var refetchCount = 0;
      final q2 = client.query<String>(
        QueryKey(['temp']),
        () async {
          refetchCount++;
          return 'fresh';
        },
      );
      await q2.ensureFetched();
      expect(refetchCount, 1, reason: 'old entry should have been GC\'d');
      expect(q2.data, 'fresh');
    });

    test('mutation runs onMutate → onSuccess and invalidates related query',
        () async {
      final client = QueryClient();
      var usersRefetchCount = 0;
      final usersQuery = client.query<List<String>>(
        QueryKey(['users']),
        () async {
          usersRefetchCount++;
          return ['a', 'b'];
        },
      );
      await usersQuery.ensureFetched();

      final createUser = client.mutation<String, String, void>(
        (name) async => 'created:$name',
        options: MutationOptions(
          onSuccess: (data, variables, context) {
            client.invalidateQueries(QueryKey(['users']));
          },
        ),
      );

      final result = await createUser.mutateAsync('charlie');

      expect(result, 'created:charlie');
      expect(createUser.isSuccess, isTrue);
      expect(usersRefetchCount, 2, reason: 'onSuccess should invalidate users');
    });

    test('mutation onError + rollback via optimistic-update context', () async {
      final client = QueryClient();
      var counter = 10;

      final increment = client.mutation<int, void, int>(
        (_) async => throw Exception('server rejected'),
        options: MutationOptions<int, void, int>(
          onMutate: (_) async {
            final snapshot = counter;
            counter += 1; // optimistic
            return snapshot;
          },
          onError: (error, variables, snapshot) {
            if (snapshot != null) counter = snapshot; // rollback
          },
        ),
      );

      expect(counter, 10);
      await expectLater(
          increment.mutateAsync(null), throwsA(isA<QueryError>()));
      expect(counter, 10, reason: 'rollback should restore original value');
      expect(increment.isError, isTrue);
    });

    test(
        'setQueryData/getQueryData drive a real cache-backed optimistic update',
        () async {
      final client = QueryClient();
      final likesKey = QueryKey(['post', 1, 'likes']);
      final likes = client.query<int>(likesKey, () async => 41);
      await likes.ensureFetched();
      expect(likes.data, 41);

      final likePost = client.mutation<int, void, int>(
        (_) async => 42, // server's authoritative count
        options: MutationOptions<int, void, int>(
          onMutate: (_) async {
            final snapshot = client.getQueryData<int>(likesKey)!;
            client.updateQueryData<int>(
                likesKey, (current) => (current ?? 0) + 1);
            return snapshot;
          },
          onSuccess: (serverCount, _, __) {
            client.setQueryData<int>(likesKey, serverCount);
          },
          onError: (error, _, snapshot) {
            if (snapshot != null) client.setQueryData<int>(likesKey, snapshot);
          },
        ),
      );

      // Optimistic bump is visible on the *same* live Query instance
      // immediately — onMutate runs synchronously before the mutation's
      // Future even settles, no manual widget rebuild wiring needed.
      final future = likePost.mutateAsync(null);
      expect(likes.data, 42,
          reason: 'optimistic update applies before the server responds');
      await future;

      expect(likes.data, 42,
          reason: 'onSuccess should reconcile with server value');
      expect(client.getQueryData<int>(likesKey), 42);
    });

    test('setQueryData rollback restores prior cached value on failure',
        () async {
      final client = QueryClient();
      final likesKey = QueryKey(['post', 2, 'likes']);
      final likes = client.query<int>(likesKey, () async => 5);
      await likes.ensureFetched();

      final likePost = client.mutation<int, void, int>(
        (_) async => throw Exception('server rejected'),
        options: MutationOptions<int, void, int>(
          onMutate: (_) async {
            final snapshot = client.getQueryData<int>(likesKey)!;
            client.updateQueryData<int>(
                likesKey, (current) => (current ?? 0) + 1);
            return snapshot;
          },
          onError: (error, _, snapshot) {
            if (snapshot != null) client.setQueryData<int>(likesKey, snapshot);
          },
        ),
      );

      await expectLater(likePost.mutateAsync(null), throwsA(isA<QueryError>()));
      expect(likes.data, 5,
          reason: 'rollback should restore the pre-mutate value');
    });
  });

  group('InfiniteQuery', () {
    test('fetchNextPage accumulates items and stops at last page', () async {
      final allPages = [
        const InfinitePage(items: [1, 2], nextParam: 1),
        const InfinitePage(items: [3, 4], nextParam: 2),
        const InfinitePage<int, int>(items: [5], nextParam: null),
      ];

      final feed = InfiniteQuery<int, int>(
        key: QueryKey(['numbers']),
        initialPageParam: 0,
        fetchPage: (param) async => allPages[param ?? 0],
      );

      await feed.fetchNextPage();
      await feed.fetchNextPage();
      await feed.fetchNextPage();

      expect(feed.items, [1, 2, 3, 4, 5]);
      expect(feed.hasNextPage, isFalse);

      // Calling again once exhausted should not throw or duplicate items.
      await feed.fetchNextPage();
      expect(feed.items, [1, 2, 3, 4, 5]);
    });
  });
}
