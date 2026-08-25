import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Deep-link target carried in a Super Admin request notification payload.
class RequestNotificationPayload {
  const RequestNotificationPayload({
    required this.type,
    required this.id,
  });

  /// `leave` or `time` or `clock`
  final String type;
  final String id;

  static const typeLeave = 'leave';
  static const typeTime = 'time';
  static const typeClock = 'clock';

  String encode() => '$type|$id';

  static RequestNotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length < 2) return null;
    final type = parts[0].trim().toLowerCase();
    final id = parts.sublist(1).join('|').trim();
    if (id.isEmpty) return null;
    if (type != typeLeave && type != typeTime && type != typeClock) {
      return null;
    }
    return RequestNotificationPayload(type: type, id: id);
  }
}

/// Local device notifications + app-icon badge for Super Admin pending requests.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'gmserp_requests';
  static const _channelName = 'Requests';
  static const _leaveChannelId = 'gmserp_leave';
  static const _leaveChannelName = 'Leave reminders';
  static const _outcomeChannelId = 'gmserp_outcomes';
  static const _outcomeChannelName = 'Request outcomes';
  static const _pendingNotificationId = 71001;
  static const _leaveReminderIdBase = 72000;
  static const _outcomeNotificationIdBase = 73000;
  static const requestsRoutePayload = 'requests';
  static const calendarRoutePayload = 'calendar';
  static const notificationsRoutePayload = 'notifications';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _lastNotifiedCount = -1;

  /// Called when the user taps a notification (foreground / background / cold).
  void Function(String? payload)? onNotificationTap;

  bool get _supportsNative =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> initialize() async {
    if (_initialized || !_supportsNative) {
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@drawable/ic_stat_gmserp');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      defaultPresentBadge: true,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onSelect,
    );

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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _leaveChannelId,
        _leaveChannelName,
        description: 'Reminders one day before approved leave',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _outcomeChannelId,
        _outcomeChannelName,
        description: 'Approved or declined leave and time-card requests',
        importance: Importance.high,
        showBadge: true,
      ),
    );

    _initialized = true;
  }

  /// If the app was launched by tapping a notification, return its payload.
  Future<String?> consumeLaunchPayload() async {
    if (!_supportsNative) return null;
    await initialize();
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
  }

  void _onSelect(NotificationResponse response) {
    onNotificationTap?.call(response.payload);
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
    String? title,
    String? body,
    String? payload,
  }) async {
    if (!_supportsNative) return;
    await initialize();

    if (!notificationsEnabled) {
      await _cancelPendingRequestNotification();
      return;
    }

    if (count <= 0) {
      await _cancelPendingRequestNotification();
      return;
    }

    final increased =
        announceIncrease && _lastNotifiedCount >= 0 && count > _lastNotifiedCount;
    final firstSeed = !announceIncrease || _lastNotifiedCount < 0;

    await _showPendingNotification(
      count: count,
      alert: increased && !firstSeed,
      title: title,
      body: body,
      payload: payload,
    );

    _lastNotifiedCount = count;
  }

  /// Local alert: approved leave starts tomorrow (one day before).
  Future<void> showLeaveReminder({
    required String leaveId,
    required String leaveDate,
    required String companyName,
  }) async {
    if (!_supportsNative) return;
    await initialize();

    final id = _leaveReminderIdBase + (leaveId.hashCode.abs() % 5000);
    final company = companyName.trim().isEmpty ? 'your company' : companyName;
    const title = 'Leave reminder';
    final body =
        'Your leave for $leaveDate at $company is tomorrow. Prepare ahead.';

    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _leaveChannelId,
          _leaveChannelName,
          channelDescription: 'Reminders one day before approved leave',
          icon: '@drawable/ic_stat_gmserp',
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_gmserp',
          ),
          color: const Color(0xFFA2D929),
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      payload: calendarRoutePayload,
    );
  }

  /// Stable tray id for a notifications-page entry (`leave:…` / `time:…`).
  int outcomeNotificationId(String entryId) {
    return _outcomeNotificationIdBase + (entryId.hashCode.abs() % 5000);
  }

  String outcomePayload(String entryId) => 'notif|$entryId';

  static String? tryParseOutcomeEntryId(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    if (payload == notificationsRoutePayload) return null;
    if (!payload.startsWith('notif|')) return null;
    final id = payload.substring('notif|'.length).trim();
    return id.isEmpty ? null : id;
  }

  /// Local alert when a leave / time-card request is approved or declined.
  Future<void> showRequestOutcome({
    required String entryId,
    required String title,
    required String body,
    bool alert = true,
  }) async {
    if (!_supportsNative) return;
    await initialize();

    final id = outcomeNotificationId(entryId);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _outcomeChannelId,
          _outcomeChannelName,
          channelDescription:
              'Approved or declined leave and time-card requests',
          icon: '@drawable/ic_stat_gmserp',
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_gmserp',
          ),
          color: const Color(0xFFA2D929),
          importance: alert ? Importance.high : Importance.low,
          priority: alert ? Priority.high : Priority.low,
          onlyAlertOnce: !alert,
          playSound: alert,
          enableVibration: alert,
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentBadge: true,
          presentSound: alert,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: alert,
          presentBadge: true,
          presentSound: alert,
        ),
      ),
      payload: outcomePayload(entryId),
    );
  }

  Future<void> cancelRequestOutcome(String entryId) async {
    if (!_supportsNative) return;
    await initialize();
    try {
      await _plugin.cancel(id: outcomeNotificationId(entryId));
    } catch (_) {}
  }

  Future<void> _cancelPendingRequestNotification() async {
    try {
      await _plugin.cancel(id: _pendingNotificationId);
    } catch (_) {}
    await _clearDarwinBadge();
    _lastNotifiedCount = 0;
  }

  Future<void> clearAll() async {
    if (!_supportsNative) {
      _lastNotifiedCount = 0;
      return;
    }
    await initialize();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
    await _clearDarwinBadge();
    _lastNotifiedCount = 0;
  }

  Future<void> _showPendingNotification({
    required int count,
    required bool alert,
    String? title,
    String? body,
    String? payload,
  }) async {
    final badge = count > 99 ? 99 : count;
    final label = count > 99 ? '99+' : '$count';
    final resolvedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'GMSERP · Requests';
    final resolvedBody = body?.trim().isNotEmpty == true
        ? body!.trim()
        : (count == 1
            ? 'You have 1 pending request waiting for review.'
            : 'You have $label pending requests waiting for review.');
    final resolvedPayload =
        (payload != null && payload.trim().isNotEmpty)
            ? payload.trim()
            : requestsRoutePayload;

    await _plugin.show(
      id: _pendingNotificationId,
      title: resolvedTitle,
      body: resolvedBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Pending leave and time-card change requests',
          icon: '@drawable/ic_stat_gmserp',
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_notification_gmserp',
          ),
          color: const Color(0xFFA2D929),
          importance: alert ? Importance.high : Importance.low,
          priority: alert ? Priority.high : Priority.low,
          number: badge,
          onlyAlertOnce: !alert,
          playSound: alert,
          enableVibration: alert,
          styleInformation: BigTextStyleInformation(resolvedBody),
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
      payload: resolvedPayload,
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
