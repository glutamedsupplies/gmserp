import '../core/utils/firebase_data.dart';
import '../models/user_model.dart';
import '../models/user_role.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class UserRepository {
  UserRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.users;

  String _userPath(String userId) => '${RtdbPaths.users}/$userId';

  Future<void> saveProfile({
    required UserModel user,
    required String source,
  }) async {
    final path = _userPath(user.id);
    final existing = await _rtdb.getMap(path);
    final existingRole = existing != null
        ? UserRole.fromStorage(existing['role'] as String?)
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
      'updatedAt': serverTimestamp(),
      'lastSource': source,
    };

    if (user.photoUrl.trim().isNotEmpty) {
      data['photoUrl'] = user.photoUrl.trim();
    }

    if (source == 'login') {
      data['lastLoginAt'] = serverTimestamp();
      data['lastLoginEmail'] = user.email;
    }

    if (source == 'register') {
      data['registeredAt'] = serverTimestamp();
    }

    if (existing == null) {
      data['createdAt'] = serverTimestamp();
    }

    await _rtdb.merge(path, data);
  }

  Future<void> updatePhotoUrl({
    required String userId,
    required String? photoUrl,
  }) async {
    final trimmed = photoUrl?.trim() ?? '';
    await _rtdb.merge(_userPath(userId), {
      'photoUrl': trimmed,
      'updatedAt': serverTimestamp(),
    });
  }

  Future<UserModel?> getUserById(String uid) async {
    final data = await _rtdb.getMap(_userPath(uid));
    if (data == null) return null;
    final user = UserModel.fromFirestore(id: uid, data: data);
    if (RolePolicy.isSuperAdminEmail(user.email) &&
        user.role != UserRole.superAdmin) {
      final promoted = user.copyWith(role: UserRole.superAdmin);
      await saveProfile(user: promoted, source: 'promote');
      return promoted;
    }
    return user;
  }

  Future<List<UserModel>> listUsers() async {
    final children = await _rtdb.getChildren(RtdbPaths.users);
    final users = children.entries
        .map((entry) => UserModel.fromFirestore(id: entry.key, data: entry.value))
        .toList();
    users.sort((a, b) => a.username.compareTo(b.username));
    return users;
  }

  Future<void> updateUserRole({
    required String userId,
    required UserRole role,
  }) async {
    await _rtdb.merge(_userPath(userId), {
      'role': role.storageValue,
      'updatedAt': serverTimestamp(),
    });
  }
}
