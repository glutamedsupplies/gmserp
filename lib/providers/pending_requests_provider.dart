import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/firebase_data.dart';
import '../core/utils/rtdb_platform.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/notification_service.dart';
import '../services/rtdb/rtdb_desktop_limiter.dart';
import '../services/rtdb/rtdb_paths.dart';
import '../services/rtdb/rtdb_service.dart';

class _PendingHint {
  const _PendingHint({
    required this.type,
    required this.id,
    required this.createdAt,
    required this.title,
    required this.body,
  });

  final String type;
  final String id;
  final DateTime createdAt;
  final String title;
  final String body;
}

/// Pending inbox count for Admin / Super Admin (Requests page + burger + badge).
class PendingRequestsProvider extends ChangeNotifier {
  PendingRequestsProvider({
    RtdbService? rtdb,
    NotificationService? notifications,
    bool Function()? notificationsEnabled,
  })  : _rtdb = rtdb ?? RtdbService(),
        _notifications = notifications ?? NotificationService.instance,
        _notificationsEnabled = notificationsEnabled ?? (() => true);

  final RtdbService _rtdb;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;

  StreamSubscription<DatabaseEvent>? _timeSub;
  StreamSubscription<DatabaseEvent>? _leaveSub;
  StreamSubscription<DatabaseEvent>? _clockSub;
  Timer? _pollTimer;
  bool _listening = false;
  bool _seeded = false;
  bool _includeTimeEdits = false;
  bool _companyUnlocked = true;
  bool _polling = false;
  String? _userId;

  int _timePending = 0;
  int _leavePending = 0;
  int _clockPending = 0;
  int pendingCount = 0;

  _PendingHint? _latestLeave;
  _PendingHint? _latestTime;
  _PendingHint? _latestClock;
  _PendingHint? _lastAnnounced;

  bool get hasPending => pendingCount > 0;

  String get badgeLabel {
    if (pendingCount <= 0) return '';
    if (pendingCount > 99) return '99+';
    return '$pendingCount';
  }

  void syncUser(UserModel? user, {bool companyUnlocked = true}) {
    final role = user?.role;
    final allowed = role == UserRole.superAdmin || role == UserRole.admin;
    final needsCompanyGate = role == UserRole.admin;
    final canListen =
        user != null && allowed && (!needsCompanyGate || companyUnlocked);

    if (!canListen) {
      final wasActive = _listening ||
          pendingCount != 0 ||
          _latestLeave != null ||
          _latestTime != null ||
          _latestClock != null;
      _stop();
      if (pendingCount != 0 ||
          _timePending != 0 ||
          _leavePending != 0 ||
          _clockPending != 0) {
        _timePending = 0;
        _leavePending = 0;
        _clockPending = 0;
        pendingCount = 0;
        notifyListeners();
      }
      _latestLeave = null;
      _latestTime = null;
      _latestClock = null;
      _lastAnnounced = null;
      _userId = null;
      _companyUnlocked = false;
      if (user == null) {
        unawaited(_notifications.clearAll());
      } else if (wasActive) {
        unawaited(
          _notifications.syncSuperAdminPending(
            count: 0,
            notificationsEnabled: true,
            announceIncrease: false,
          ),
        );
      }
      return;
    }

    if (_listening &&
        _userId == user.id &&
        _companyUnlocked == companyUnlocked) {
      return;
    }

    _stop();
    _userId = user.id;
    _companyUnlocked = companyUnlocked;
    _listening = true;
    _seeded = false;
    _includeTimeEdits = role == UserRole.superAdmin;

    if (preferRtdbPolling) {
      _startPolling();
      return;
    }
    _startLiveListeners();
  }

  void _startPolling() {
    if (preferRtdbPolling) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!_listening) return;
        unawaited(_pollOnce());
        _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
          unawaited(_pollOnce());
        });
      });
      return;
    }
    unawaited(_pollOnce());
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    if (!_listening || _polling || RtdbDesktopLimiter.isHeavyLoading) return;
    _polling = true;
    try {
      if (_includeTimeEdits) {
        final time = await _rtdb.getChildren(RtdbPaths.timeCardChangeRequests);
        _applyTimePending(time);
      } else {
        _timePending = 0;
        _latestTime = null;
      }
      final leave = await _rtdb.getChildren(RtdbPaths.leaveRequests);
      _applyLeavePending(leave);
      final clock = await _rtdb.getChildren(RtdbPaths.clockRequests);
      _applyClockPending(clock);
      _emit();
    } catch (_) {
      // Keep last good badge counts on transient RTDB errors.
    } finally {
      _polling = false;
    }
  }

  void _startLiveListeners() {
    if (_includeTimeEdits) {
      _timeSub = _rtdb.onValue(RtdbPaths.timeCardChangeRequests).listen(
        (event) {
          _applyTimePending(RtdbService.snapshotChildren(event.snapshot));
          _emit();
        },
        onError: (_) {
          _timePending = 0;
          _latestTime = null;
          _emit();
        },
      );
    } else {
      _timePending = 0;
      _latestTime = null;
    }

    _leaveSub = _rtdb.onValue(RtdbPaths.leaveRequests).listen(
      (event) {
        _applyLeavePending(RtdbService.snapshotChildren(event.snapshot));
        _emit();
      },
      onError: (_) {
        _leavePending = 0;
        _latestLeave = null;
        _emit();
      },
    );

    _clockSub = _rtdb.onValue(RtdbPaths.clockRequests).listen(
      (event) {
        _applyClockPending(RtdbService.snapshotChildren(event.snapshot));
        _emit();
      },
      onError: (_) {
        _clockPending = 0;
        _latestClock = null;
        _emit();
      },
    );
  }

  void _applyTimePending(Map<String, Map<String, dynamic>> children) {
    _PendingHint? newest;
    var count = 0;
    for (final entry in children.entries) {
      final data = entry.value;
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'pending') continue;
      count += 1;
      final created = _readCreatedAt(data);
      final employee =
          (data['employeeName']?.toString().trim().isNotEmpty == true)
              ? data['employeeName'].toString().trim()
              : (data['employeeEmail']?.toString() ?? 'Employee');
      final company = data['companyName']?.toString().trim() ?? '';
      final hint = _PendingHint(
        type: RequestNotificationPayload.typeTime,
        id: entry.key,
        createdAt: created,
        title: 'Time card change request',
        body: company.isEmpty
            ? '$employee submitted a time edit for review.'
            : '$employee · $company submitted a time edit for review.',
      );
      if (newest == null || hint.createdAt.isAfter(newest.createdAt)) {
        newest = hint;
      }
    }
    _timePending = count;
    _latestTime = newest;
  }

  void _applyLeavePending(Map<String, Map<String, dynamic>> children) {
    _PendingHint? newest;
    var count = 0;
    for (final entry in children.entries) {
      final data = entry.value;
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'pending') continue;
      count += 1;
      final created = _readCreatedAt(data);
      final employee =
          (data['username']?.toString().trim().isNotEmpty == true)
              ? data['username'].toString().trim()
              : (data['userEmail']?.toString() ?? 'Employee');
      final company = data['companyName']?.toString().trim() ?? '';
      final hint = _PendingHint(
        type: RequestNotificationPayload.typeLeave,
        id: entry.key,
        createdAt: created,
        title: 'Leave request',
        body: company.isEmpty
            ? '$employee submitted a leave request for review.'
            : '$employee · $company submitted a leave request for review.',
      );
      if (newest == null || hint.createdAt.isAfter(newest.createdAt)) {
        newest = hint;
      }
    }
    _leavePending = count;
    _latestLeave = newest;
  }

  void _applyClockPending(Map<String, Map<String, dynamic>> children) {
    _PendingHint? newest;
    var count = 0;
    for (final entry in children.entries) {
      final data = entry.value;
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'pending' && status != 'expired') continue;
      count += 1;
      final created = _readCreatedAt(data);
      final type = data['type']?.toString() ?? 'clockIn';
      final employee =
          (data['username']?.toString().trim().isNotEmpty == true)
              ? data['username'].toString().trim()
              : (data['userEmail']?.toString() ?? 'Employee');
      final company = data['companyName']?.toString().trim() ?? '';
      final kind = type == 'clockOut' ? 'time out' : 'time in';
      final hint = _PendingHint(
        type: RequestNotificationPayload.typeClock,
        id: entry.key,
        createdAt: created,
        title: 'Employee $kind request',
        body: company.isEmpty
            ? '$employee submitted a $kind request.'
            : '$employee · $company submitted a $kind request.',
      );
      if (newest == null || hint.createdAt.isAfter(newest.createdAt)) {
        newest = hint;
      }
    }
    _clockPending = count;
    _latestClock = newest;
  }

  Future<void> refreshNotificationPrefs() async {
    if (!_listening) {
      await _notifications.clearAll();
      return;
    }
    await _notifications.syncSuperAdminPending(
      count: pendingCount,
      notificationsEnabled: _notificationsEnabled(),
      announceIncrease: false,
      title: _lastAnnounced?.title,
      body: _lastAnnounced?.body,
      payload: _payloadFor(_lastAnnounced),
    );
  }

  void _emit() {
    final total = _timePending + _leavePending + _clockPending;
    final wasSeeded = _seeded;
    final newest = _pickNewest();
    final increased = wasSeeded && total > pendingCount;

    if (pendingCount == total && wasSeeded && !increased) {
      return;
    }

    pendingCount = total;
    _seeded = true;
    if (increased && newest != null) {
      _lastAnnounced = newest;
    } else if (!wasSeeded && newest != null) {
      _lastAnnounced = newest;
    } else if (total <= 0) {
      _lastAnnounced = null;
    }
    notifyListeners();

    unawaited(
      _notifications.syncSuperAdminPending(
        count: total,
        notificationsEnabled: _notificationsEnabled(),
        announceIncrease: wasSeeded,
        title: increased ? newest?.title : _lastAnnounced?.title,
        body: increased
            ? (newest?.body ??
                'You have $total pending request${total == 1 ? '' : 's'} waiting for review.')
            : _lastAnnounced?.body,
        payload: _payloadFor(increased ? newest : _lastAnnounced),
      ),
    );
  }

  _PendingHint? _pickNewest() {
    final candidates = <_PendingHint>[
      ?_latestLeave,
      ?_latestTime,
      ?_latestClock,
    ];
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return candidates.first;
  }

  String? _payloadFor(_PendingHint? hint) {
    if (hint == null) return NotificationService.requestsRoutePayload;
    return RequestNotificationPayload(type: hint.type, id: hint.id).encode();
  }

  DateTime _readCreatedAt(Map<String, dynamic> data) {
    return parseFirebaseDate(data['createdAt']) ??
        parseFirebaseDate(data['updatedAt']) ??
        parseFirebaseDate(data['requestedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _timeSub?.cancel();
    _leaveSub?.cancel();
    _clockSub?.cancel();
    _timeSub = null;
    _leaveSub = null;
    _clockSub = null;
    _listening = false;
    _seeded = false;
    _includeTimeEdits = false;
    _polling = false;
    _userId = null;
    _companyUnlocked = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
