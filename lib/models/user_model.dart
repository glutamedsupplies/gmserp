import 'user_role.dart';

class UserModel {
  final String id;
  final String username;
  final String email;
  final String? _phoneNumber;
  final UserRole role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required String this._phoneNumber,
    this.role = UserRole.user,
    this.createdAt,
    this.updatedAt,
  });

  String get phoneNumber {
    try {
      return _phoneNumber ?? '';
    } catch (_) {
      return '';
    }
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      role: UserRole.fromStorage(json['role'] as String?),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  factory UserModel.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return UserModel(
      id: id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phoneNumber: data['phoneNumber'] as String? ?? '',
      role: UserRole.fromStorage(data['role'] as String?),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role.storageValue,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? email,
    String? phoneNumber,
    UserRole? role,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
