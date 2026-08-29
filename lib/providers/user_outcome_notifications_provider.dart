import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/firebase_data.dart';
import '../core/utils/rtdb_platform.dart';
import '../models/activity_log_entry.dart';
import '../models/announcement.dart';
import '../models/company_model.dart';
import '../models/salary_rate_change.dart';
import '../models/time_card_profile_change.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import '../services/notification_seen_store.dart';
import '../services/notification_service.dart';
import '../services/rtdb/rtdb_desktop_limiter.dart';
import '../services/rtdb/rtdb_paths.dart';
import '../services/rtdb/rtdb_service.dart';

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
    RtdbService? rtdb,
    NotificationService? notifications,
    NotificationSeenStore? seenStore,
  })  : _rtdb = rtdb ?? RtdbService(),
        _notifications = notifications ?? NotificationService.instance,
        _seenStore = seenStore ?? NotificationSeenStore.instance;

  final RtdbService _rtdb;
  final NotificationService _notifications;
  final NotificationSeenStore _seenStore;

  StreamSubscription<DatabaseEvent>? _leaveSub;
  StreamSubscription<DatabaseEvent>? _requesterSub;
  StreamSubscription<DatabaseEvent>? _employeeSub;
  StreamSubscription<DatabaseEvent>? _salarySub;
  StreamSubscription<DatabaseEvent>? _profileSub;
  StreamSubscription<DatabaseEvent>? _clockSub;
  StreamSubscription<DatabaseEvent>? _announceSub;
  Timer? _pollTimer;
  bool _polling = false;

  String? _userId;
  String? _activeCompanyId;
  String? _activeCompanyDocId;
  bool _companyUnlocked = false;
  bool _listening = false;
  bool _seeded = false;
  bool _superAdminMode = false;

  final Map<String, _OutcomeItem> _leaveOutcomes = {};
  final Map<String, _OutcomeItem> _timeAsRequester = {};
  final Map<String, _OutcomeItem> _timeAsEmployee = {};
  final Map<String, _OutcomeItem> _salaryOutcomes = {};
  final Map<String, _OutcomeItem> _profileOutcomes = {};
  final Map<String, _OutcomeItem> _clockOutcomes = {};
  final Map<String, _OutcomeItem> _announceOutcomes = {};

  Set<String> _seen = {};
  Set<String> _announced = {};

  Map<String, _OutcomeItem> get _outcomes {
    final merged = <String, _OutcomeItem>{
      ..._leaveOutcomes,
      ..._timeAsEmployee,
      ..._timeAsRequester,
      ..._salaryOutcomes,
      ..._profileOutcomes,
      ..._clockOutcomes,
      ..._announceOutcomes,
    };
    return merged;
  }

  int get unseenCount =>
      _outcomes.keys.where((id) => !_seen.contains(id)).length;

  bool isSeen(String entryId) => _seen.contains(entryId);

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
    _superAdminMode = role == UserRole.superAdmin;
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

    if (preferRtdbPolling) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!_listening || _userId != userId) return;
        unawaited(_pollOnce(userId));
        _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
          unawaited(_pollOnce(userId));
        });
      });
      return;
    }

    _leaveSub = _rtdb.onValue(RtdbPaths.leaveRequests).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          if (entry.value['userId']?.toString() == userId) {
            filtered[entry.key] = entry.value;
          }
        }
        _leaveOutcomes
          ..clear()
          ..addAll(_parseLeaveOutcomes(filtered));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known leave outcomes on transient RTDB errors.
      },
    );

    _requesterSub = _rtdb.onValue(RtdbPaths.timeCardChangeRequests).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          if (entry.value['requesterId']?.toString() == userId) {
            filtered[entry.key] = entry.value;
          }
        }
        _timeAsRequester
          ..clear()
          ..addAll(_parseTimeOutcomes(filtered, asRequester: true));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known requester outcomes on transient RTDB errors.
      },
    );

    _employeeSub = _rtdb.onValue(RtdbPaths.timeCardChangeRequests).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          if (entry.value['employeeId']?.toString() == userId) {
            filtered[entry.key] = entry.value;
          }
        }
        _timeAsEmployee
          ..clear()
          ..addAll(_parseTimeOutcomes(filtered, asRequester: false));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known employee outcomes on transient RTDB errors.
      },
    );

    _clockSub = _rtdb.onValue(RtdbPaths.clockRequests).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          if (entry.value['userId']?.toString() == userId) {
            filtered[entry.key] = entry.value;
          }
        }
        _clockOutcomes
          ..clear()
          ..addAll(_parseClockOutcomes(filtered));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known clock outcomes on transient RTDB errors.
      },
    );

    _salarySub = _rtdb.onValue(RtdbPaths.salaryRateChanges).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          final recipients = parseRecipientIds(entry.value['recipientIds']);
          if (recipients.contains(userId)) {
            filtered[entry.key] = entry.value;
          }
        }
        _salaryOutcomes
          ..clear()
          ..addAll(_parseSalaryOutcomes(filtered, userId: userId));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known salary outcomes on transient RTDB errors.
      },
    );

    _profileSub = _rtdb.onValue(RtdbPaths.timeCardProfileChanges).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          final recipients = parseRecipientIds(entry.value['recipientIds']);
          if (recipients.contains(userId)) {
            filtered[entry.key] = entry.value;
          }
        }
        _profileOutcomes
          ..clear()
          ..addAll(_parseProfileOutcomes(filtered, userId: userId));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known profile outcomes on transient RTDB errors.
      },
    );

    _announceSub = _rtdb.onValue(RtdbPaths.announcements).listen(
      (event) {
        final children = RtdbService.snapshotChildren(event.snapshot);
        final filtered = <String, Map<String, dynamic>>{};
        for (final entry in children.entries) {
          final recipients = parseRecipientIds(entry.value['recipientIds']);
          if (recipients.contains(userId)) {
            filtered[entry.key] = entry.value;
          }
        }
        _announceOutcomes
          ..clear()
          ..addAll(_parseAnnouncementOutcomes(filtered));
        unawaited(_syncLocalNotifications(userId));
        notifyListeners();
      },
      onError: (_) {
        // Keep last known announcement outcomes on transient RTDB errors.
      },
    );
  }

  Future<void> _pollOnce(String userId) async {
    if (!_listening ||
        _userId != userId ||
        _polling ||
        RtdbDesktopLimiter.isHeavyLoading) {
      return;
    }
    _polling = true;
    try {
      final skipInboxPaths = preferRtdbPolling && _superAdminMode;
      if (!skipInboxPaths) {
        final leaves = await _rtdb.getChildren(RtdbPaths.leaveRequests);
        final leaveFiltered = <String, Map<String, dynamic>>{};
        for (final entry in leaves.entries) {
          if (entry.value['userId']?.toString() == userId) {
            leaveFiltered[entry.key] = entry.value;
          }
        }
        _leaveOutcomes
          ..clear()
          ..addAll(_parseLeaveOutcomes(leaveFiltered));

        final timeChanges =
            await _rtdb.getChildren(RtdbPaths.timeCardChangeRequests);
        final asRequester = <String, Map<String, dynamic>>{};
        final asEmployee = <String, Map<String, dynamic>>{};
        for (final entry in timeChanges.entries) {
          if (entry.value['requesterId']?.toString() == userId) {
            asRequester[entry.key] = entry.value;
          }
          if (entry.value['employeeId']?.toString() == userId) {
            asEmployee[entry.key] = entry.value;
          }
        }
        _timeAsRequester
          ..clear()
          ..addAll(_parseTimeOutcomes(asRequester, asRequester: true));
        _timeAsEmployee
          ..clear()
          ..addAll(_parseTimeOutcomes(asEmployee, asRequester: false));

        final clocks = await _rtdb.getChildren(RtdbPaths.clockRequests);
        final clockFiltered = <String, Map<String, dynamic>>{};
        for (final entry in clocks.entries) {
          if (entry.value['userId']?.toString() == userId) {
            clockFiltered[entry.key] = entry.value;
          }
        }
        _clockOutcomes
          ..clear()
          ..addAll(_parseClockOutcomes(clockFiltered));
      }
      // Personal leave/time/clock on desktop Super Admin are synced when the
      // Activity page loads; do not clear them here or the badge orphan counts.

      final salary = await _rtdb.getChildren(RtdbPaths.salaryRateChanges);
      final salaryFiltered = <String, Map<String, dynamic>>{};
      for (final entry in salary.entries) {
        final recipients = parseRecipientIds(entry.value['recipientIds']);
        if (recipients.contains(userId)) {
          salaryFiltered[entry.key] = entry.value;
        }
      }
      _salaryOutcomes
        ..clear()
        ..addAll(_parseSalaryOutcomes(salaryFiltered, userId: userId));

      final profiles =
          await _rtdb.getChildren(RtdbPaths.timeCardProfileChanges);
      final profileFiltered = <String, Map<String, dynamic>>{};
      for (final entry in profiles.entries) {
        final recipients = parseRecipientIds(entry.value['recipientIds']);
        if (recipients.contains(userId)) {
          profileFiltered[entry.key] = entry.value;
        }
      }
      _profileOutcomes
        ..clear()
        ..addAll(_parseProfileOutcomes(profileFiltered, userId: userId));

      final announces = await _rtdb.getChildren(RtdbPaths.announcements);
      final announceFiltered = <String, Map<String, dynamic>>{};
      for (final entry in announces.entries) {
        final recipients = parseRecipientIds(entry.value['recipientIds']);
        if (recipients.contains(userId)) {
          announceFiltered[entry.key] = entry.value;
        }
      }
      _announceOutcomes
        ..clear()
        ..addAll(_parseAnnouncementOutcomes(announceFiltered));

      unawaited(_syncLocalNotifications(userId));
      notifyListeners();
    } catch (_) {
      // Keep last known inbox state on transient RTDB errors.
    } finally {
      _polling = false;
    }
  }

  Map<String, _OutcomeItem> _parseLeaveOutcomes(
    Map<String, Map<String, dynamic>> children,
  ) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final data = entry.value;
      final companyId = data['companyId']?.toString() ?? '';
      final companyDocumentId = data['companyDocumentId']?.toString() ?? '';
      if (!_matchesActiveCompany(companyId, companyDocumentId)) continue;

      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'leave:${entry.key}';
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
        updatedAt: parseFirebaseDate(data['updatedAt']) ??
            parseFirebaseDate(data['createdAt']) ??
            DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseTimeOutcomes(
    Map<String, Map<String, dynamic>> children, {
    required bool asRequester,
  }) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final data = entry.value;
      final companyId = data['companyId']?.toString() ?? '';
      final companyDocumentId = data['companyDocumentId']?.toString() ?? '';
      if (!_matchesActiveCompany(companyId, companyDocumentId)) continue;

      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'time:${entry.key}';
      final approved = status == 'approved';
      final workDate = data['workDate']?.toString() ?? '';
      final employeeName = data['employeeName']?.toString().trim() ?? '';
      final reviewer = data['reviewedByName']?.toString().trim() ?? '';
      final direct = data['source']?.toString() == 'directEdit';
      final String body;
      if (direct) {
        body = [
          if (employeeName.isNotEmpty && asRequester) employeeName,
          if (workDate.isNotEmpty) 'Date $workDate',
          if (reviewer.isNotEmpty) 'Updated by $reviewer',
        ].join(' · ');
      } else if (asRequester) {
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

      final String title;
      if (direct) {
        title = asRequester
            ? 'Time entry updated'
            : 'Your time entry was updated';
      } else {
        title = approved ? 'Time change approved' : 'Time change declined';
      }

      map[entryId] = _OutcomeItem(
        entryId: entryId,
        title: title,
        body: body.isEmpty
            ? (direct
                ? 'Time entry was updated.'
                : (approved
                    ? 'Your time change request was approved.'
                    : 'Your time change request was declined.'))
            : body,
        updatedAt: parseFirebaseDate(data['updatedAt']) ??
            parseFirebaseDate(data['createdAt']) ??
            DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseSalaryOutcomes(
    Map<String, Map<String, dynamic>> children, {
    required String userId,
  }) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final change =
          SalaryRateChange.fromFirestore(id: entry.key, data: entry.value);
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
      map['salary:${entry.key}'] = _OutcomeItem(
        entryId: 'salary:${entry.key}',
        title: title,
        body: body,
        updatedAt: change.createdAt ?? DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseClockOutcomes(
    Map<String, Map<String, dynamic>> children,
  ) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final data = entry.value;
      final companyId = data['companyId']?.toString() ?? '';
      final companyDocumentId = data['companyDocumentId']?.toString() ?? '';
      if (!_matchesActiveCompany(companyId, companyDocumentId)) continue;

      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status != 'approved' && status != 'rejected') continue;

      final entryId = 'clock:${entry.key}';
      final approved = status == 'approved';
      final type = data['type']?.toString() == 'clockOut' ? 'Time out' : 'Time in';
      final workDate = data['workDate']?.toString() ?? '';
      final reviewer = data['reviewedByName']?.toString().trim() ?? '';
      final body = [
        if (workDate.isNotEmpty) 'Date $workDate',
        if (reviewer.isNotEmpty)
          approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
      ].join(' · ');

      map[entryId] = _OutcomeItem(
        entryId: entryId,
        title: approved ? '$type approved' : '$type declined',
        body: body.isEmpty
            ? (approved
                ? 'Your $type request was approved.'
                : 'Your $type request was declined.')
            : body,
        updatedAt: parseFirebaseDate(data['updatedAt']) ??
            parseFirebaseDate(data['createdAt']) ??
            DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseProfileOutcomes(
    Map<String, Map<String, dynamic>> children, {
    required String userId,
  }) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final change =
          TimeCardProfileChange.fromFirestore(id: entry.key, data: entry.value);
      if (!_matchesActiveCompany(change.companyId, change.companyDocumentId)) {
        continue;
      }
      final isEmployee = change.employeeId == userId;
      final isActor = change.actorId == userId;
      final title = isEmployee
          ? 'Time card settings updated'
          : isActor
              ? 'Time card settings saved'
              : 'Employee time card updated';
      final body = isEmployee
          ? '${change.changeSummary} · by ${change.actorName.isEmpty ? 'Admin' : change.actorName}'
          : [
              if (change.employeeName.isNotEmpty) change.employeeName,
              change.changeSummary,
              if (change.companyName.isNotEmpty) change.companyName,
            ].join(' · ');
      map['profile:${entry.key}'] = _OutcomeItem(
        entryId: 'profile:${entry.key}',
        title: title,
        body: body,
        updatedAt: change.createdAt ?? DateTime.now(),
      );
    }
    return map;
  }

  Map<String, _OutcomeItem> _parseAnnouncementOutcomes(
    Map<String, Map<String, dynamic>> children,
  ) {
    final map = <String, _OutcomeItem>{};
    for (final entry in children.entries) {
      final item = Announcement.fromFirestore(id: entry.key, data: entry.value);
      if (!_matchesActiveCompany(item.companyId, item.companyDocumentId)) {
        continue;
      }
      final body = [
        if (item.message.isNotEmpty) item.message,
        if (item.companyName.isNotEmpty) item.companyName,
      ].join(' · ');
      map['announce:${entry.key}'] = _OutcomeItem(
        entryId: 'announce:${entry.key}',
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

  /// Keeps the header badge aligned with personal rows the Activity page loaded.
  Future<void> applyPersonalActivityEntries(
    List<ActivityLogEntry> entries,
  ) async {
    final userId = _userId;
    if (userId == null) return;

    _leaveOutcomes.clear();
    _timeAsRequester.clear();
    _timeAsEmployee.clear();
    _clockOutcomes.clear();
    _salaryOutcomes.clear();
    _profileOutcomes.clear();
    _announceOutcomes.clear();

    for (final entry in entries) {
      final item = _OutcomeItem(
        entryId: entry.id,
        title: entry.summary,
        body: entry.detail.isNotEmpty ? entry.detail : entry.summary,
        updatedAt: entry.occurredAt,
      );
      switch (entry.kind) {
        case ActivityLogKind.leave:
          _leaveOutcomes[entry.id] = item;
        case ActivityLogKind.timeEdit:
          _timeAsRequester[entry.id] = item;
        case ActivityLogKind.clock:
          _clockOutcomes[entry.id] = item;
        case ActivityLogKind.salaryRate:
          _salaryOutcomes[entry.id] = item;
        case ActivityLogKind.timeCardSettings:
          _profileOutcomes[entry.id] = item;
        case ActivityLogKind.announcement:
          _announceOutcomes[entry.id] = item;
      }
    }

    notifyListeners();
    await _syncLocalNotifications(userId);
  }

  void _stop({bool cancelTray = false}) {
    final toCancel = cancelTray
        ? {..._announced, ..._seen, ..._outcomes.keys}
        : const <String>{};
    _pollTimer?.cancel();
    _pollTimer = null;
    _leaveSub?.cancel();
    _requesterSub?.cancel();
    _employeeSub?.cancel();
    _salarySub?.cancel();
    _profileSub?.cancel();
    _clockSub?.cancel();
    _announceSub?.cancel();
    _leaveSub = null;
    _requesterSub = null;
    _employeeSub = null;
    _salarySub = null;
    _profileSub = null;
    _clockSub = null;
    _announceSub = null;
    _listening = false;
    _seeded = false;
    _polling = false;
    _superAdminMode = false;
    _userId = null;
    _activeCompanyId = null;
    _activeCompanyDocId = null;
    _companyUnlocked = false;
    _leaveOutcomes.clear();
    _timeAsRequester.clear();
    _timeAsEmployee.clear();
    _salaryOutcomes.clear();
    _profileOutcomes.clear();
    _clockOutcomes.clear();
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
