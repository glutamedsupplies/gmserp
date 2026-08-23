import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'auth_service.dart';

/// Local mock authentication for development.
///
/// Replace this class with an API-backed implementation when connecting
/// to REST, Firebase, Supabase, Laravel, or Node.js. Passwords are never
/// persisted in plain text in the user model or shared preferences session.
class MockAuthService implements AuthService {
  static const String _sessionKey = 'auth_session_user';
  static const String _usersKey = 'auth_registered_users';
  static const String _rememberKey = 'auth_remember_me';

  // In-memory store mirrors persisted users for faster lookups during a session.
  final Map<String, _StoredCredentials> _credentials = {};
  bool _loaded = false;

  MockAuthService() {
    _seedDemoAccount();
  }

  void _seedDemoAccount() {
    _credentials['demo@gmail.com'] = _StoredCredentials(
      user: const UserModel(
        id: 'demo-001',
        username: 'demo',
        email: 'demo@gmail.com',
        phoneNumber: '09171234567',
      ),
      // Stored hashed-style token only — never log or expose raw passwords.
      passwordHash: _hashPassword('Demo@1234'),
    );
  }

  /// Simple non-cryptographic obfuscation for local mock storage only.
  /// Real backends must use proper hashing (bcrypt/argon2) server-side over HTTPS.
  String _hashPassword(String password) {
    return base64Encode(utf8.encode('gms:$password'));
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final email = (map['email'] as String).toLowerCase();
        _credentials[email] = _StoredCredentials(
          user: UserModel.fromJson(map['user'] as Map<String, dynamic>),
          passwordHash: map['passwordHash'] as String,
        );
      }
    } catch (_) {
      // Corrupt local cache — ignore and continue with seed data.
    }
  }

  Future<void> _persistUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _credentials.entries.map((entry) {
      return {
        'email': entry.key,
        'passwordHash': entry.value.passwordHash,
        'user': entry.value.user.toJson(),
      };
    }).toList();
    await prefs.setString(_usersKey, jsonEncode(list));
  }

  Future<void> _saveSession(UserModel user, {required bool rememberMe}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
    if (rememberMe) {
      await prefs.setString(_sessionKey, jsonEncode(user.toJson()));
    } else {
      await prefs.remove(_sessionKey);
    }
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.setBool(_rememberKey, false);
  }

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    await Future<void>.delayed(AppConstants.mockNetworkDelay);
    await _ensureLoaded();

    final key = email.trim().toLowerCase();
    final stored = _credentials[key];

    if (stored == null || stored.passwordHash != _hashPassword(password)) {
      return AuthResult.failure('Invalid email or password.');
    }

    await _saveSession(stored.user, rememberMe: true);
    return AuthResult.success(
      user: stored.user,
      message: 'Login successful.',
    );
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  }) async {
    await Future<void>.delayed(AppConstants.mockNetworkDelay);
    await _ensureLoaded();

    final key = email.trim().toLowerCase();
    if (_credentials.containsKey(key)) {
      return AuthResult.failure('Email address is already registered.');
    }

    final user = UserModel(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      username: username.trim(),
      email: key,
      phoneNumber: phoneNumber.trim().replaceAll(' ', ''),
    );

    _credentials[key] = _StoredCredentials(
      user: user,
      passwordHash: _hashPassword(password),
    );
    await _persistUsers();

    return AuthResult.success(
      user: user,
      message: 'Account successfully created.',
    );
  }

  @override
  Future<AuthResult> forgotPassword({required String email}) async {
    await Future<void>.delayed(AppConstants.mockNetworkDelay);
    await _ensureLoaded();

    final key = email.trim().toLowerCase();
    if (!_credentials.containsKey(key)) {
      // Avoid revealing whether an account exists in production;
      // for mock UX we still return a clear message.
      return AuthResult.failure('No account found with this email address.');
    }

    return AuthResult.success(
      message: 'Password reset instructions have been sent to your email.',
    );
  }

  @override
  Future<void> logout() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _clearSession();
  }

  @override
  Future<UserModel?> checkAuthentication() async {
    await _ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await _clearSession();
      return null;
    }
  }

  @override
  Future<AuthResult> updateAccount({
    required String username,
    required String email,
    required String phoneNumber,
    required String currentPassword,
    String? newPassword,
  }) async {
    await Future<void>.delayed(AppConstants.mockNetworkDelay);
    await _ensureLoaded();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return AuthResult.failure('Please sign in again.');
    }

    UserModel current;
    try {
      current = UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AuthResult.failure('Please sign in again.');
    }

    final oldKey = current.email.toLowerCase();
    final stored = _credentials[oldKey];
    if (stored == null || stored.passwordHash != _hashPassword(currentPassword)) {
      return AuthResult.failure('Invalid email or password.');
    }

    final nextEmail = email.trim().toLowerCase();
    if (nextEmail != oldKey && _credentials.containsKey(nextEmail)) {
      return AuthResult.failure('Email address is already registered.');
    }

    final updated = current.copyWith(
      username: username.trim(),
      email: nextEmail,
      phoneNumber: phoneNumber.trim().replaceAll(' ', ''),
    );

    _credentials.remove(oldKey);
    _credentials[nextEmail] = _StoredCredentials(
      user: updated,
      passwordHash: newPassword != null && newPassword.isNotEmpty
          ? _hashPassword(newPassword)
          : stored.passwordHash,
    );
    await _persistUsers();
    final remember = prefs.getBool(_rememberKey) ?? false;
    await _saveSession(updated, rememberMe: remember);

    return AuthResult.success(user: updated, message: 'Profile updated.');
  }
}

class _StoredCredentials {
  final UserModel user;
  final String passwordHash;

  const _StoredCredentials({
    required this.user,
    required this.passwordHash,
  });
}
