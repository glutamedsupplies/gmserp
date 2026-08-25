import 'time_entry.dart';

/// Employee-submitted clock in or clock out awaiting admin/super-admin approval.
class ClockRequest {
  const ClockRequest({
    required this.id,
    required this.type,
    required this.status,
    required this.userId,
    required this.username,
    required this.userEmail,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.workDate,
    required this.requestedAt,
    this.entryId,
    this.createdAt,
    this.updatedAt,
  });

  static const typeClockIn = 'clockIn';
  static const typeClockOut = 'clockOut';

  final String id;
  /// [typeClockIn] or [typeClockOut]
  final String type;
  final String status;
  final String userId;
  final String username;
  final String userEmail;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String workDate;
  /// Exact time the employee pressed time in / time out.
  final DateTime requestedAt;
  /// Open entry to close when [type] is [typeClockOut].
  final String? entryId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isClockIn => type == typeClockIn;
  bool get isClockOut => type == typeClockOut;

  String get typeLabel => isClockIn ? 'Time in' : 'Time out';

  String get requestedAtLabel => formatClockTime(requestedAt);

  factory ClockRequest.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return ClockRequest(
      id: id,
      type: data['type']?.toString() ?? typeClockIn,
      status: data['status']?.toString() ?? 'pending',
      userId: data['userId']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      userEmail: data['userEmail']?.toString() ?? '',
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      workDate: data['workDate']?.toString() ?? '',
      requestedAt: _parseDate(data['requestedAt']) ?? DateTime.now(),
      entryId: data['entryId']?.toString(),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return DateTime.tryParse(value.toString());
    }
  }
}
