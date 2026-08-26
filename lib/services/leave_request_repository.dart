import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_model.dart';
import '../models/leave_request.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';

class LeaveRequestRepository {
  LeaveRequestRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'leaveRequests';

  CollectionReference<Map<String, dynamic>> get _leaves =>
      _firestore.collection(collectionName);

  Future<List<LeaveRequest>> listForUserCompany({
    required String userId,
    required String companyId,
  }) async {
    final snapshot = await _leaves
        .where('userId', isEqualTo: userId)
        .where('companyId', isEqualTo: companyId)
        .get();

    final leaves = snapshot.docs
        .map((doc) => LeaveRequest.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    leaves.sort((a, b) => b.startDate.compareTo(a.startDate));
    return leaves;
  }

  Future<List<LeaveRequest>> listByUserId(String userId) async {
    final snapshot = await _leaves.where('userId', isEqualTo: userId).get();
    final leaves = snapshot.docs
        .map((doc) => LeaveRequest.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    leaves.sort((a, b) {
      final byUpdated = (b.updatedAt ?? b.createdAt ?? DateTime(0))
          .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(0));
      if (byUpdated != 0) return byUpdated;
      return b.startDate.compareTo(a.startDate);
    });
    return leaves;
  }

  /// Pending or approved leave that already covers any day in [startDate]–[endDate].
  Future<LeaveRequest?> findBlockingLeave({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snapshot =
        await _leaves.where('userId', isEqualTo: userId).get();
    final docId = companyDocumentId?.trim() ?? '';
    final start = formatWorkDate(startDate);
    final end = formatWorkDate(endDate);

    for (final doc in snapshot.docs) {
      final leave = LeaveRequest.fromFirestore(id: doc.id, data: doc.data());
      if (!leave.isActiveLeave) continue;

      final matchesCompany = leave.companyId == companyId ||
          leave.companyDocumentId == companyId ||
          (docId.isNotEmpty &&
              (leave.companyId == docId || leave.companyDocumentId == docId));
      if (!matchesCompany) continue;

      // Ranges overlap when startA <= endB && startB <= endA.
      if (start.compareTo(leave.endDate) <= 0 &&
          leave.startDate.compareTo(end) <= 0) {
        return leave;
      }
    }
    return null;
  }

  Future<List<LeaveRequest>> listByCompanyId(String companyId) async {
    final snapshot =
        await _leaves.where('companyId', isEqualTo: companyId).get();

    final leaves = snapshot.docs
        .map((doc) => LeaveRequest.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    leaves.sort((a, b) => b.startDate.compareTo(a.startDate));
    return leaves;
  }

  Future<List<LeaveRequest>> listAll() async {
    final snapshot = await _leaves.get();
    final leaves = snapshot.docs
        .map((doc) => LeaveRequest.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
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
    await _leaves.doc(requestId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (reviewerId.isNotEmpty) 'reviewedById': reviewerId,
      if (reviewerName.isNotEmpty) 'reviewedByName': reviewerName,
      'reviewedAt': FieldValue.serverTimestamp(),
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
      // Client timestamp so Super Admin always sees when the request was taken.
      'requestedAt': now.toUtc().toIso8601String(),
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final doc = await _leaves.add(data);
    final snapshot = await doc.get();
    return LeaveRequest.fromFirestore(
      id: snapshot.id,
      data: snapshot.data() ?? data,
    );
  }
}
