import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/leave_request_repository.dart';
import '../services/notification_service.dart';
import '../services/time_card_change_request_repository.dart';

/// Pending inbox count for Super Admin (Requests page + burger + app icon).
class PendingRequestsProvider extends ChangeNotifier {
  PendingRequestsProvider({
    TimeCardChangeRequestRepository? timeChangeRepository,
    FirebaseFirestore? firestore,
    NotificationService? notifications,
    bool Function()? notificationsEnabled,
  })  : _timeChangeRepository =
            timeChangeRepository ?? TimeCardChangeRequestRepository(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _notifications = notifications ?? NotificationService.instance,
        _notificationsEnabled = notificationsEnabled ?? (() => true);

  final TimeCardChangeRequestRepository _timeChangeRepository;
  final FirebaseFirestore _firestore;
  final NotificationService _notifications;
  final bool Function() _notificationsEnabled;

  StreamSubscription<int>? _timeSub;
  StreamSubscription<int>? _leaveSub;
  bool _listening = false;
  bool _seeded = false;

  int _timePending = 0;
  int _leavePending = 0;
  int pendingCount = 0;

  bool get hasPending => pendingCount > 0;

  String get badgeLabel {
    if (pendingCount <= 0) return '';
    if (pendingCount > 99) return '99+';
    return '$pendingCount';
  }

  void syncUser(UserModel? user) {
    if (user == null || user.role != UserRole.superAdmin) {
      _stop();
      if (pendingCount != 0 || _timePending != 0 || _leavePending != 0) {
        _timePending = 0;
        _leavePending = 0;
        pendingCount = 0;
        notifyListeners();
      }
      unawaited(_notifications.clearAll());
      return;
    }

    if (_listening) {
      // Keep badge / silent notification in sync when settings change.
      unawaited(
        _notifications.syncSuperAdminPending(
          count: pendingCount,
          notificationsEnabled: _notificationsEnabled(),
          announceIncrease: false,
        ),
      );
      return;
    }
    _listening = true;
    _seeded = false;

    _timeSub = _timeChangeRepository.watchPendingCount().listen(
      (value) {
        _timePending = value;
        _emit();
      },
      onError: (_) {
        _timePending = 0;
        _emit();
      },
    );

    _leaveSub = _firestore
        .collection(LeaveRequestRepository.collectionName)
        .snapshots()
        .map((snapshot) {
      var total = 0;
      for (final doc in snapshot.docs) {
        final status = doc.data()['status']?.toString().toLowerCase() ?? '';
        if (status == 'pending') total += 1;
      }
      return total;
    }).listen(
      (value) {
        _leavePending = value;
        _emit();
      },
      onError: (_) {
        _leavePending = 0;
        _emit();
      },
    );
  }

  /// Call when the notifications setting is toggled.
  Future<void> refreshNotificationPrefs() async {
    if (!_listening) {
      await _notifications.clearAll();
      return;
    }
    await _notifications.syncSuperAdminPending(
      count: pendingCount,
      notificationsEnabled: _notificationsEnabled(),
      announceIncrease: false,
    );
  }

  void _emit() {
    final total = _timePending + _leavePending;
    final wasSeeded = _seeded;
    if (pendingCount == total && wasSeeded) {
      return;
    }
    pendingCount = total;
    _seeded = true;
    notifyListeners();

    unawaited(
      _notifications.syncSuperAdminPending(
        count: total,
        notificationsEnabled: _notificationsEnabled(),
        announceIncrease: wasSeeded,
      ),
    );
  }

  void _stop() {
    _timeSub?.cancel();
    _leaveSub?.cancel();
    _timeSub = null;
    _leaveSub = null;
    _listening = false;
    _seeded = false;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
