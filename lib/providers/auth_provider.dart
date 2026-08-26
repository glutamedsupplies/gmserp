import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/avatar_cloud_store.dart';
import '../services/local_avatar_factory.dart';
import '../services/local_avatar_store.dart';
import '../services/notification_service.dart';
import '../services/user_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthService authService,
    AvatarCloudStore? avatarCloud,
    UserRepository? users,
  })  : _authService = authService, // ignore: prefer_initializing_formals
        _avatars = createLocalAvatarStore(),
        _avatarCloud = avatarCloud ?? AvatarCloudStore(),
        _users = users ?? UserRepository();

  final AuthService _authService;
  final LocalAvatarStore _avatars;
  final AvatarCloudStore _avatarCloud;
  final UserRepository _users;

  bool _isLoading = false;
  bool _isAuthenticated = false;
  bool _isInitializing = true;
  UserModel? _user;
  String? _errorMessage;
  Uint8List? _avatarBytes;
  int _avatarRevision = 0;

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  bool get isInitializing => _isInitializing;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  Uint8List? get avatarBytes => _avatarBytes;
  int get avatarRevision => _avatarRevision;
  bool get hasLocalAvatar => _avatarBytes != null && _avatarBytes!.isNotEmpty;

  Future<void> checkAuthentication() async {
    _isInitializing = true;
    notifyListeners();

    try {
      final sessionUser = await _authService.checkAuthentication();
      _user = sessionUser;
      _isAuthenticated = sessionUser != null;
      _errorMessage = null;
      try {
        await _loadAvatar();
      } catch (error) {
        debugPrint('Could not load avatar: $error');
      }
    } catch (_) {
      _user = null;
      _isAuthenticated = false;
      _avatarBytes = null;
      _errorMessage = 'Unable to connect to the server.';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    return _runAuthAction(() async {
      final result = await _authService.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (result.success && result.user != null) {
        _user = result.user;
        _isAuthenticated = true;
        _errorMessage = null;
        try {
          await _loadAvatar();
        } catch (error) {
          debugPrint('Could not load avatar: $error');
        }
        return true;
      }

      _errorMessage = result.message ?? 'Invalid email or password.';
      return false;
    });
  }

  Future<bool> register({
    required String username,
    required String email,
    required String phoneNumber,
    required String password,
  }) async {
    return _runAuthAction(() async {
      final result = await _authService.register(
        username: username,
        email: email,
        phoneNumber: phoneNumber,
        password: password,
      );

      if (result.success) {
        _errorMessage = null;
        return true;
      }

      _errorMessage =
          result.message ?? 'Something went wrong. Please try again.';
      return false;
    });
  }

  Future<bool> forgotPassword({required String email}) async {
    return _runAuthAction(() async {
      final result = await _authService.forgotPassword(email: email);

      if (result.success) {
        _errorMessage = null;
        return true;
      }

      _errorMessage =
          result.message ?? 'Something went wrong. Please try again.';
      return false;
    });
  }

  Future<bool> updateAccount({
    required String username,
    required String email,
    required String phoneNumber,
    required String currentPassword,
    String? newPassword,
  }) async {
    return _runAuthAction(() async {
      final result = await _authService.updateAccount(
        username: username,
        email: email,
        phoneNumber: phoneNumber,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (result.success && result.user != null) {
        _user = result.user;
        _errorMessage = null;
        await _loadAvatar();
        return true;
      }

      _errorMessage =
          result.message ?? 'Something went wrong. Please try again.';
      return false;
    });
  }

  /// Saves the photo locally and uploads it so other devices (web/mobile) see it.
  Future<bool> saveLocalAvatar(List<int> bytes) async {
    final user = _user;
    if (user == null) {
      _errorMessage = 'Please sign in again.';
      notifyListeners();
      return false;
    }
    return _runAuthAction(() async {
      await _avatars.write(user.id, bytes);
      _avatarBytes = Uint8List.fromList(bytes);
      _avatarRevision++;

      final url = await _avatarCloud.upload(userId: user.id, bytes: bytes);
      await _users.updatePhotoUrl(userId: user.id, photoUrl: url);
      try {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      } catch (_) {}
      _user = user.copyWith(photoUrl: url);
      _errorMessage = null;
      return true;
    });
  }

  Future<bool> removeLocalAvatar() async {
    final user = _user;
    if (user == null) return false;
    return _runAuthAction(() async {
      await _avatars.delete(user.id);
      try {
        await _avatarCloud.delete(user.id);
      } catch (error) {
        debugPrint('Cloud avatar delete failed: $error');
      }
      await _users.updatePhotoUrl(userId: user.id, photoUrl: '');
      try {
        await FirebaseAuth.instance.currentUser?.updatePhotoURL(null);
      } catch (_) {}
      _avatarBytes = null;
      _avatarRevision++;
      _user = user.copyWith(photoUrl: '');
      _errorMessage = null;
      return true;
    });
  }

  Future<void> _loadAvatar() async {
    final user = _user;
    if (user == null) {
      _avatarBytes = null;
      return;
    }

    // Prefer cloud so a photo saved on phone appears on web (and vice versa).
    if (user.hasPhotoUrl) {
      try {
        final remote = await _avatarCloud.downloadBytes(user.photoUrl);
        if (remote != null && remote.isNotEmpty) {
          await _avatars.write(user.id, remote);
          _avatarBytes = remote;
          _avatarRevision++;
          return;
        }
      } catch (error) {
        debugPrint('Could not download cloud avatar: $error');
      }
    }

    _avatarBytes = await _avatars.read(user.id);
    _avatarRevision++;
  }

  Future<void> reloadUser() async {
    if (_user == null) return;
    try {
      final sessionUser = await _authService.checkAuthentication();
      if (sessionUser != null) {
        _user = sessionUser;
        await _loadAvatar();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
    } finally {
      _user = null;
      _isAuthenticated = false;
      _errorMessage = null;
      _avatarBytes = null;
      _avatarRevision++;
      _isLoading = false;
      notifyListeners();
      // Drop Super Admin tray / badge notifications as soon as the session ends.
      unawaited(NotificationService.instance.clearAll());
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _runAuthAction(Future<bool> Function() action) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await action();
    } catch (error, stack) {
      debugPrint('Auth action failed: $error\n$stack');
      _errorMessage =
          'Unable to finish that request. Check your internet connection and try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
