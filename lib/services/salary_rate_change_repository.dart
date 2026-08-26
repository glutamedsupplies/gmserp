import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/salary_rate_change.dart';

class SalaryRateChangeRepository {
  SalaryRateChangeRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'salaryRateChanges';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(collectionName);

  Future<SalaryRateChange> create({
    required String companyId,
    required String companyDocumentId,
    required String companyName,
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String actorId,
    required String actorName,
    required double previousRate,
    required double newRate,
    required List<String> recipientIds,
  }) async {
    final recipients = recipientIds.toSet().where((id) => id.isNotEmpty).toList()
      ..sort();
    final ref = _collection.doc();
    final change = SalaryRateChange(
      id: ref.id,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
      companyName: companyName,
      employeeId: employeeId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      actorId: actorId,
      actorName: actorName,
      previousRate: previousRate,
      newRate: newRate,
      recipientIds: recipients,
      createdAt: DateTime.now(),
    );
    await ref.set(change.toFirestore());
    return change;
  }

  Future<List<SalaryRateChange>> listAll() async {
    final snapshot = await _collection.get();
    final items = snapshot.docs
        .map(
          (doc) => SalaryRateChange.fromFirestore(id: doc.id, data: doc.data()),
        )
        .toList();
    items.sort(
      (a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  Future<List<SalaryRateChange>> listForRecipient(String userId) async {
    final snapshot = await _collection
        .where('recipientIds', arrayContains: userId)
        .get();
    final items = snapshot.docs
        .map(
          (doc) => SalaryRateChange.fromFirestore(id: doc.id, data: doc.data()),
        )
        .toList();
    items.sort(
      (a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }
}
