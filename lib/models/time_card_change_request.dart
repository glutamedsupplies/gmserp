import '../core/utils/firebase_data.dart';
import '../models/time_entry.dart';

/// Admin- or employee-submitted request to create/update time in / time out.
class TimeCardChangeRequest {
  const TimeCardChangeRequest({
    required this.id,
    required this.status,
    required this.requesterId,
    required this.requesterName,
    required this.requesterEmail,
    required this.employeeId,
    required this.employeeName,
    required this.employeeEmail,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.workDate,
    required this.proposedTimeIn,
    this.proposedTimeOut,
    this.currentTimeIn,
    this.currentTimeOut,
    this.currentTimeInText = '',
    this.currentTimeOutText = '',
    this.existingEntryId,
    this.note = '',
    this.createdAt,
    this.updatedAt,
    this.reviewedById = '',
    this.reviewedByName = '',
    this.source = '',
  });

  final String id;
  final String status;
  final String requesterId;
  final String requesterName;
  final String requesterEmail;
  final String employeeId;
  final String employeeName;
  final String employeeEmail;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String workDate;
  final DateTime proposedTimeIn;
  final DateTime? proposedTimeOut;
  final DateTime? currentTimeIn;
  final DateTime? currentTimeOut;
  final String currentTimeInText;
  final String currentTimeOutText;
  final String? existingEntryId;
  /// Reason / note from the requester (required for employee self-requests).
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String reviewedById;
  final String reviewedByName;

  /// `directEdit` when Super Admin saves time in/out without a pending request.
  final String source;

  bool get isDirectEdit => source == 'directEdit';

  bool get isPending => status.toLowerCase() == 'pending';

  bool get hasPriorRecord =>
      currentTimeIn != null ||
      (currentTimeInText.isNotEmpty &&
          currentTimeInText != '—' &&
          currentTimeInText != '-' &&
          currentTimeInText.toLowerCase() != 'no prior record');

  String get proposedTimeInLabel => formatClockTime(proposedTimeIn);

  String get proposedTimeOutLabel =>
      proposedTimeOut == null ? 'Open' : formatClockTime(proposedTimeOut!);

  String get currentTimeInLabel {
    if (currentTimeInText.trim().isNotEmpty) return currentTimeInText.trim();
    if (currentTimeIn != null) return formatClockTime(currentTimeIn!);
    return '—';
  }

  String get currentTimeOutLabel {
    if (currentTimeOutText.trim().isNotEmpty) return currentTimeOutText.trim();
    if (currentTimeOut != null) return formatClockTime(currentTimeOut!);
    if (hasPriorRecord) return 'Open';
    return '—';
  }

  TimeCardChangeRequest copyWith({
    DateTime? currentTimeIn,
    DateTime? currentTimeOut,
    String? currentTimeInText,
    String? currentTimeOutText,
    String? note,
    String? reviewedById,
    String? reviewedByName,
    String? source,
  }) {
    return TimeCardChangeRequest(
      id: id,
      status: status,
      requesterId: requesterId,
      requesterName: requesterName,
      requesterEmail: requesterEmail,
      employeeId: employeeId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
      companyName: companyName,
      workDate: workDate,
      proposedTimeIn: proposedTimeIn,
      proposedTimeOut: proposedTimeOut,
      currentTimeIn: currentTimeIn ?? this.currentTimeIn,
      currentTimeOut: currentTimeOut ?? this.currentTimeOut,
      currentTimeInText: currentTimeInText ?? this.currentTimeInText,
      currentTimeOutText: currentTimeOutText ?? this.currentTimeOutText,
      existingEntryId: existingEntryId,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewedById: reviewedById ?? this.reviewedById,
      reviewedByName: reviewedByName ?? this.reviewedByName,
      source: source ?? this.source,
    );
  }

  factory TimeCardChangeRequest.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return TimeCardChangeRequest(
      id: id,
      status: data['status']?.toString() ?? 'pending',
      requesterId: data['requesterId']?.toString() ?? '',
      requesterName: data['requesterName']?.toString() ?? '',
      requesterEmail: data['requesterEmail']?.toString() ?? '',
      employeeId: data['employeeId']?.toString() ?? '',
      employeeName: data['employeeName']?.toString() ?? '',
      employeeEmail: data['employeeEmail']?.toString() ?? '',
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      workDate: data['workDate']?.toString() ?? '',
      proposedTimeIn: parseFirebaseDate(data['proposedTimeIn']) ?? DateTime.now(),
      proposedTimeOut: parseFirebaseDate(data['proposedTimeOut']),
      currentTimeIn: parseFirebaseDate(data['currentTimeIn']),
      currentTimeOut: parseFirebaseDate(data['currentTimeOut']),
      currentTimeInText: data['currentTimeInLabel']?.toString() ??
          data['currentTimeInText']?.toString() ??
          '',
      currentTimeOutText: data['currentTimeOutLabel']?.toString() ??
          data['currentTimeOutText']?.toString() ??
          '',
      existingEntryId: data['existingEntryId']?.toString(),
      note: data['note']?.toString() ?? '',
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
      reviewedById: data['reviewedById']?.toString() ?? '',
      reviewedByName: data['reviewedByName']?.toString() ?? '',
      source: data['source']?.toString() ?? '',
    );
  }
}
