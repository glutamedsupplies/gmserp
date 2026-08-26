import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';

class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'users';

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(collectionName);

  Future<void> saveProfile({
    required UserModel user,
    required String source,
  }) async {
    final ref = _users.doc(user.id);
    final existing = await ref.get();
    final existingRole = existing.exists
        ? UserRole.fromStorage(existing.data()?['role'] as String?)
        : null;
    final role = RolePolicy.resolve(
      email: user.email,
      existing: existingRole ?? user.role,
    );

    final data = <String, dynamic>{
      'id': user.id,
      'username': user.username,
      'email': user.email,
      'phoneNumber': user.phoneNumber,
      'role': role.storageValue,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSource': source,
    };

    // Preserve existing photoUrl on merge saves unless this write sets one.
    if (user.photoUrl.trim().isNotEmpty) {
      data['photoUrl'] = user.photoUrl.trim();
    }

    if (source == 'login') {
      data['lastLoginAt'] = FieldValue.serverTimestamp();
      data['lastLoginEmail'] = user.email;
    }

    if (source == 'register') {
      data['registeredAt'] = FieldValue.serverTimestamp();
    }

    if (!existing.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> updatePhotoUrl({
    required String userId,
    required String? photoUrl,
  }) async {
    final trimmed = photoUrl?.trim() ?? '';
    await _users.doc(userId).set(
      {
        'photoUrl': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<UserModel?> getUserById(String uid) async {
    final snapshot = await _users.doc(uid).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    final user = UserModel.fromFirestore(id: snapshot.id, data: snapshot.data()!);
    if (RolePolicy.isSuperAdminEmail(user.email) &&
        user.role != UserRole.superAdmin) {
      final promoted = user.copyWith(role: UserRole.superAdmin);
      await saveProfile(user: promoted, source: 'promote');
      return promoted;
    }
    return user;
  }

  Future<List<UserModel>> listUsers() async {
    final snapshot = await _users.get();
    final users = snapshot.docs
        .map((doc) => UserModel.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    users.sort((a, b) => a.username.compareTo(b.username));
    return users;
  }

  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) async {
    await _users.doc(userId).set(
      {
        'role': role.storageValue,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
