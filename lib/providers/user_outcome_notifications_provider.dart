import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/announcement.dart';
import '../models/company_model.dart';
import '../models/salary_rate_change.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/announcement_repository.dart';
import '../services/leave_request_repository.dart';
import '../services/notification_seen_store.dart';
import '../services/notification_service.dart';
import '../services/salary_rate_change_repository.dart';
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

/// Watches leave / time-card / salary outcomes for Employee, Admin & Super Admin
/// and keeps local notifications for unseen items.
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _salarySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _announceSub;

  String? _userId;
  String? _activeCompanyId;
  String? _activeCompanyDocId;
  bool _companyUnlocked = false;
  bool _listening = false;
  bool _seeded = false;

  final Map<String, _OutcomeItem> _leaveOutcomes = {};
  final Map<String, _OutcomeItem> _timeAsRequester = {};
  final Map<String, _OutcomeItem> _timeAsEmployee = {};
  final Map<String, _OutcomeItem> _salaryOutcomes = {};
  final Map<String, _OutcomeItem> _announceOutcomes = {};

  Set<String> _seen = {};
  Set<String> _announced = {};

  Map<String, _OutcomeItem> get _outcomes {
    final merged = <String, _OutcomeItem>{
      ..._leaveOutcomes,
      ..._timeAsEmployee,
      ..._timeAsRequester, // requester wording wins when both
      ..._salaryOutcomes,
      ..._announceOutcomes,
    };
    return merged;
  }

  int get unseenCount =>
      _outcomes.keys.where((id) => !_seen.contains(id)).length;

  bool isSeen(String entryId) => _seen.contains(entryId);

  /// True when [entryId] is in the personal inbox stream (badge source).
  bool isTrackedOutcome(String entryId) => _outcomes.containsKey(entryId);

  bool isTrackedUnseen(String entryId) =>
      isTrackedOutcome(entryId) && !isSeen(entryId);

  void syncUser(
    UserModel? user, {
    CompanyModel? activeCompany,
    bool companyUnlocked = true,
  }) {
    final role = user?.role;
    final allowed = role == UserRole.employee ||
        role == UserRole.admin ||
        role == UserRole.superAdmin;
    final needsCompanyGate =
        role == UserRole.employee || role == UserRole.admin;
    final canListen = user != null &&
        allowed &&
        (!needsCompanyGate || (companyUnlocked && activeCompany != null));

    if (!canListen) {
      final hadUser = _userId != null;
      _stop(cancelTray: hadUser);
      if (hadUser) notifyListeners();
      return;
    }

    final companyId = activeCompany?.id;
    final companyDocId = activeCompany?.firestoreId;
    if (_listening &&
        _userId == user.id &&
        _companyUnlocked == companyUnlocked &&
        _activeCompanyId == companyId &&
        _activeCompanyDocId == companyDocId) {
      return;
    }

    _stop(cancelTray: true);
    _userId = user.id;
    _activeCompanyId = companyId;
    _activeCompanyDocId = companyDocId;
    _companyUnlocked = companyUnlocked;
    _listening = true;
    _seeded = false;
    unawaited(_start(user.id));
  }

  bool _matchesActiveCompany(String companyId, String companyDocumentId) {
    final activeId = _activeCompanyId;
    if (activeId == null) return true;
    final activeDoc = _activeCompanyDocId;
    if (companyId == activeId || companyDocumentId == activeId) return true;
    if (activeDoc != null &&
        (companyId == activeDoc || companyDocumentId == activeDoc)) {
      return true;
    }
    return companyId.isEmpty && companyDocumentId.isEmpty;
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

    _salarySub = _firestore
        .collection(SalaryRateChangeRepository.collectionName)
        .where('recipientIds', arrayContains: userId)
        .snapshots()
        .listen((snapshot) {
      _salaryOutcomes
        ..clear()
        ..addAll(_parseSalaryOutcomes(snapshot, userId: userId));
      unawaited(_syncLocalNotifications(userId));
      notifyListeners();
    });

    _announceSub = _firestore
        .collection(AnnouncementRepository.collectionName)
        .where('recipientIds', arrayContains: userId)
        .snapshots()
        .listen((snapshot) {
      _announceOutcomes
        ..clear()
        ..addAll(_parseAnnouncementOutcomes(snapshot));
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
      final companyId = data['companyId']?.toString() ?? '';
      final companyDocumentId = data['companyDocumentId']?.toString() ?? '';
      if (!_matchesActiveCompany(companyId, companyDocumentId)) continue;

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
      final reviewer = data['reviewedByName']?.toString().trim() ?? '';
      final body = [
        if (range.isNotEmpty) 'Leave $range',
        if (company.isNotEmpty) company,
        if (reviewer.isNotEmpty)
          approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
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
      final companyId = data['companyId']?.toString() ?? '';
      final companyDocumentId = data['companyDocumentId']?.toString() ?? '';
      if (!_matchesActiveCompany(companyId, companyDocumentId)) continue;

      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'time:${doc.id}';
      final approved = status == 'approved';
      final workDate = data['workDate']?.toString() ?? '';
      final employeeName = data['employeeName']?.toString().trim() ?? '';
      final reviewer = data['reviewedByName']?.toString().trim() ?? '';
      final String body;
      if (asRequester) {
        body = [
          if (employeeName.isNotEmpty) employeeName,
          if (workDate.isNotEmpty) 'Date $workDate',
          if (reviewer.isNotEmpty)
            approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
        ].join(' · ');
      } else {
        body = [
          if (workDate.isNotEmpty)
            'Date $workDate was ${approved ? 'approved' : 'declined'}'
          else
            'A time card change for you was ${approved ? 'approved' : 'declined'}',
          if (reviewer.isNotEmpty)
            approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
        ].join(' · ');
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

  Map<String, _OutcomeItem> _parseSalaryOutcomes(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    required String userId,
  }) {
    final map = <String, _OutcomeItem>{};
    for (final doc in snapshot.docs) {
      final change = SalaryRateChange.fromFirestore(id: doc.id, data: doc.data());
      if (!_matchesActiveCompany(change.companyId, change.companyDocumentId)) {
        continue;
      }
      final isEmployee = change.employeeId == userId;
      final title = isEmployee
          ? 'Daily salary rate updated'
          : 'Staff salary rate updated';
      final body = isEmployee
          ? change.rateChangeLabel
          : [
              if (change.employeeName.isNotEmpty) change.employeeName,
              change.rateChangeLabel,
              if (change.companyName.isNotEmpty) change.companyName,
            ].join(' · ');
      map['salary:${doc.id}'] = _OutcomeItem(
        entryId: 'salary:${doc.id}',
        title: title,
        body: body,
        updatedAt: change.createdAt ?? DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseAnnouncementOutcomes(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = <String, _OutcomeItem>{};
    for (final doc in snapshot.docs) {
      final item = Announcement.fromFirestore(id: doc.id, data: doc.data());
      if (!_matchesActiveCompany(item.companyId, item.companyDocumentId)) {
        continue;
      }
      final body = [
        if (item.message.isNotEmpty) item.message,
        if (item.companyName.isNotEmpty) item.companyName,
      ].join(' · ');
      map['announce:${doc.id}'] = _OutcomeItem(
        entryId: 'announce:${doc.id}',
        title: item.subject.isEmpty ? 'Announcement' : item.subject,
        body: body.isEmpty ? 'New announcement' : body,
        updatedAt: item.createdAt ?? DateTime.now(),
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

  void _stop({bool cancelTray = false}) {
    final toCancel = cancelTray
        ? {..._announced, ..._seen, ..._outcomes.keys}
        : const <String>{};
    _leaveSub?.cancel();
    _requesterSub?.cancel();
    _employeeSub?.cancel();
    _salarySub?.cancel();
    _announceSub?.cancel();
    _leaveSub = null;
    _requesterSub = null;
    _employeeSub = null;
    _salarySub = null;
    _announceSub = null;
    _listening = false;
    _seeded = false;
    _userId = null;
    _activeCompanyId = null;
    _activeCompanyDocId = null;
    _companyUnlocked = false;
    _leaveOutcomes.clear();
    _timeAsRequester.clear();
    _timeAsEmployee.clear();
    _salaryOutcomes.clear();
    _announceOutcomes.clear();
    _seen = {};
    _announced = {};
    for (final id in toCancel) {
      unawaited(_notifications.cancelRequestOutcome(id));
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
