import '../models/activity_log_entry.dart';
import '../models/announcement.dart';
import '../models/clock_request.dart';
import '../models/leave_request.dart';
import '../models/salary_rate_change.dart';
import '../models/time_card_change_request.dart';
import 'announcement_repository.dart';
import 'clock_request_repository.dart';
import 'leave_request_repository.dart';
import 'salary_rate_change_repository.dart';
import 'time_card_change_request_repository.dart';

class ActivityLogRepository {
  ActivityLogRepository({
    LeaveRequestRepository? leaveRepository,
    TimeCardChangeRequestRepository? timeChangeRepository,
    ClockRequestRepository? clockRepository,
    SalaryRateChangeRepository? salaryRateRepository,
    AnnouncementRepository? announcementRepository,
  })  : _leaveRepository = leaveRepository ?? LeaveRequestRepository(),
        _timeChangeRepository =
            timeChangeRepository ?? TimeCardChangeRequestRepository(),
        _clockRepository = clockRepository ?? ClockRequestRepository(),
        _salaryRateRepository =
            salaryRateRepository ?? SalaryRateChangeRepository(),
        _announcementRepository =
            announcementRepository ?? AnnouncementRepository();

  final LeaveRequestRepository _leaveRepository;
  final TimeCardChangeRequestRepository _timeChangeRepository;
  final ClockRequestRepository _clockRepository;
  final SalaryRateChangeRepository _salaryRateRepository;
  final AnnouncementRepository _announcementRepository;

  Future<List<ActivityLogEntry>> listResolved() async {
    final results = await Future.wait([
      _leaveRepository.listAll(),
      _timeChangeRepository.listAll(),
      _safeList(_clockRepository.listAll, const <ClockRequest>[]),
      _safeList(_salaryRateRepository.listAll, const <SalaryRateChange>[]),
      _safeList(_announcementRepository.listAll, const <Announcement>[]),
    ]);

    final leaves = results[0] as List<LeaveRequest>;
    final timeEdits = results[1] as List<TimeCardChangeRequest>;
    final clocks = results[2] as List<ClockRequest>;
    final salaryChanges = results[3] as List<SalaryRateChange>;
    final announcements = results[4] as List<Announcement>;

    final logs = <ActivityLogEntry>[
      for (final leave in leaves)
        if (_isResolved(leave.status)) _fromLeave(leave),
      for (final change in timeEdits)
        if (_isResolved(change.status)) _fromTimeEdit(change),
      for (final clock in clocks)
        if (_isResolved(clock.status)) _fromClock(clock),
      for (final change in salaryChanges) _fromSalary(change),
      for (final item in announcements) _fromAnnouncement(item),
    ];

    logs.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return logs;
  }

  /// Approved/declined leave, time-card, and clock outcomes for one user,
  /// plus salary / announcement updates addressed to that user.
  Future<List<ActivityLogEntry>> listResolvedForUser(
    String userId, {
    String? companyId,
    String? companyDocumentId,
  }) async {
    final leaves = await _safeList(
      () => _leaveRepository.listByUserId(userId),
      const <LeaveRequest>[],
    );
    final asRequester = await _safeList(
      () => _timeChangeRepository.listByRequester(userId),
      const <TimeCardChangeRequest>[],
    );
    final asEmployee = await _safeList(
      () => _timeChangeRepository.listByEmployeeId(userId),
      const <TimeCardChangeRequest>[],
    );
    final clocks = await _safeList(
      () => _clockRepository.listForUser(userId),
      const <ClockRequest>[],
    );
    final salaryChanges = await _safeList(
      () => _salaryRateRepository.listForRecipient(userId),
      const <SalaryRateChange>[],
    );
    final announcements = await _safeList(
      () => _announcementRepository.listForRecipient(userId),
      const <Announcement>[],
    );

    final seenTimeIds = <String>{};
    final logs = <ActivityLogEntry>[
      for (final leave in leaves)
        if (_isResolved(leave.status))
          _fromLeave(leave, forViewerId: userId),
      for (final clock in clocks)
        if (_isResolved(clock.status))
          _fromClock(clock, forViewerId: userId),
      for (final change in salaryChanges)
        _fromSalary(change, forViewerId: userId),
      for (final item in announcements) _fromAnnouncement(item),
    ];

    void addTime(TimeCardChangeRequest change) {
      if (!_isResolved(change.status)) return;
      if (!seenTimeIds.add(change.id)) return;
      logs.add(_fromTimeEdit(change, forViewerId: userId));
    }

    for (final change in asRequester) {
      addTime(change);
    }
    for (final change in asEmployee) {
      addTime(change);
    }

    logs.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (companyId == null && companyDocumentId == null) return logs;
    return logs
        .where(
          (entry) => _matchesCompany(
            entry,
            companyId: companyId,
            companyDocumentId: companyDocumentId,
          ),
        )
        .toList();
  }

  bool _matchesCompany(
    ActivityLogEntry entry, {
    String? companyId,
    String? companyDocumentId,
  }) {
    if (companyId != null &&
        (entry.companyId == companyId ||
            entry.companyDocumentId == companyId)) {
      return true;
    }
    if (companyDocumentId != null &&
        (entry.companyId == companyDocumentId ||
            entry.companyDocumentId == companyDocumentId)) {
      return true;
    }
    return false;
  }

  Future<List<T>> _safeList<T>(
    Future<List<T>> Function() load,
    List<T> fallback,
  ) async {
    try {
      return await load();
    } catch (_) {
      return fallback;
    }
  }

  bool _isResolved(String status) {
    final s = status.toLowerCase();
    return s == 'approved' || s == 'rejected';
  }

  ActivityLogEntry _fromLeave(LeaveRequest leave, {String? forViewerId}) {
    final approved = leave.status.toLowerCase() == 'approved';
    final range = '${leave.startDate} → ${leave.endDate}';
    final isMine = forViewerId != null && leave.userId == forViewerId;
    final reviewer = leave.reviewedByName.trim();
    final summary = isMine
        ? (approved
            ? 'Your leave request was approved'
            : 'Your leave request was declined')
        : (approved ? 'Leave approved' : 'Leave rejected');
    final detailParts = <String>[
      if (leave.reason.trim().isNotEmpty) leave.reason.trim(),
      range,
      if (reviewer.isNotEmpty)
        approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
    ];
    return ActivityLogEntry(
      id: 'leave:${leave.id}',
      kind: ActivityLogKind.leave,
      status: leave.status,
      companyId: leave.companyId,
      companyDocumentId: leave.companyDocumentId,
      companyName: leave.companyName,
      subjectName: leave.username,
      subjectEmail: leave.userEmail,
      summary: summary,
      detail: detailParts.join(' · '),
      occurredAt: leave.updatedAt ?? leave.createdAt ?? DateTime.now(),
      leaveRange: range,
      reviewerName: reviewer,
    );
  }

  ActivityLogEntry _fromTimeEdit(
    TimeCardChangeRequest change, {
    String? forViewerId,
  }) {
    final approved = change.status.toLowerCase() == 'approved';
    final current = change.hasPriorRecord
        ? '${change.currentTimeInLabel} → ${change.currentTimeOutLabel}'
        : 'No prior record';
    final proposed =
        '${change.proposedTimeInLabel} → ${change.proposedTimeOutLabel}';
    final asRequester =
        forViewerId != null && change.requesterId == forViewerId;
    final asEmployee =
        forViewerId != null && change.employeeId == forViewerId;
    final reviewer = change.reviewedByName.trim();
    final String summary;
    if (asRequester) {
      summary = approved
          ? 'Your time change request was approved'
          : 'Your time change request was declined';
    } else if (asEmployee) {
      summary = approved
          ? 'A time card change for you was approved'
          : 'A time card change for you was declined';
    } else {
      summary = approved ? 'Time change approved' : 'Time change rejected';
    }
    final detailParts = <String>[
      '$current → $proposed',
      if (change.note.trim().isNotEmpty) 'Note: ${change.note.trim()}',
      if (reviewer.isNotEmpty)
        approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
    ];
    return ActivityLogEntry(
      id: 'time:${change.id}',
      kind: ActivityLogKind.timeEdit,
      status: change.status,
      companyId: change.companyId,
      companyDocumentId: change.companyDocumentId,
      companyName: change.companyName,
      subjectName: change.employeeName,
      subjectEmail: change.employeeEmail,
      actorName: change.requesterName,
      reviewerName: reviewer,
      workDate: change.workDate,
      summary: summary,
      detail: detailParts.join(' · '),
      occurredAt: change.updatedAt ?? change.createdAt ?? DateTime.now(),
    );
  }

  ActivityLogEntry _fromClock(ClockRequest clock, {String? forViewerId}) {
    final approved = clock.status.toLowerCase() == 'approved';
    final isMine = forViewerId != null && clock.userId == forViewerId;
    final reviewer = clock.reviewedByName.trim();
    final kind = clock.typeLabel.toLowerCase();
    final summary = isMine
        ? (approved
            ? 'Your $kind request was approved'
            : 'Your $kind request was declined')
        : (approved
            ? '${clock.typeLabel} approved'
            : '${clock.typeLabel} rejected');
    final detailParts = <String>[
      'Date ${clock.workDate}',
      'Requested at ${clock.requestedAtLabel}',
      if (clock.note.trim().isNotEmpty) 'Note: ${clock.note.trim()}',
      if (reviewer.isNotEmpty)
        approved ? 'Approved by $reviewer' : 'Declined by $reviewer',
    ];
    return ActivityLogEntry(
      id: 'clock:${clock.id}',
      kind: ActivityLogKind.clock,
      status: clock.status,
      companyId: clock.companyId,
      companyDocumentId: clock.companyDocumentId,
      companyName: clock.companyName,
      subjectName: clock.username,
      subjectEmail: clock.userEmail,
      reviewerName: reviewer,
      workDate: clock.workDate,
      summary: summary,
      detail: detailParts.join(' · '),
      occurredAt: clock.updatedAt ?? clock.createdAt ?? clock.requestedAt,
    );
  }

  ActivityLogEntry _fromSalary(
    SalaryRateChange change, {
    String? forViewerId,
  }) {
    final isEmployee =
        forViewerId != null && change.employeeId == forViewerId;
    final summary = isEmployee
        ? 'Your daily salary rate was updated'
        : 'Daily salary rate updated';
    final actor = change.actorName.trim().isEmpty
        ? 'Admin'
        : change.actorName.trim();
    final detail = isEmployee
        ? '${change.rateChangeLabel} · by $actor'
        : '${change.employeeName.isEmpty ? 'Employee' : change.employeeName}'
            ' · ${change.rateChangeLabel} · by $actor';
    return ActivityLogEntry(
      id: 'salary:${change.id}',
      kind: ActivityLogKind.salaryRate,
      status: 'updated',
      companyId: change.companyId,
      companyDocumentId: change.companyDocumentId,
      companyName: change.companyName,
      subjectName: change.employeeName,
      subjectEmail: change.employeeEmail,
      actorName: change.actorName,
      summary: summary,
      detail: detail,
      occurredAt: change.createdAt ?? DateTime.now(),
    );
  }

  ActivityLogEntry _fromAnnouncement(Announcement item) {
    final actor =
        item.actorName.trim().isEmpty ? 'Super Admin' : item.actorName.trim();
    return ActivityLogEntry(
      id: 'announce:${item.id}',
      kind: ActivityLogKind.announcement,
      status: 'sent',
      companyId: item.companyId,
      companyDocumentId: item.companyDocumentId,
      companyName: item.companyName,
      subjectName: item.subject,
      subjectEmail: '',
      actorName: actor,
      summary: item.subject,
      detail: item.message,
      occurredAt: item.createdAt ?? DateTime.now(),
    );
  }
}
