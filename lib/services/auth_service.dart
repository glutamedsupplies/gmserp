import '../models/user_model.dart';

/// Result wrapper for authentication operations.
class AuthResult {
  final bool success;
  final UserModel? user;
  final String? message;

  const AuthResult({
    required this.success,
    this.user,
    this.message,
  });

  factory AuthResult.success({UserModel? user, String? message}) {
    return AuthResult(success: true, user: user, message: message);
  }

  factory AuthResult.failure(String message) {
    return AuthResult(success: false, message: message);
  }
}

/// Abstraction for authentication backends.
///
/// Current app uses [FirebaseAuthService] (Firebase Auth + Firestore).
/// Swap implementations without changing UI or provider code.
abstract class AuthService {
  Future<AuthResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
  });

  Future<AuthResult> register({
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  });

  Future<AuthResult> forgotPassword({required String email});

  Future<void> logout();

  Future<UserModel?> checkAuthentication();

  Future<AuthResult> updateAccount({
    required String username,
    required String email,
    required String phoneNumber,
    required String currentPassword,
    String? newPassword,
  });
}
