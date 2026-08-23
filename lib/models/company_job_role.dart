import 'company_model.dart';

class CompanyRoleListing {
  final CompanyModel company;
  final CompanyJobRole role;

  const CompanyRoleListing({
    required this.company,
    required this.role,
  });
}

class CompanyJobRole {
  final String id;
  final String name;
  final String description;

  const CompanyJobRole({
    required this.id,
    required this.name,
    this.description = '',
  });

  factory CompanyJobRole.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return CompanyJobRole(
      id: id,
      name: data['name']?.toString().trim() ?? '',
      description: data['description']?.toString().trim() ?? '',
    );
  }

  CompanyJobRole copyWith({
    String? name,
    String? description,
  }) {
    return CompanyJobRole(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name.trim(),
      'description': description.trim(),
    };
  }
}
