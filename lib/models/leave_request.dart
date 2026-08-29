import '../core/utils/firebase_data.dart';
import 'time_entry.dart';

class LeaveRequest {
  final String id;
  final String userId;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String username;
  final String userEmail;
  final String reason;
  final String startDate;
  final String endDate;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String reviewedById;
  final String reviewedByName;

  const LeaveRequest({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.username,
    required this.userEmail,
    required this.reason,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.reviewedById = '',
    this.reviewedByName = '',
  });

  bool get isActiveLeave =>
      status == 'approved' || status == 'pending';

  bool get isApprovedLeave => status == 'approved';

  bool coversWorkDate(String workDate) {
    return workDate.compareTo(startDate) >= 0 &&
        workDate.compareTo(endDate) <= 0;
  }

  factory LeaveRequest.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return LeaveRequest(
      id: id,
      userId: data['userId']?.toString() ?? '',
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      userEmail: data['userEmail']?.toString() ?? '',
      reason: data['reason']?.toString() ?? '',
      startDate: data['startDate']?.toString() ?? '',
      endDate: data['endDate']?.toString() ?? '',
      status: data['status']?.toString() ?? 'pending',
      createdAt: parseFirebaseDate(data['createdAt']) ??
          parseFirebaseDate(data['requestedAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
      reviewedById: data['reviewedById']?.toString() ?? '',
      reviewedByName: data['reviewedByName']?.toString() ?? '',
    );
  }
}

bool hasLeaveOnDate({
  required List<LeaveRequest> leaves,
  required String workDate,
}) {
  return leaves.any(
    (leave) => leave.isActiveLeave && leave.coversWorkDate(workDate),
  );
}

bool hasApprovedLeaveOnDate({
  required List<LeaveRequest> leaves,
  required String workDate,
}) {
  return leaves.any(
    (leave) => leave.isApprovedLeave && leave.coversWorkDate(workDate),
  );
}

String formatLeaveDate(DateTime date) => formatWorkDate(date);
