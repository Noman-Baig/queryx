enum NetworkStatus { online, offline, unknown }

/// Reports connectivity so the engine can skip unnecessary requests while
/// offline and resume (refetch/poll) when the connection returns. The core
/// package ships a permanently-online default; plug a real adapter
/// (`connectivity_plus`, platform channels, etc.) via [NetworkMonitor].
abstract class NetworkMonitor {
  NetworkStatus get status;
  Stream<NetworkStatus> get onStatusChange;
  void dispose() {}
}

/// Default no-op monitor: always reports online. Use this in tests or
/// until a real connectivity adapter is wired up.
class AlwaysOnlineNetworkMonitor implements NetworkMonitor {
  @override
  NetworkStatus get status => NetworkStatus.online;

  @override
  Stream<NetworkStatus> get onStatusChange => const Stream.empty();

  @override
  void dispose() {}
}
