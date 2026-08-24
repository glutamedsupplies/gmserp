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
  }) async {
    await _leaves.doc(requestId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<LeaveRequest> submit({
    required UserModel user,
    required CompanyModel company,
    required String reason,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
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
      'createdAt': FieldValue.serverTimestamp(),
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
