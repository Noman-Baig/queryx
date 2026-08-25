import 'package:queryx/queryx.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    test('retries retryable errors up to maxRetries', () {
      const policy = RetryPolicy(maxRetries: 3, jitter: false);
      final networkError = QueryError.network('boom');
      expect(policy.shouldRetry(networkError, 0), isTrue);
      expect(policy.shouldRetry(networkError, 2), isTrue);
      expect(policy.shouldRetry(networkError, 3), isFalse);
    });

    test('never retries non-retryable errors by default', () {
      const policy = RetryPolicy(maxRetries: 5);
      final validationError = QueryError(
        type: QueryErrorType.validation,
        message: 'bad input',
      );
      expect(policy.shouldRetry(validationError, 0), isFalse);
    });

    test('never retries a cancelled request', () {
      const policy = RetryPolicy(maxRetries: 5);
      expect(policy.shouldRetry(QueryError.cancelled(), 0), isFalse);
    });

    test('delay grows exponentially and is capped at maxDelay', () {
      const policy = RetryPolicy(
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 10),
        backoffFactor: 2,
        jitter: false,
      );
      expect(policy.delayFor(0), const Duration(seconds: 1));
      expect(policy.delayFor(1), const Duration(seconds: 2));
      expect(policy.delayFor(2), const Duration(seconds: 4));
      expect(policy.delayFor(10), const Duration(seconds: 10)); // capped
    });

    test('custom shouldRetry overrides default classification', () {
      final policy = RetryPolicy(
        maxRetries: 2,
        shouldRetry: (error, attempt) => error.statusCode == 429,
      );
      final rateLimited = QueryError(
        type: QueryErrorType.server,
        message: 'too many requests',
        statusCode: 429,
      );
      final notFound = QueryError(
        type: QueryErrorType.notFound,
        message: 'missing',
        statusCode: 404,
      );
      expect(policy.shouldRetry(rateLimited, 0), isTrue);
      expect(policy.shouldRetry(notFound, 0), isFalse);
    });
  });
}
