/// queryx — a fast, lightweight, production-grade server-state engine for
/// Flutter/Dart. State-management agnostic: use it with Riverpod, GetX,
/// Bloc, Provider, or plain `setState`.
library;

export 'src/cache/cache_entry.dart' show QueryStatus, CacheEntry;
export 'src/cache/persistence.dart';
export 'src/client/query_client.dart';
export 'src/errors/query_error.dart';
export 'src/mutation/mutation.dart';
export 'src/network/network_monitor.dart';
export 'src/query/infinite_query.dart';
export 'src/query/query.dart' show Query, Fetcher;
export 'src/query/query_key.dart';
export 'src/query/query_options.dart';
export 'src/retry/retry_policy.dart';
export 'src/transport/http_client_adapter.dart';
export 'src/utils/logger.dart';
