import '../core/utils/firebase_data.dart';

class CompanyModel {
  final String id;
  final String? documentId;
  final String name;
  final String passwordHash;
  final String staffPasswordHash;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanyModel({
    required this.id,
    this.documentId,
    required this.name,
    required this.passwordHash,
    this.staffPasswordHash = '',
    required this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  String get companyId => id;

  /// Firestore document id. Falls back to [id] when missing (hot reload / older data).
  String get firestoreId {
    try {
      final doc = documentId;
      if (doc != null && doc.isNotEmpty) return doc;
    } catch (_) {}
    return id;
  }

  DateTime? get lastUpdatedAt => updatedAt ?? createdAt;

  factory CompanyModel.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final storedId = _stringField(data['companyId']);
    return CompanyModel(
      id: storedId.isNotEmpty ? storedId : id,
      documentId: id,
      name: _stringField(data['name']),
      passwordHash: _stringField(data['passwordHash']),
      staffPasswordHash: _stringField(data['staffPasswordHash']),
      createdBy: _stringField(data['createdBy']),
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
    );
  }

  static String _stringField(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }
}
