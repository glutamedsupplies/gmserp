import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/leave_request_repository.dart';
import '../services/notification_seen_store.dart';
import '../services/notification_service.dart';
import '../services/time_card_change_request_repository.dart';

class _OutcomeItem {
  const _OutcomeItem({
    required this.entryId,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  final String entryId;
  final String title;
  final String body;
  final DateTime updatedAt;
}

/// Watches leave / time-card outcomes for Employee & Admin and keeps
/// local notifications for unseen items.
class UserOutcomeNotificationsProvider extends ChangeNotifier {
  UserOutcomeNotificationsProvider({
    FirebaseFirestore? firestore,
    NotificationService? notifications,
    NotificationSeenStore? seenStore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _notifications = notifications ?? NotificationService.instance,
        _seenStore = seenStore ?? NotificationSeenStore.instance;

  final FirebaseFirestore _firestore;
  final NotificationService _notifications;
  final NotificationSeenStore _seenStore;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leaveSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requesterSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _employeeSub;

  String? _userId;
  bool _listening = false;
  bool _seeded = false;

  final Map<String, _OutcomeItem> _leaveOutcomes = {};
  final Map<String, _OutcomeItem> _timeAsRequester = {};
  final Map<String, _OutcomeItem> _timeAsEmployee = {};

  Set<String> _seen = {};
  Set<String> _announced = {};

  Map<String, _OutcomeItem> get _outcomes {
    final merged = <String, _OutcomeItem>{
      ..._leaveOutcomes,
      ..._timeAsEmployee,
      ..._timeAsRequester, // requester wording wins when both
    };
    return merged;
  }

  int get unseenCount =>
      _outcomes.keys.where((id) => !_seen.contains(id)).length;

  bool isSeen(String entryId) => _seen.contains(entryId);

  void syncUser(UserModel? user) {
    final role = user?.role;
    final allowed = role == UserRole.employee || role == UserRole.admin;
    if (user == null || !allowed) {
      final hadUser = _userId != null;
      _stop();
      if (hadUser) notifyListeners();
      return;
    }

    if (_listening && _userId == user.id) return;

    _stop();
    _userId = user.id;
    _listening = true;
    _seeded = false;
    unawaited(_start(user.id));
  }

  Future<void> _start(String userId) async {
    _seen = await _seenStore.loadSeen(userId);
    _announced = await _seenStore.loadAnnounced(userId);
    if (!_listening || _userId != userId) return;

    unawaited(_notifications.requestPermission());

    _leaveSub = _firestore
        .collection(LeaveRequestRepository.collectionName)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _leaveOutcomes
        ..clear()
        ..addAll(_parseLeaveOutcomes(snapshot));
      unawaited(_syncLocalNotifications(userId));
      notifyListeners();
    });

    _requesterSub = _firestore
        .collection(TimeCardChangeRequestRepository.collectionName)
        .where('requesterId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _timeAsRequester
        ..clear()
        ..addAll(_parseTimeOutcomes(snapshot, asRequester: true));
      unawaited(_syncLocalNotifications(userId));
      notifyListeners();
    });

    _employeeSub = _firestore
        .collection(TimeCardChangeRequestRepository.collectionName)
        .where('employeeId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      _timeAsEmployee
        ..clear()
        ..addAll(_parseTimeOutcomes(snapshot, asRequester: false));
      unawaited(_syncLocalNotifications(userId));
      notifyListeners();
    });
  }

  Map<String, _OutcomeItem> _parseLeaveOutcomes(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = <String, _OutcomeItem>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'leave:${doc.id}';
      final approved = status == 'approved';
      final start = data['startDate']?.toString() ?? '';
      final end = data['endDate']?.toString() ?? '';
      final range = start.isEmpty
          ? ''
          : (end.isEmpty || end == start ? start : '$start → $end');
      final company = data['companyName']?.toString().trim() ?? '';
      final body = [
        if (range.isNotEmpty) 'Leave $range',
        if (company.isNotEmpty) company,
      ].join(' · ');

      map[entryId] = _OutcomeItem(
        entryId: entryId,
        title: approved ? 'Leave approved' : 'Leave declined',
        body: body.isEmpty
            ? (approved
                ? 'Your leave request was approved.'
                : 'Your leave request was declined.')
            : body,
        updatedAt: _parseDate(data['updatedAt']) ??
            _parseDate(data['createdAt']) ??
            DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseTimeOutcomes(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required bool asRequester,
  }) {
    final map = <String, _OutcomeItem>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'time:${doc.id}';
      final approved = status == 'approved';
      final workDate = data['workDate']?.toString() ?? '';
      final employeeName = data['employeeName']?.toString().trim() ?? '';
      final String body;
      if (asRequester) {
        body = [
          if (employeeName.isNotEmpty) employeeName,
          if (workDate.isNotEmpty) 'Date $workDate',
        ].join(' · ');
      } else {
        body = workDate.isEmpty
            ? 'A time card change for you was ${approved ? 'approved' : 'declined'}.'
            : 'Date $workDate was ${approved ? 'approved' : 'declined'}.';
      }

      map[entryId] = _OutcomeItem(
        entryId: entryId,
        title: approved ? 'Time change approved' : 'Time change declined',
        body: body.isEmpty
            ? (approved
                ? 'Your time change request was approved.'
                : 'Your time change request was declined.')
            : body,
        updatedAt: _parseDate(data['updatedAt']) ??
            _parseDate(data['createdAt']) ??
            DateTime.now(),
      );
    }
    return map;
  }

  Future<void> _syncLocalNotifications(String userId) async {
    if (_userId != userId) return;

    final outcomes = _outcomes;
    final liveIds = outcomes.keys.toSet();

    // Drop tray items that are no longer unresolved outcomes.
    for (final id in {..._announced, ..._seen}) {
      if (!liveIds.contains(id) || _seen.contains(id)) {
        await _notifications.cancelRequestOutcome(id);
      }
    }

    final unseen = outcomes.values
        .where((item) => !_seen.contains(item.entryId))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    for (final item in unseen) {
      final alreadyAnnounced = _announced.contains(item.entryId);
      final alert = _seeded && !alreadyAnnounced;
      await _notifications.showRequestOutcome(
        entryId: item.entryId,
        title: item.title,
        body: item.body,
        alert: alert,
      );
      if (!alreadyAnnounced) {
        _announced.add(item.entryId);
        await _seenStore.markAnnounced(userId, item.entryId);
      }
    }

    _seeded = true;
  }

  Future<void> markSeen(String entryId) async {
    await markLoadedSeen([entryId]);
  }

  /// Opening the notifications page marks loaded outcomes as seen and clears
  /// their local tray notifications.
  Future<void> markLoadedSeen(Iterable<String> entryIds) async {
    final userId = _userId;
    if (userId == null) return;
    final ids = entryIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    var changed = false;
    for (final id in ids) {
      if (_seen.add(id)) changed = true;
      await _notifications.cancelRequestOutcome(id);
    }
    if (!changed) return;

    await _seenStore.markSeenMany(userId, ids);
    notifyListeners();
  }

  Future<void> markSeenFromPayload(String? payload) async {
    final entryId = NotificationService.tryParseOutcomeEntryId(payload);
    if (entryId != null) {
      await markSeen(entryId);
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.tryParse(value.toString());
    }
  }

  void _stop() {
    _leaveSub?.cancel();
    _requesterSub?.cancel();
    _employeeSub?.cancel();
    _leaveSub = null;
    _requesterSub = null;
    _employeeSub = null;
    _listening = false;
    _seeded = false;
    _userId = null;
    _leaveOutcomes.clear();
    _timeAsRequester.clear();
    _timeAsEmployee.clear();
    _seen = {};
    _announced = {};
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
