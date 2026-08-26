enum ActivityLogKind {
  timeEdit,
  clock,
  leave,
  salaryRate,
  announcement,
}

/// Super Admin audit log / Notifications inbox entry.
class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.kind,
    required this.status,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.subjectName,
    required this.subjectEmail,
    required this.summary,
    required this.detail,
    required this.occurredAt,
    this.actorName = '',
    this.reviewerName = '',
    this.workDate = '',
    this.leaveRange = '',
  });

  final String id;
  final ActivityLogKind kind;
  final String status;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String subjectName;
  final String subjectEmail;
  final String summary;
  final String detail;
  final DateTime occurredAt;
  /// Requester / sender / salary updater.
  final String actorName;
  /// Who approved or declined the request.
  final String reviewerName;
  final String workDate;
  final String leaveRange;

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';
  bool get isSalaryUpdate => kind == ActivityLogKind.salaryRate;
  bool get isAnnouncement => kind == ActivityLogKind.announcement;

  String get kindLabel {
    switch (kind) {
      case ActivityLogKind.timeEdit:
        return 'Time card';
      case ActivityLogKind.clock:
        return 'Time in / out';
      case ActivityLogKind.leave:
        return 'Leave';
      case ActivityLogKind.salaryRate:
        return 'Salary';
      case ActivityLogKind.announcement:
        return 'Announcement';
    }
  }

  String get statusLabel {
    if (status.isEmpty) return status;
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  String get decisionLabel {
    if (reviewerName.trim().isEmpty) return '';
    if (isApproved) return 'Approved by $reviewerName';
    if (isRejected) return 'Declined by $reviewerName';
    return 'Reviewed by $reviewerName';
  }

  String get searchText => [
        kindLabel,
        status,
        companyName,
        subjectName,
        subjectEmail,
        actorName,
        reviewerName,
        summary,
        detail,
        workDate,
        leaveRange,
      ].join(' ').toLowerCase();
}
