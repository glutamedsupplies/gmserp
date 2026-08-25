import '../models/activity_log_entry.dart';
import '../models/leave_request.dart';
import '../models/time_card_change_request.dart';
import 'leave_request_repository.dart';
import 'time_card_change_request_repository.dart';

class ActivityLogRepository {
  ActivityLogRepository({
    LeaveRequestRepository? leaveRepository,
    TimeCardChangeRequestRepository? timeChangeRepository,
  })  : _leaveRepository = leaveRepository ?? LeaveRequestRepository(),
        _timeChangeRepository =
            timeChangeRepository ?? TimeCardChangeRequestRepository();

  final LeaveRequestRepository _leaveRepository;
  final TimeCardChangeRequestRepository _timeChangeRepository;

  Future<List<ActivityLogEntry>> listResolved() async {
    final results = await Future.wait([
      _leaveRepository.listAll(),
      _timeChangeRepository.listAll(),
    ]);

    final leaves = results[0] as List<LeaveRequest>;
    final timeEdits = results[1] as List<TimeCardChangeRequest>;

    final logs = <ActivityLogEntry>[
      for (final leave in leaves)
        if (_isResolved(leave.status)) _fromLeave(leave),
      for (final change in timeEdits)
        if (_isResolved(change.status)) _fromTimeEdit(change),
    ];

    logs.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return logs;
  }

  /// Approved/declined leave and time-card outcomes for one employee or admin.
  Future<List<ActivityLogEntry>> listResolvedForUser(String userId) async {
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

    final seenTimeIds = <String>{};
    final logs = <ActivityLogEntry>[
      for (final leave in leaves)
        if (_isResolved(leave.status))
          _fromLeave(leave, forViewerId: userId),
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
    return logs;
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
    final isMine =
        forViewerId != null && leave.userId == forViewerId;
    final summary = isMine
        ? (approved
            ? 'Your leave request was approved'
            : 'Your leave request was declined')
        : (approved ? 'Leave approved' : 'Leave rejected');
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
      detail: leave.reason.trim().isEmpty
          ? range
          : '${leave.reason.trim()} · $range',
      occurredAt: leave.updatedAt ?? leave.createdAt ?? DateTime.now(),
      leaveRange: range,
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
      workDate: change.workDate,
      summary: summary,
      detail: '$current → $proposed',
      occurredAt: change.updatedAt ?? change.createdAt ?? DateTime.now(),
    );
  }
}
