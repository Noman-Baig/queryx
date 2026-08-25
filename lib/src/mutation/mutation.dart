import 'dart:async';

import '../cache/cache_entry.dart';
import '../errors/query_error.dart';
import '../utils/queryx_listenable.dart';

typedef MutationFn<T, V> = Future<T> Function(V variables);

/// Lifecycle callbacks for a [Mutation], mirroring TanStack Query's
/// well-tested optimistic-update contract:
///
/// 1. [onMutate] fires first — snapshot current state and apply an
///    optimistic update, returning a "context" value.
/// 2. On success, [onSuccess] fires with the server response and that
///    context (e.g. to invalidate related queries).
/// 3. On failure, [onError] fires with the error and that same context
///    (e.g. to roll back the optimistic update using the snapshot).
/// 4. [onSettled] always fires last, success or failure.
class MutationOptions<T, V, C> {
  const MutationOptions({
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final Future<C> Function(V variables)? onMutate;
  final void Function(T data, V variables, C? context)? onSuccess;
  final void Function(QueryError error, V variables, C? context)? onError;
  final void Function(T? data, QueryError? error, V variables, C? context)?
      onSettled;
}

/// A single write operation (POST/PUT/PATCH/DELETE). Unlike [Query],
/// mutations are not cached or deduplicated by key — each [mutate] call is
/// a distinct, explicit action.
///
/// ```dart
/// final createUser = client.mutation<User, CreateUserInput>(
///   (input) => api.post('/users', input.toJson()),
///   options: MutationOptions(
///     onSuccess: (user, _, __) => client.invalidateQueries(QueryKey(['users'])),
///   ),
/// );
/// await createUser.mutate(input);
/// ```
class Mutation<T, V, C> {
  Mutation(this._fn, {MutationOptions<T, V, C>? options})
      : _options = options ?? const MutationOptions();

  final MutationFn<T, V> _fn;
  final MutationOptions<T, V, C> _options;
  final listenable = QueryxListenable();

  T? data;
  QueryError? error;
  QueryStatus status = QueryStatus.idle;

  bool get isLoading => status == QueryStatus.loading;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;

  Stream<void> get stream => listenable.stream;
  void addListener(void Function() l) => listenable.addListener(l);
  void removeListener(void Function() l) => listenable.removeListener(l);

  bool _cancelled = false;

  /// Runs the mutation and returns its result, throwing [QueryError] on
  /// failure. Use [mutate] instead if you'd rather observe state via
  /// listeners than await/try-catch.
  Future<T> mutateAsync(V variables) async {
    _cancelled = false;
    status = QueryStatus.loading;
    error = null;
    listenable.notifyListeners();

    C? context;
    if (_options.onMutate != null) {
      context = await _options.onMutate!(variables);
    }

    try {
      final result = await _fn(variables);
      if (_cancelled) throw QueryError.cancelled();
      data = result;
      status = QueryStatus.success;
      listenable.notifyListeners();
      _options.onSuccess?.call(result, variables, context);
      _options.onSettled?.call(result, null, variables, context);
      return result;
    } catch (e, st) {
      final err = e is QueryError ? e : defaultErrorMapper(e, st);

      error = err;
      status = QueryStatus.error;
      listenable.notifyListeners();

      _options.onError?.call(err, variables, context);
      _options.onSettled?.call(null, err, variables, context);

      throw err;
    }
  }

  /// Fire-and-observe variant of [mutateAsync] — errors are swallowed here
  /// (they're already surfaced via [error]/[onError]) so callers don't need
  /// a try-catch for simple UI flows.
  void mutate(V variables) {
    unawaited(mutateAsync(variables).then((_) {}, onError: (_) {}));
  }

  void cancel() {
    _cancelled = true;
    status = QueryStatus.idle;
    listenable.notifyListeners();
  }

  void reset() {
    data = null;
    error = null;
    status = QueryStatus.idle;
    listenable.notifyListeners();
  }

  void dispose() => listenable.dispose();
}
