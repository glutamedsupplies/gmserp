import 'dart:async';
import 'dart:html' as html;
import 'dart:math';

// Conditional import for Flutter web only (see app_instance_guard.dart).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

/// Ensures only one browser tab can use GMSERP at a time.
class AppInstanceGuard {
  AppInstanceGuard._();

  static final AppInstanceGuard instance = AppInstanceGuard._();

  static const _lockKey = 'gmserp_active_instance';
  static const _tabIdKey = 'gmserp_tab_id';
  static const _channelName = 'gmserp_instance_guard';
  static const _heartbeatInterval = Duration(seconds: 2);
  static const _staleAfter = Duration(seconds: 6);

  final StreamController<bool> _primaryController =
      StreamController<bool>.broadcast();

  bool _isPrimary = true;
  String? _tabId;
  Timer? _heartbeatTimer;
  html.BroadcastChannel? _channel;
  void Function(html.Event)? _storageListener;

  bool get isPrimary => _isPrimary;

  Stream<bool> get onPrimaryChanged => _primaryController.stream;

  Future<void> initialize() async {
    _tabId = html.window.sessionStorage[_tabIdKey];
    if (_tabId == null || _tabId!.isEmpty) {
      _tabId = _newTabId();
      html.window.sessionStorage[_tabIdKey] = _tabId!;
    }

    _channel = html.BroadcastChannel(_channelName);
    _channel!.onMessage.listen((_) {
      _reevaluateLock(notifyChannel: false);
    });

    _storageListener = (html.Event event) {
      final storageEvent = event as html.StorageEvent;
      if (storageEvent.key != _lockKey) return;
      _reevaluateLock(notifyChannel: false);
    };
    html.window.addEventListener('storage', _storageListener!);

    _reevaluateLock(notifyChannel: true);
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    if (_storageListener != null) {
      html.window.removeEventListener('storage', _storageListener!);
    }
    _channel?.close();
    if (!_primaryController.isClosed) {
      _primaryController.close();
    }
  }

  void _heartbeat() {
    if (!_isPrimary) {
      _reevaluateLock(notifyChannel: false);
      return;
    }
    _writeLock(DateTime.now().millisecondsSinceEpoch);
  }

  void _reevaluateLock({required bool notifyChannel}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final raw = html.window.localStorage[_lockKey];

    if (raw == null || raw.isEmpty) {
      _claimLock(now, notifyChannel: notifyChannel);
      return;
    }

    final parts = raw.split('|');
    if (parts.length != 2) {
      _claimLock(now, notifyChannel: notifyChannel);
      return;
    }

    final ownerTabId = parts[0];
    final lastBeat = int.tryParse(parts[1]) ?? 0;
    final isStale = now - lastBeat > _staleAfter.inMilliseconds;

    if (ownerTabId == _tabId || isStale) {
      _claimLock(now, notifyChannel: notifyChannel);
    } else {
      _setPrimary(false);
    }
  }

  void _claimLock(int timestamp, {required bool notifyChannel}) {
    _writeLock(timestamp);
    _setPrimary(true);
    if (notifyChannel) {
      _channel?.postMessage('claim');
    }
  }

  void _writeLock(int timestamp) {
    html.window.localStorage[_lockKey] = '$_tabId|$timestamp';
  }

  void _setPrimary(bool value) {
    if (_isPrimary == value) return;
    _isPrimary = value;
    if (!_primaryController.isClosed) {
      _primaryController.add(value);
    }
  }

  String _newTabId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 30)}';
  }
}
