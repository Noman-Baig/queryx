// import 'dart:async';

// import '../cache/cache_entry.dart';
// import '../errors/query_error.dart';
// import '../utils/queryx_listenable.dart';

// typedef MutationFn<T, V> = Future<T> Function(V variables);

// /// Lifecycle callbacks for a [Mutation], mirroring TanStack Query's
// /// well-tested optimistic-update contract:
// ///
// /// 1. [onMutate] fires first — snapshot current state and apply an
// ///    optimistic update, returning a "context" value.
// /// 2. On success, [onSuccess] fires with the server response and that
// ///    context (e.g. to invalidate related queries).
// /// 3. On failure, [onError] fires with the error and that same context
// ///    (e.g. to roll back the optimistic update using the snapshot).
// /// 4. [onSettled] always fires last, success or failure.
// class MutationOptions<T, V, C> {
//   const MutationOptions({
//     this.onMutate,
//     this.onSuccess,
//     this.onError,
//     this.onSettled,
//   });

//   final Future<C> Function(V variables)? onMutate;
//   final void Function(T data, V variables, C? context)? onSuccess;
//   final void Function(QueryError error, V variables, C? context)? onError;
//   final void Function(T? data, QueryError? error, V variables, C? context)?
//       onSettled;
// }

// /// A single write operation (POST/PUT/PATCH/DELETE). Unlike [Query],
// /// mutations are not cached or deduplicated by key — each [mutate] call is
// /// a distinct, explicit action.
// ///
// /// ```dart
// /// final createUser = client.mutation<User, CreateUserInput>(
// ///   (input) => api.post('/users', input.toJson()),
// ///   options: MutationOptions(
// ///     onSuccess: (user, _, __) => client.invalidateQueries(QueryKey(['users'])),
// ///   ),
// /// );
// /// await createUser.mutate(input);
// /// ```
// class Mutation<T, V, C> {
//   Mutation(this._fn, {MutationOptions<T, V, C>? options})
//       : _options = options ?? const MutationOptions();

//   final MutationFn<T, V> _fn;
//   final MutationOptions<T, V, C> _options;
//   final listenable = QueryxListenable();

//   T? data;
//   QueryError? error;
//   QueryStatus status = QueryStatus.idle;

//   bool get isLoading => status == QueryStatus.loading;
//   bool get isSuccess => status == QueryStatus.success;
//   bool get isError => status == QueryStatus.error;

//   Stream<void> get stream => listenable.stream;
//   void addListener(void Function() l) => listenable.addListener(l);
//   void removeListener(void Function() l) => listenable.removeListener(l);

//   bool _cancelled = false;

//   /// Runs the mutation and returns its result, throwing [QueryError] on
//   /// failure. Use [mutate] instead if you'd rather observe state via
//   /// listeners than await/try-catch.
//   Future<T> mutateAsync(V variables) async {
//     _cancelled = false;
//     status = QueryStatus.loading;
//     error = null;
//     listenable.notifyListeners();

//     C? context;
//     if (_options.onMutate != null) {
//       context = await _options.onMutate!(variables);
//     }

//     try {
//       final result = await _fn(variables);
//       if (_cancelled) throw QueryError.cancelled();
//       data = result;
//       status = QueryStatus.success;
//       listenable.notifyListeners();
//       _options.onSuccess?.call(result, variables, context);
//       _options.onSettled?.call(result, null, variables, context);
//       return result;
//     } catch (e, st) {
//       final err = e is QueryError ? e : defaultErrorMapper(e, st);

//       error = err;
//       status = QueryStatus.error;
//       listenable.notifyListeners();

//       _options.onError?.call(err, variables, context);
//       _options.onSettled?.call(null, err, variables, context);

//       throw err;
//     }
//   }

//   /// Fire-and-observe variant of [mutateAsync] — errors are swallowed here
//   /// (they're already surfaced via [error]/[onError]) so callers don't need
//   /// a try-catch for simple UI flows.
//   void mutate(V variables) {
//     unawaited(mutateAsync(variables).then((_) {}, onError: (_) {}));
//   }

//   void cancel() {
//     _cancelled = true;
//     status = QueryStatus.idle;
//     listenable.notifyListeners();
//   }

//   void reset() {
//     data = null;
//     error = null;
//     status = QueryStatus.idle;
//     listenable.notifyListeners();
//   }

//   void dispose() => listenable.dispose();
// }

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

  // Each mutateAsync call gets its own identity.
  //
  // This is important when mutations overlap:
  //
  // mutation #1 starts
  // mutation #2 starts
  // mutation #2 succeeds
  // mutation #1 fails
  //
  // Mutation #1 must not execute an old optimistic rollback callback after
  // mutation #2 has already become the newer mutation.
  int _nextMutationId = 0;
  int _latestMutationId = 0;

  // Cancellation belongs to an individual mutation execution rather than
  // being shared by all overlapping executions.
  final Set<int> _cancelledMutationIds = <int>{};

  /// Runs the mutation and returns its result, throwing [QueryError] on
  /// failure. Use [mutate] instead if you'd rather observe state via
  /// listeners than await/try-catch.
  Future<T> mutateAsync(V variables) async {
    final mutationId = ++_nextMutationId;
    _latestMutationId = mutationId;

    status = QueryStatus.loading;
    error = null;
    listenable.notifyListeners();

    C? context;

    if (_options.onMutate != null) {
      context = await _options.onMutate!(variables);
    }

    try {
      final result = await _fn(variables);

      if (_cancelledMutationIds.remove(mutationId)) {
        throw QueryError.cancelled();
      }

      data = result;

      // Only the newest mutation is allowed to control the shared Mutation
      // state. An older request completing later must not overwrite the
      // state produced by a newer request.
      if (mutationId == _latestMutationId) {
        status = QueryStatus.success;
        error = null;
        listenable.notifyListeners();
      }

      // Preserve the existing success callback behavior. A successful
      // mutation still receives its own context.
      _options.onSuccess?.call(result, variables, context);

      if (mutationId == _latestMutationId) {
        _options.onSettled?.call(result, null, variables, context);
      }

      return result;
    } catch (e, st) {
      final err = e is QueryError ? e : defaultErrorMapper(e, st);

      final isLatest = mutationId == _latestMutationId;

      // Only the latest mutation controls the shared Mutation state.
      //
      // Without this guard, an older failed request could change the
      // Mutation into an error state after a newer request already
      // succeeded.
      if (isLatest) {
        error = err;
        status = QueryStatus.error;
        listenable.notifyListeners();
      }

      // IMPORTANT:
      //
      // The optimistic cache rollback is normally performed by onError.
      // When multiple mutations overlap, an older failed mutation may carry
      // an obsolete snapshot. Calling that callback could restore stale
      // data over a newer successful mutation.
      //
      // Therefore onError is only invoked for the current/latest mutation.
      // Sequential mutations are unaffected because each one is the latest
      // mutation when it completes.
      if (isLatest) {
        _options.onError?.call(err, variables, context);
        _options.onSettled?.call(null, err, variables, context);
      }

      throw err;
    } finally {
      _cancelledMutationIds.remove(mutationId);
    }
  }

  /// Fire-and-observe variant of [mutateAsync] — errors are swallowed here
  /// (they're already surfaced via [error]/[onError]) so callers don't need
  /// a try-catch for simple UI flows.
  void mutate(V variables) {
    unawaited(mutateAsync(variables).then((_) {}, onError: (_) {}));
  }

  void cancel() {
    // Cancel the currently active/latest mutation.
    //
    // The cancellation is now tied to the mutation execution ID rather
    // than using one shared boolean that could accidentally affect another
    // overlapping mutation.
    final mutationId = _latestMutationId;

    if (mutationId == 0) {
      status = QueryStatus.idle;
      listenable.notifyListeners();
      return;
    }

    _cancelledMutationIds.add(mutationId);

    if (mutationId == _latestMutationId) {
      status = QueryStatus.idle;
      listenable.notifyListeners();
    }
  }

  void reset() {
    data = null;
    error = null;
    status = QueryStatus.idle;
    listenable.notifyListeners();
  }

  void dispose() => listenable.dispose();
}
