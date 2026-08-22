import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/password_hasher.dart';
import '../models/company_model.dart';
import '../models/staff_assignment.dart';

class CompanyRepository {
  CompanyRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection('companies');

  Future<List<CompanyModel>> listCompanies() async {
    final snapshot = await _companies.get();
    final companies = snapshot.docs
        .map((doc) => CompanyModel.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    companies.sort((a, b) => a.name.compareTo(b.name));
    return companies;
  }

  Future<void> createCompany({
    required String name,
    required String password,
    required String createdBy,
  }) async {
    await _companies.add({
      'name': name.trim(),
      'passwordHash': PasswordHasher.hash(password),
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCompany({
    required String id,
    required String name,
    String? newPassword,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (newPassword != null && newPassword.isNotEmpty) {
      data['passwordHash'] = PasswordHasher.hash(newPassword);
    }
    await _companies.doc(id).set(data, SetOptions(merge: true));
  }

  bool unlockCompany({
    required CompanyModel company,
    required String password,
  }) {
    return PasswordHasher.matches(
      plainText: password,
      hash: company.passwordHash,
    );
  }

  CollectionReference<Map<String, dynamic>> _staff(String companyId) =>
      _companies.doc(companyId).collection('staff');

  Future<List<StaffAssignment>> listStaff(String companyId) async {
    final snapshot = await _staff(companyId).get();
    return snapshot.docs
        .map(
          (doc) => StaffAssignment.fromFirestore(id: doc.id, data: doc.data()),
        )
        .toList();
  }

  Future<StaffAssignment?> getAssignment({
    required String companyId,
    required String userId,
  }) async {
    final snapshot = await _staff(companyId).doc(userId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return StaffAssignment.fromFirestore(
      id: snapshot.id,
      data: snapshot.data()!,
    );
  }

  Future<void> assignStaff({
    required String companyId,
    required StaffAssignment assignment,
  }) async {
    await _staff(companyId).doc(assignment.userId).set({
      ...assignment.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
