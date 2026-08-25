import '../models/time_entry.dart';

/// Admin-submitted request to create/update an employee time in / time out.
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
    this.createdAt,
    this.updatedAt,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

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
      createdAt: createdAt,
      updatedAt: updatedAt,
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
      proposedTimeIn: _parseDate(data['proposedTimeIn']) ?? DateTime.now(),
      proposedTimeOut: _parseDate(data['proposedTimeOut']),
      currentTimeIn: _parseDate(data['currentTimeIn']),
      currentTimeOut: _parseDate(data['currentTimeOut']),
      currentTimeInText: data['currentTimeInLabel']?.toString() ??
          data['currentTimeInText']?.toString() ??
          '',
      currentTimeOutText: data['currentTimeOutLabel']?.toString() ??
          data['currentTimeOutText']?.toString() ??
          '',
      existingEntryId: data['existingEntryId']?.toString(),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
