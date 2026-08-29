import '../core/utils/firebase_data.dart';
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
    this.relatedClockInId,
    this.note = '',
    this.createdAt,
    this.updatedAt,
    this.reviewedById = '',
    this.reviewedByName = '',
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
  /// Open entry to close when [type] is [typeClockOut] (set after time-in approval).
  final String? entryId;
  /// Pending time-in request this time-out belongs to (when time-in is not approved yet).
  final String? relatedClockInId;
  /// Employee note required with the request.
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String reviewedById;
  final String reviewedByName;

  bool get isPending => status.toLowerCase() == 'pending';

  /// Pending plus legacy/expired rows that Super Admin can still review.
  bool get awaitsReview {
    final normalized = status.toLowerCase();
    return normalized == 'pending' || normalized == 'expired';
  }

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
      requestedAt: parseFirebaseDate(data['requestedAt']) ?? DateTime.now(),
      entryId: data['entryId']?.toString(),
      relatedClockInId: data['relatedClockInId']?.toString(),
      note: data['note']?.toString() ?? '',
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
      reviewedById: data['reviewedById']?.toString() ?? '',
      reviewedByName: data['reviewedByName']?.toString() ?? '',
    );
  }
}
