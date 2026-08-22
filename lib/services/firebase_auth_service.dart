import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';
import '../models/user_role.dart';
import 'auth_service.dart';
import 'user_repository.dart';

/// Firebase Authentication + Cloud Firestore.
///
/// - Email/password → Firebase Auth (never stored in Firestore)
/// - Username, email, phone → Firestore `users/{uid}`
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    UserRepository? userRepository,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _users = userRepository ?? UserRepository();

  final FirebaseAuth _auth;
  final UserRepository _users;

  static const String _rememberKey = 'auth_remember_me';

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      await _setPersistence(rememberMe);

      User? firebaseUser;
      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        firebaseUser = credential.user;
      } on FirebaseAuthException catch (e) {
        firebaseUser = _auth.currentUser;
        if (firebaseUser == null ||
            (e.code != 'network-request-failed' &&
                e.code != 'too-many-requests' &&
                e.code != 'internal-error')) {
          return AuthResult.failure(_mapAuthError(e));
        }
      }

      if (firebaseUser == null) {
        return AuthResult.failure('Invalid email or password.');
      }

      try {
        await _ensureAuthToken(firebaseUser);
      } catch (_) {}

      final user = await _profileAfterAuth(
        firebaseUser: firebaseUser,
        fallbackEmail: email.trim().toLowerCase(),
        source: 'login',
      );
      await _saveRememberMe(rememberMe);

      return AuthResult.success(
        user: user,
        message: 'Login successful.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } on FirebaseException catch (e) {
      final signedIn = _auth.currentUser;
      if (signedIn != null) {
        final user = await _profileAfterAuth(
          firebaseUser: signedIn,
          fallbackEmail: email.trim().toLowerCase(),
          source: 'login',
        );
        await _saveRememberMe(rememberMe);
        return AuthResult.success(user: user, message: 'Login successful.');
      }
      return AuthResult.failure(_mapFirestoreError(e));
    } catch (error, stack) {
      debugPrint('Login failed: $error\n$stack');
      final signedIn = _auth.currentUser;
      if (signedIn != null) {
        final user = await _profileAfterAuth(
          firebaseUser: signedIn,
          fallbackEmail: email.trim().toLowerCase(),
          source: 'login',
        );
        await _saveRememberMe(rememberMe);
        return AuthResult.success(user: user, message: 'Login successful.');
      }
      return AuthResult.failure(
        'Unable to finish sign-in. Check your internet connection and try again.',
      );
    }
  }

  Future<UserModel> _profileAfterAuth({
    required User firebaseUser,
    required String fallbackEmail,
    required String source,
  }) async {
    UserModel? existing;
    try {
      existing = await _users.getUserById(firebaseUser.uid);
    } catch (error) {
      debugPrint('Could not load Firestore profile: $error');
    }

    final email = firebaseUser.email ?? fallbackEmail;
    final user = UserModel(
      id: firebaseUser.uid,
      username: existing?.username.isNotEmpty == true
          ? existing!.username
          : (firebaseUser.displayName ?? email.split('@').first),
      email: email,
      phoneNumber: existing?.phoneNumber ?? firebaseUser.phoneNumber ?? '',
      role: RolePolicy.resolve(email: email, existing: existing?.role),
    );

    try {
      await _users.saveProfile(user: user, source: source);
      return await _users.getUserById(firebaseUser.uid) ?? user;
    } catch (error) {
      debugPrint('Could not save Firestore profile: $error');
      return user;
    }
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();

      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return AuthResult.failure('Something went wrong. Please try again.');
      }

      await firebaseUser.updateDisplayName(username.trim());
      await _ensureAuthToken(firebaseUser);

      final user = UserModel(
        id: firebaseUser.uid,
        username: username.trim(),
        email: normalizedEmail,
        phoneNumber: phoneNumber.trim().replaceAll(' ', ''),
        role: RolePolicy.resolve(email: normalizedEmail),
        createdAt: DateTime.now().toUtc(),
      );

      await _users.saveProfile(user: user, source: 'register');

      await _auth.signOut();

      return AuthResult.success(
        user: user,
        message: 'Account successfully created.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } on FirebaseException catch (e) {
      return AuthResult.failure(_mapFirestoreError(e));
    } catch (_) {
      return AuthResult.failure('Unable to connect to the server.');
    }
  }

  @override
  Future<AuthResult> forgotPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return AuthResult.success(
        message: 'Password reset instructions have been sent to your email.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (_) {
      return AuthResult.failure('Unable to connect to the server.');
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, false);
  }

  @override
  Future<UserModel?> checkAuthentication() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool(_rememberKey) ?? false;
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) return null;

    if (!rememberMe) {
      await _auth.signOut();
      return null;
    }

    final profile = await _users.getUserById(firebaseUser.uid);
    if (profile != null) return profile;

    return UserModel(
      id: firebaseUser.uid,
      username: firebaseUser.displayName ??
          firebaseUser.email?.split('@').first ??
          'user',
      email: firebaseUser.email ?? '',
      phoneNumber: firebaseUser.phoneNumber ?? '',
    );
  }

  Future<void> _ensureAuthToken(User firebaseUser) async {
    await firebaseUser.reload();
    await firebaseUser.getIdToken(true);
  }

  Future<void> _setPersistence(bool rememberMe) async {
    if (!kIsWeb) return;
    await _auth.setPersistence(
      rememberMe ? Persistence.LOCAL : Persistence.SESSION,
    );
  }

  Future<void> _saveRememberMe(bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberKey, rememberMe);
  }

  String _mapFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Could not save account data. Enable Firestore and publish '
            'the project firestore.rules so signed-in users can write users/{uid}.';
      case 'unavailable':
        return 'Unable to connect to the server.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Something went wrong. Please try again.';
    }
  }

  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'requires-recent-login':
        return 'Enter your current password to update email or password.';
      case 'email-already-in-use':
        return 'Email address is already registered.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'A network error occurred during sign-in. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled in Firebase.';
      case 'configuration-not-found':
      case 'internal-error':
        final detail = (e.message ?? '').toLowerCase();
        if (detail.contains('configuration_not_found') ||
            e.code == 'configuration-not-found') {
          return 'Firebase Auth is not fully set up for this Android app. '
              'In Firebase Console enable Authentication → Email/Password, '
              'then Project settings → Your apps → Android (gmserp.android) '
              'and add the debug SHA-1 fingerprint.';
        }
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Something went wrong. Please try again.';
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Something went wrong. Please try again.';
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
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null || firebaseUser.email == null) {
      return AuthResult.failure('Please sign in again.');
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: firebaseUser.email!,
        password: currentPassword,
      );
      await firebaseUser.reauthenticateWithCredential(credential);

      final nextUsername = username.trim();
      final nextEmail = email.trim().toLowerCase();
      final nextPhone = phoneNumber.trim().replaceAll(' ', '');

      await firebaseUser.updateDisplayName(nextUsername);

      if (newPassword != null && newPassword.isNotEmpty) {
        await firebaseUser.updatePassword(newPassword);
      }

      var savedEmail = firebaseUser.email ?? nextEmail;
      var emailPendingVerification = false;
      if (nextEmail != savedEmail.toLowerCase()) {
        await firebaseUser.verifyBeforeUpdateEmail(nextEmail);
        emailPendingVerification = true;
        savedEmail = nextEmail;
      }

      final existing = await _users.getUserById(firebaseUser.uid);
      final user = UserModel(
        id: firebaseUser.uid,
        username: nextUsername,
        email: savedEmail,
        phoneNumber: nextPhone,
        role: RolePolicy.resolve(
          email: savedEmail,
          existing: existing?.role,
        ),
      );

      await _users.saveProfile(user: user, source: 'profile');
      final saved = await _users.getUserById(firebaseUser.uid);

      return AuthResult.success(
        user: saved ?? user,
        message: emailPendingVerification
            ? 'Profile saved. Confirm the new email from the inbox to finish the Gmail change.'
            : 'Profile updated.',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } on FirebaseException catch (e) {
      return AuthResult.failure(_mapFirestoreError(e));
    } catch (_) {
      return AuthResult.failure('Unable to connect to the server.');
    }
  }
}
