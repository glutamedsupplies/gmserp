enum ActivityLogKind {
  timeEdit,
  leave,
}

/// Super Admin audit log built from resolved leave / time-card requests.
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
  final String actorName;
  final String workDate;
  final String leaveRange;

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';

  String get kindLabel =>
      kind == ActivityLogKind.timeEdit ? 'Time card' : 'Leave';

  String get statusLabel {
    if (status.isEmpty) return status;
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  String get searchText => [
    kindLabel,
    status,
    companyName,
    subjectName,
    subjectEmail,
    actorName,
    summary,
    detail,
    workDate,
    leaveRange,
  ].join(' ').toLowerCase();
}
