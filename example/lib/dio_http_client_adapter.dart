// Reference implementation of a Dio transport adapter for queryx.
//
// This file is intentionally kept in `example/`, not in the core package:
// queryx's core has zero dependency on Dio (or any transport), so apps that
// prefer `http`, `dart:io`, or a fully custom client aren't forced to pull
// Dio in. In a real project this would ship as its own tiny package,
// `queryx_dio`, that apps add only if they want it.
//
// Usage:
//   final adapter = DioHttpClientAdapter(Dio(BaseOptions(baseUrl: ...)));
//   final client = QueryClient();
//   final api = ApiService(adapter, client);

import 'package:dio/dio.dart' as dio;
import 'package:queryx/queryx.dart';

class DioHttpClientAdapter implements HttpClientAdapter {
  DioHttpClientAdapter(this._dio);

  final dio.Dio _dio;

  @override
  Future<QueryxResponse> request(QueryxRequest request) async {
    dio.CancelToken? cancelToken;
    if (request.cancelToken != null) {
      cancelToken = dio.CancelToken();
      request.cancelToken!.onCancel(cancelToken.cancel);
    }

    try {
      final response = await _dio.request<dynamic>(
        request.path,
        data: request.body,
        queryParameters: request.queryParameters,
        cancelToken: cancelToken,
        onSendProgress: request.onSendProgress,
        onReceiveProgress: request.onReceiveProgress,
        options: dio.Options(
          method: request.method.name.toUpperCase(),
          headers: request.headers,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
        ),
      );
      return QueryxResponse(
        statusCode: response.statusCode ?? 200,
        data: response.data,
        headers: response.headers.map.map((k, v) => MapEntry(k, v.join(','))),
      );
    } on dio.DioException catch (e, st) {
      throw mapDioError(e, st);
    }
  }
}

/// Normalizes Dio's own exception hierarchy into queryx's [QueryError], so
/// nothing Dio-specific ever leaks past the transport boundary. Wire this in
/// via `QueryClient`'s error mapper hook (or call it directly from a custom
/// adapter, as above) — see spec §34/§35.
QueryError mapDioError(dio.DioException e, StackTrace st) {
  switch (e.type) {
    case dio.DioExceptionType.connectionTimeout:
    case dio.DioExceptionType.sendTimeout:
    case dio.DioExceptionType.receiveTimeout:
    case dio.DioExceptionType.transformTimeout:
      return QueryError.timeout(e, st);

    case dio.DioExceptionType.cancel:
      return QueryError.cancelled(e);

    case dio.DioExceptionType.connectionError:
      return QueryError.network(e, st);

    case dio.DioExceptionType.badResponse:
      final status = e.response?.statusCode ?? 0;
      final body = e.response?.data;

      // Example backend envelope support (spec §35):
      // {"success": false, "message": "...", "code": "..."}
      // {"error": {"message": "...", "code": "..."}}

      String? message;
      String? code;

      if (body is Map) {
        final errObj = body['error'];

        if (errObj is Map) {
          message = errObj['message']?.toString();
          code = errObj['code']?.toString();
        } else {
          message = body['message']?.toString();
          code = body['code']?.toString();
        }
      }

      final type = switch (status) {
        401 => QueryErrorType.unauthorized,
        403 => QueryErrorType.forbidden,
        404 => QueryErrorType.notFound,
        422 => QueryErrorType.validation,
        >= 500 => QueryErrorType.server,
        _ => QueryErrorType.unknown,
      };

      return QueryError(
        type: type,
        statusCode: status,
        code: code,
        message: message ?? 'Request failed with status $status',
        details: body,
        originalError: e,
        stackTrace: st,
      );

    case dio.DioExceptionType.badCertificate:
    case dio.DioExceptionType.unknown:
      return QueryError.unknown(e, st);
  }
}
