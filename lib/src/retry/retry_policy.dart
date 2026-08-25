import 'dart:math';

import '../errors/query_error.dart';

/// Decides whether a failed attempt should be retried, and how long to wait
/// before the next attempt. Sensible defaults only retry errors that are
/// plausibly transient (network, timeout, 5xx) — never 4xx/validation, and
/// never a cancelled request.
class RetryPolicy {
  const RetryPolicy({
    this.maxRetries = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffFactor = 2.0,
    this.jitter = true,
    ShouldRetry? shouldRetry,
  }) : _shouldRetry = shouldRetry;

  final int maxRetries;
  final Duration initialDelay;
  final Duration maxDelay;
  final double backoffFactor;
  final bool jitter;
  final ShouldRetry? _shouldRetry;

  static const RetryPolicy none = RetryPolicy(maxRetries: 0);

  /// Whether [attempt] (0-indexed, the attempt that just failed) should be
  /// retried given [error].
  bool shouldRetry(QueryError error, int attempt) {
    if (attempt >= maxRetries) return false;
    if (_shouldRetry != null) return _shouldRetry(error, attempt);
    return error.isRetryable;
  }

  /// Delay before retrying [attempt] (0-indexed, the attempt that just
  /// failed), using exponential backoff with optional jitter, capped at
  /// [maxDelay].
  Duration delayFor(int attempt) {
    final raw = initialDelay.inMilliseconds * pow(backoffFactor, attempt);
    var ms = min(raw, maxDelay.inMilliseconds.toDouble());
    if (jitter) {
      // Full jitter: uniform(0, ms) avoids synchronized retry storms across
      // many clients/queries retrying the same failing endpoint at once.
      ms = Random().nextDouble() * ms;
    }
    return Duration(milliseconds: ms.round());
  }
}

typedef ShouldRetry = bool Function(QueryError error, int attempt);
