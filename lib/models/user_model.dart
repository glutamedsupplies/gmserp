import '../core/utils/firebase_data.dart';
import 'user_role.dart';

class UserModel {
  final String id;
  final String username;
  final String email;
  final String? _phoneNumber;
  final UserRole role;
  final String photoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required String this._phoneNumber,
    this.role = UserRole.user,
    this.photoUrl = '',
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

  bool get hasPhotoUrl => photoUrl.trim().isNotEmpty;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: parseFirebaseString(json['id']),
      username: parseFirebaseString(json['username']),
      email: parseFirebaseString(json['email']),
      phoneNumber: parseFirebaseString(json['phoneNumber']),
      role: UserRole.fromStorage(parseFirebaseString(json['role'])),
      photoUrl: parseFirebaseString(json['photoUrl']),
      createdAt: parseFirebaseDate(json['createdAt']),
      updatedAt: parseFirebaseDate(json['updatedAt']),
    );
  }

  factory UserModel.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return UserModel(
      id: id,
      username: parseFirebaseString(data['username']),
      email: parseFirebaseString(data['email']),
      phoneNumber: parseFirebaseString(data['phoneNumber']),
      role: UserRole.fromStorage(parseFirebaseString(data['role'])),
      photoUrl: parseFirebaseString(data['photoUrl']),
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role.storageValue,
      'photoUrl': photoUrl,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? email,
    String? phoneNumber,
    UserRole? role,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
