import '../core/utils/firebase_data.dart';
import '../models/company_model.dart';
import '../models/leave_request.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class LeaveRequestRepository {
  LeaveRequestRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.leaveRequests;

  String _requestPath(String requestId) =>
      '${RtdbPaths.leaveRequests}/$requestId';

  Future<List<LeaveRequest>> _loadAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.leaveRequests);
    return children.entries
        .map(
          (entry) =>
              LeaveRequest.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
  }

  Future<List<LeaveRequest>> listForUserCompany({
    required String userId,
    required String companyId,
  }) async {
    final leaves = (await _loadAll())
        .where(
          (leave) => leave.userId == userId && leave.companyId == companyId,
        )
        .toList();
    leaves.sort((a, b) => b.startDate.compareTo(a.startDate));
    return leaves;
  }

  Future<List<LeaveRequest>> listByUserId(String userId) async {
    final leaves =
        (await _loadAll()).where((leave) => leave.userId == userId).toList();
    leaves.sort((a, b) {
      final byUpdated = (b.updatedAt ?? b.createdAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0));
      if (byUpdated != 0) return byUpdated;
      return b.startDate.compareTo(a.startDate);
    });
    return leaves;
  }

  Future<LeaveRequest?> findBlockingLeave({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final docId = companyDocumentId?.trim() ?? '';
    final start = formatWorkDate(startDate);
    final end = formatWorkDate(endDate);

    for (final leave in await _loadAll()) {
      if (leave.userId != userId || !leave.isActiveLeave) continue;

      final matchesCompany = leave.companyId == companyId ||
          leave.companyDocumentId == companyId ||
          (docId.isNotEmpty &&
              (leave.companyId == docId || leave.companyDocumentId == docId));
      if (!matchesCompany) continue;

      if (start.compareTo(leave.endDate) <= 0 &&
          leave.startDate.compareTo(end) <= 0) {
        return leave;
      }
    }
    return null;
  }

  Future<List<LeaveRequest>> listByCompanyId(
    String companyId, {
    String? companyDocumentId,
  }) async {
    final leaves = (await _loadAll())
        .where(
          (leave) => matchesCompanyRef(
            storedCompanyId: leave.companyId,
            storedDocumentId: leave.companyDocumentId,
            companyId: companyId,
            companyDocumentId: companyDocumentId,
          ),
        )
        .toList();
    leaves.sort((a, b) => b.startDate.compareTo(a.startDate));
    return leaves;
  }

  Future<List<LeaveRequest>> listAll() async {
    final leaves = await _loadAll();
    leaves.sort((a, b) {
      final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byCreated != 0) return byCreated;
      return b.startDate.compareTo(a.startDate);
    });
    return leaves;
  }

  Future<void> updateStatus({
    required String requestId,
    required String status,
    String reviewerId = '',
    String reviewerName = '',
  }) async {
    await _rtdb.merge(_requestPath(requestId), {
      'status': status,
      'updatedAt': serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': serverTimestamp(),
    });
  }

  Future<LeaveRequest> submit({
    required UserModel user,
    required CompanyModel company,
    required String reason,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final blocking = await findBlockingLeave(
      userId: user.id,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      startDate: startDate,
      endDate: endDate,
    );
    if (blocking != null) {
      final range = blocking.startDate == blocking.endDate
          ? blocking.startDate
          : '${blocking.startDate} → ${blocking.endDate}';
      throw StateError(
        'You already have a ${blocking.status} leave request covering $range. '
        'Each date can only be requested once.',
      );
    }

    final now = DateTime.now();
    final id = _rtdb.newKey(RtdbPaths.leaveRequests);
    final data = <String, dynamic>{
      'userId': user.id,
      'userEmail': user.email,
      'username': user.username,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'reason': reason.trim(),
      'startDate': formatWorkDate(startDate),
      'endDate': formatWorkDate(endDate),
      'status': 'pending',
      'requestedAt': now.toUtc().toIso8601String(),
      'createdAt': writeFirebaseDate(now),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_requestPath(id), data);
    return LeaveRequest.fromFirestore(id: id, data: data);
  }
}
