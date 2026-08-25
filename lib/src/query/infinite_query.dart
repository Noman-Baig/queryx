import 'dart:async';

import '../errors/query_error.dart';
import '../retry/retry_policy.dart';
import '../utils/logger.dart';
import '../utils/queryx_listenable.dart';
import 'query_key.dart';

/// One fetched page: the items, plus whatever cursor/page-info the caller
/// needs to request the next page. `P` is your own lightweight page-param
/// type (an int page number, a cursor string, an offset, etc.) — queryx
/// doesn't assume page-number vs cursor pagination (spec §21).
class InfinitePage<T, P> {
  const InfinitePage(
      {required this.items, required this.nextParam, this.previousParam});

  final List<T> items;

  /// Param to request the next page, or `null` if this is the last page.
  final P? nextParam;

  /// Param to request the previous page, or `null` if this is the first.
  final P? previousParam;
}

typedef PageFetcher<T, P> = Future<InfinitePage<T, P>> Function(P? pageParam);

/// A query that accumulates pages as the user scrolls, rather than
/// replacing data on each fetch (spec §22).
///
/// ```dart
/// final feed = InfiniteQuery<Post, int>(
///   key: QueryKey(['posts']),
///   initialPageParam: 0,
///   fetchPage: (page) => api.getPosts(page: page ?? 0),
/// );
/// await feed.fetchNextPage();
/// ```
class InfiniteQuery<T, P> {
  InfiniteQuery({
    required this.key,
    required this.fetchPage,
    this.initialPageParam,
    RetryPolicy? retryPolicy,
    QueryxLogger? logger,
  })  : _retryPolicy = retryPolicy ?? const RetryPolicy(maxRetries: 3),
        _logger = logger ?? QueryxLogger();

  final QueryKey key;
  final PageFetcher<T, P> fetchPage;
  final P? initialPageParam;
  final RetryPolicy _retryPolicy;
  final QueryxLogger _logger;
  final listenable = QueryxListenable();

  final List<InfinitePage<T, P>> pages = [];
  QueryError? error;
  bool isLoading = false;
  bool isFetchingNextPage = false;
  bool isFetchingPreviousPage = false;

  List<T> get items => pages.expand((p) => p.items).toList(growable: false);
  bool get hasNextPage => pages.isEmpty || pages.last.nextParam != null;
  bool get hasPreviousPage =>
      pages.isNotEmpty && pages.first.previousParam != null;

  Stream<void> get stream => listenable.stream;
  void addListener(void Function() l) => listenable.addListener(l);
  void removeListener(void Function() l) => listenable.removeListener(l);

  bool _inFlightNext = false;
  bool _inFlightPrev = false;

  /// Loads the first page, replacing any existing pages.
  Future<void> refresh() async {
    pages.clear();
    isLoading = true;
    listenable.notifyListeners();
    await fetchNextPage();
    isLoading = false;
    listenable.notifyListeners();
  }

  /// Fetches the next page and appends it. No-ops (rather than firing a
  /// duplicate request) if a next-page fetch is already in flight or
  /// there's no next page (spec §22: avoid duplicate page requests).
  Future<void> fetchNextPage() async {
    if (_inFlightNext || !hasNextPage) return;
    _inFlightNext = true;
    isFetchingNextPage = true;
    listenable.notifyListeners();

    final param = pages.isEmpty ? initialPageParam : pages.last.nextParam;
    var attempt = 0;
    while (true) {
      try {
        final page = await fetchPage(param);
        pages.add(page);
        error = null;
        _logger.log(
            'QUERY', '${key.id} → page loaded (${page.items.length} items)');
        break;
      } catch (e, st) {
        final err = e is QueryError ? e : defaultErrorMapper(e, st);

        if (_retryPolicy.shouldRetry(err, attempt)) {
          await Future<void>.delayed(
            _retryPolicy.delayFor(attempt),
          );
          attempt++;
          continue;
        }

        error = err;
        break;
      }
    }
    isFetchingNextPage = false;
    _inFlightNext = false;
    listenable.notifyListeners();
  }

  /// Fetches the previous page and prepends it (for chat-style UIs that
  /// paginate upward).
  Future<void> fetchPreviousPage() async {
    if (_inFlightPrev || !hasPreviousPage) return;
    _inFlightPrev = true;
    isFetchingPreviousPage = true;
    listenable.notifyListeners();

    final param = pages.first.previousParam;
    try {
      final page = await fetchPage(param);
      pages.insert(0, page);
      error = null;
    } catch (e, st) {
      error = e is QueryError ? e : defaultErrorMapper(e, st);
    }
    isFetchingPreviousPage = false;
    _inFlightPrev = false;
    listenable.notifyListeners();
  }

  void reset() {
    pages.clear();
    error = null;
    isLoading = false;
    isFetchingNextPage = false;
    isFetchingPreviousPage = false;
    listenable.notifyListeners();
  }

  void dispose() => listenable.dispose();
}
