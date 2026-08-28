import 'dart:async';

import '../../core/utils/rtdb_platform.dart';

/// Limits concurrent RTDB I/O on Windows/Linux so the Firebase C++ SDK does
/// not abort when many requests run at once (e.g. opening Requests).
class RtdbDesktopLimiter {
  RtdbDesktopLimiter._();

  static int _inFlight = 0;
  static int _heavyLoadDepth = 0;
  static const _maxConcurrent = 1;
  static final _waitQueue = <Completer<void>>[];

  /// True while a screen is performing a multi-read load (e.g. Requests inbox).
  static bool get isHeavyLoading => _heavyLoadDepth > 0;

  /// Marks a heavy screen load so background polls defer until it finishes.
  static Future<T> runHeavy<T>(Future<T> Function() action) async {
    if (!preferRtdbPolling) {
      return action();
    }
    _heavyLoadDepth++;
    try {
      return await action();
    } finally {
      _heavyLoadDepth--;
    }
  }

  static Future<T> run<T>(Future<T> Function() action) async {
    if (!preferRtdbPolling) {
      return action();
    }

    await _acquire();
    try {
      return await action();
    } finally {
      _release();
    }
  }

  static Future<void> _acquire() async {
    if (_inFlight < _maxConcurrent) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _waitQueue.add(waiter);
    await waiter.future;
    _inFlight++;
  }

  static void _release() {
    _inFlight--;
    if (_waitQueue.isEmpty) return;
    _waitQueue.removeAt(0).complete();
  }
}
