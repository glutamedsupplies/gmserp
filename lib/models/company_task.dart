import '../core/utils/firebase_data.dart';
import 'company_model.dart';

class CompanyTaskListing {
  final CompanyModel company;
  final CompanyTask task;

  const CompanyTaskListing({
    required this.company,
    required this.task,
  });
}

class CompanyTask {
  final String id;
  final String title;
  final String description;
  final String? _roleId;
  final String? _roleName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get roleId => _roleId ?? '';
  String get roleName => _roleName ?? '';

  const CompanyTask({
    required this.id,
    required this.title,
    this.description = '',
    String this._roleId = '',
    String roleName = '',
    this.createdAt,
    this.updatedAt,
  }) : _roleName = roleName; // ignore: prefer_initializing_formals

  factory CompanyTask.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return CompanyTask(
      id: id,
      title: data['title']?.toString().trim() ?? '',
      description: data['description']?.toString().trim() ?? '',
      roleId: data['roleId']?.toString().trim() ?? '',
      roleName: data['roleName']?.toString().trim() ?? '',
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
    );
  }

  CompanyTask copyWith({
    String? title,
    String? description,
    String? roleId,
    String? roleName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title.trim(),
      'description': description.trim(),
      'roleId': roleId.trim(),
      'roleName': roleName.trim(),
    };
  }
}
