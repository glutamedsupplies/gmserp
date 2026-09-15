import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import 'notification_seen_store.dart';
import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final userId = message.data['recipientId'];
  final entryId = message.data['entryId'];
  if (userId != null && entryId != null) {
    await NotificationSeenStore.instance.markAnnounced(userId, entryId);
  }
}

/// Registers this installation for server-originated background notifications.
class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();
  // Public Web Push key for gmserp-ffc76; override for other environments.
  static const _vapid = String.fromEnvironment(
    'FCM_VAPID_KEY',
    defaultValue: 'BOj_n7M8_HVrsRvxesVUFCRKBn4EDgatBEyYzGnHPjP1t7BivupIrc0ExZf24nG_bz_W2ct1SBrh4qkbxDo-f7o',
  );
  bool _initialized = false;
  String? _userId;
  String? _companyId;
  String? _token;
  String? _launchPayload;
  Future<void> _queue = Future.value();

  bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if (_initialized || !supported) return;
    _initialized = true;
    if (!kIsWeb) FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService.instance.onNotificationTap?.call(
        message.data['payload'] ??
            NotificationService.notificationsRoutePayload,
      );
    });
    // Existing database listeners own foreground alerts, avoiding duplicate alerts.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _token = token;
      syncSession(_userId, companyId: _companyId);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _launchPayload =
          initial.data['payload'] ??
          NotificationService.notificationsRoutePayload;
    }
  }

  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  void refreshRegistration() => syncSession(_userId, companyId: _companyId);

  void syncSession(String? userId, {String? companyId}) {
    _queue = _queue
        .catchError((Object _) {})
        .then((_) async {
          if (!supported) return;
          await initialize();
          if (userId == null &&
              _userId != null &&
              _token != null &&
              FirebaseAuth.instance.currentUser?.uid == _userId) {
            final key = sha256.convert(utf8.encode(_token!)).toString();
            await FirebaseDatabase.instance
                .ref('pushTokens/$_userId/$key')
                .remove();
          }
          _userId = userId;
          _companyId = companyId;
          if (userId == null) return;
          if (kIsWeb && _vapid.isEmpty) return;
          final settings = await FirebaseMessaging.instance
              .getNotificationSettings();
          if (settings.authorizationStatus != AuthorizationStatus.authorized &&
              settings.authorizationStatus != AuthorizationStatus.provisional) {
            return;
          }
          _token ??= await FirebaseMessaging.instance.getToken(
            vapidKey: kIsWeb ? _vapid : null,
          );
          final token = _token;
          if (token == null ||
              FirebaseAuth.instance.currentUser?.uid != userId) {
            return;
          }
          final key = sha256.convert(utf8.encode(token)).toString();
          await FirebaseDatabase.instance.ref('pushTokens/$userId/$key').set({
            'token': token,
            'enabled':
                (await SharedPreferences.getInstance()).getBool(
                  'settings.notifications',
                ) ??
                true,
            'companyId': companyId ?? '',
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
            'updatedAt': ServerValue.timestamp,
          });
        })
        .catchError((Object error) {
          debugPrint('Push registration unavailable: $error');
        });
  }

  /// Call before signing out, while this user can still remove their token.
  Future<void> unregister() async {
    await _queue;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    // A token-refresh callback during deletion must not re-register this user.
    _userId = null;
    _companyId = null;
    if (supported && token != null && userId != null) {
      final key = sha256.convert(utf8.encode(token)).toString();
      try {
        await FirebaseDatabase.instance.ref('pushTokens/$userId/$key').remove();
      } catch (error) {
        debugPrint('Could not remove push registration: $error');
      }
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (error) {
        debugPrint('Could not invalidate push token: $error');
      }
    }
    _token = null;
  }
}
