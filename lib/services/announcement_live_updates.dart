import 'dart:async';

/// Session-scoped refreshes: independent of the selected route or page ticker.
class AnnouncementLiveUpdates {
  AnnouncementLiveUpdates({
    required this.changes,
    required this.refresh,
    this.retryInterval = const Duration(seconds: 15),
  });

  final Stream<void> changes;
  final Future<void> Function() refresh;
  final Duration retryInterval;
  StreamSubscription<void>? _subscription;
  Timer? _retry;
  bool _closed = false;
  bool _running = false;
  bool _dirty = false;

  void start() {
    if (_closed || _subscription != null) return;
    _subscription = changes.listen(
      (_) => requestRefresh(),
      onError: (Object _) => requestRefresh(),
    );
    _retry = Timer.periodic(retryInterval, (_) => requestRefresh());
    requestRefresh();
  }

  Future<void> requestRefresh() async {
    if (_closed) return;
    _dirty = true;
    if (_running) return;
    _running = true;
    try {
      while (_dirty && !_closed) {
        _dirty = false;
        try {
          await refresh();
        } catch (_) {
          /* Retry on the next event/timer. */
        }
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
  }
}
