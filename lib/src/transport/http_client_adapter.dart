/// Transport-agnostic request/response contract. queryx never hard-codes to
/// Dio — `queryx_dio` is the default adapter, but `http`, `dart:io`, or a
/// fully custom client can implement this instead.
abstract class HttpClientAdapter {
  Future<QueryxResponse> request(QueryxRequest request);
}

enum HttpMethod { get, post, put, patch, delete, head }

class QueryxRequest {
  QueryxRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.queryParameters = const {},
    this.body,
    this.cancelToken,
    this.connectTimeout,
    this.sendTimeout,
    this.receiveTimeout,
    this.onSendProgress,
    this.onReceiveProgress,
  });

  final HttpMethod method;
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic> queryParameters;
  final Object? body;
  final QueryxCancelToken? cancelToken;
  final Duration? connectTimeout;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;
  final void Function(int sent, int total)? onSendProgress;
  final void Function(int received, int total)? onReceiveProgress;
}

class QueryxResponse {
  QueryxResponse({
    required this.statusCode,
    required this.data,
    this.headers = const {},
  });

  final int statusCode;
  final dynamic data;
  final Map<String, String> headers;
}

/// Cooperative cancellation handle. Adapters translate this into their own
/// native cancellation (e.g. Dio's `CancelToken`) where the transport
/// supports it.
class QueryxCancelToken {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() listener) => _listeners.add(listener);
}
