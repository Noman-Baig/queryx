import 'dart:async';

/// A tiny observer primitive so the core engine has zero dependency on
/// Flutter's `ChangeNotifier`/`Listenable`. UI-binding packages
/// (`queryx_riverpod`, `queryx_getx`, or a hand-rolled `ChangeNotifier`
/// wrapper) adapt this to whatever the host framework expects.
///
/// Exposes both a synchronous listener list (cheap, used by UI bindings for
/// granular rebuilds) and a broadcast [stream] (for `StreamBuilder`/custom
/// reactive integrations, see spec §50).
class QueryxListenable {
  final _listeners = <void Function()>[];
  StreamController<void>? _controller;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  Stream<void> get stream {
    _controller ??= StreamController<void>.broadcast();
    return _controller!.stream;
  }

  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
    _controller?.add(null);
  }

  void dispose() {
    _listeners.clear();
    _controller?.close();
    _controller = null;
  }
}
