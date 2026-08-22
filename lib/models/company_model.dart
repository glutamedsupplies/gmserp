class CompanyModel {
  final String id;
  final String name;
  final String passwordHash;
  final String createdBy;

  const CompanyModel({
    required this.id,
    required this.name,
    required this.passwordHash,
    required this.createdBy,
  });

  factory CompanyModel.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return CompanyModel(
      id: id,
      name: data['name'] as String? ?? '',
      passwordHash: data['passwordHash'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
    );
  }
}
