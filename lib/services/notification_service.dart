import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local device notifications + app-icon badge for Super Admin pending requests.
///
/// Badge count is driven by [flutter_local_notifications] (Android notification
/// number + iOS/macOS badgeNumber) so we avoid plugins that apply KGP.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'gmserp_requests';
  static const _channelName = 'Requests';
  static const _pendingNotificationId = 71001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _lastNotifiedCount = -1;

  bool get _supportsNative =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> initialize() async {
    if (_initialized || !_supportsNative) {
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(settings: settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Pending leave and time-card change requests',
        importance: Importance.high,
        showBadge: true,
      ),
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (!_supportsNative) return false;
    await initialize();

    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          await mac?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      return granted;
    }

    return false;
  }

  /// Updates the launcher badge and optionally pushes a device notification
  /// when the pending count increases.
  Future<void> syncSuperAdminPending({
    required int count,
    required bool notificationsEnabled,
    bool announceIncrease = true,
  }) async {
    if (!_supportsNative) return;
    await initialize();

    if (!notificationsEnabled) {
      await clearAll();
      return;
    }

    if (count <= 0) {
      await clearAll();
      return;
    }

    final increased =
        announceIncrease && _lastNotifiedCount >= 0 && count > _lastNotifiedCount;
    final firstSeed = !announceIncrease || _lastNotifiedCount < 0;

    // Keep an active notification so Android launcher badges stay in sync.
    // Sound/alert only when the pending count actually increases.
    await _showPendingNotification(
      count: count,
      alert: increased && !firstSeed,
    );

    _lastNotifiedCount = count;
  }

  Future<void> clearAll() async {
    if (!_supportsNative) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    await _clearDarwinBadge();
    _lastNotifiedCount = 0;
  }

  Future<void> _showPendingNotification({
    required int count,
    required bool alert,
  }) async {
    final badge = count > 99 ? 99 : count;
    final label = count > 99 ? '99+' : '$count';
    final body = count == 1
        ? 'You have 1 pending request waiting for review.'
        : 'You have $label pending requests waiting for review.';

    await _plugin.show(
      id: _pendingNotificationId,
      title: 'GMSERP · Requests',
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Pending leave and time-card change requests',
          importance: alert ? Importance.high : Importance.low,
          priority: alert ? Priority.high : Priority.low,
          number: badge,
          onlyAlertOnce: !alert,
          playSound: alert,
          enableVibration: alert,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentBadge: true,
          presentSound: alert,
          badgeNumber: badge,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentBadge: true,
          presentSound: alert,
          badgeNumber: badge,
        ),
      ),
    );
  }

  Future<void> _clearDarwinBadge() async {
    if (!Platform.isIOS && !Platform.isMacOS) return;
    try {
      await _plugin.show(
        id: _pendingNotificationId,
        title: null,
        body: null,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: 0,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: false,
            badgeNumber: 0,
          ),
        ),
      );
      await _plugin.cancel(id: _pendingNotificationId);
    } catch (_) {}
  }
}
