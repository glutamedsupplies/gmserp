import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/clock_request_repository.dart';
import '../services/leave_request_repository.dart';
import '../services/notification_service.dart';
import '../services/time_card_change_request_repository.dart';

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
    FirebaseFirestore? firestore,
    NotificationService? notifications,
    bool Function()? notificationsEnabled,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notifications = notifications ?? NotificationService.instance,
        _notificationsEnabled = notificationsEnabled ?? (() => true);

  final FirebaseFirestore _firestore;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _timeSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leaveSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _clockSub;
  bool _listening = false;
  bool _seeded = false;
  bool _includeTimeEdits = false;

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

  void syncUser(UserModel? user) {
    final role = user?.role;
    final allowed = role == UserRole.superAdmin || role == UserRole.admin;
    if (user == null || !allowed) {
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

    if (_listening) {
      return;
    }
    _listening = true;
    _seeded = false;
    _includeTimeEdits = role == UserRole.superAdmin;

    if (_includeTimeEdits) {
      _timeSub = _firestore
          .collection(TimeCardChangeRequestRepository.collectionName)
          .snapshots()
          .listen(
        (snapshot) {
          _PendingHint? newest;
          var count = 0;
          for (final doc in snapshot.docs) {
            final data = doc.data();
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
              id: doc.id,
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

    _leaveSub = _firestore
        .collection(LeaveRequestRepository.collectionName)
        .snapshots()
        .listen(
      (snapshot) {
        _PendingHint? newest;
        var count = 0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
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
            id: doc.id,
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
        _emit();
      },
      onError: (_) {
        _leavePending = 0;
        _latestLeave = null;
        _emit();
      },
    );

    _clockSub = _firestore
        .collection(ClockRequestRepository.collectionName)
        .snapshots()
        .listen(
      (snapshot) {
        _PendingHint? newest;
        var count = 0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final status = data['status']?.toString().toLowerCase() ?? '';
          if (status != 'pending') continue;
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
            id: doc.id,
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
        _emit();
      },
      onError: (_) {
        _clockPending = 0;
        _latestClock = null;
        _emit();
      },
    );
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
      if (_latestLeave != null) _latestLeave!,
      if (_latestTime != null) _latestTime!,
      if (_latestClock != null) _latestClock!,
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
    final value = data['createdAt'] ?? data['updatedAt'] ?? data['requestedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _stop() {
    _timeSub?.cancel();
    _leaveSub?.cancel();
    _clockSub?.cancel();
    _timeSub = null;
    _leaveSub = null;
    _clockSub = null;
    _listening = false;
    _seeded = false;
    _includeTimeEdits = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
