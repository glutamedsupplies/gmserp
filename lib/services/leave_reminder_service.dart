import 'package:shared_preferences/shared_preferences.dart';

import '../models/leave_request.dart';
import '../models/time_entry.dart';
import 'notification_service.dart';

/// Fires a one-day-before reminder for approved leave (employee / admin).
class LeaveReminderService {
  LeaveReminderService._();
  static final LeaveReminderService instance = LeaveReminderService._();

  static const _prefPrefix = 'leave_reminder_shown_';

  /// Notify when [tomorrow] falls on an approved leave day (day-before alert).
  Future<void> syncUpcomingLeaveReminders({
    required String userId,
    required List<LeaveRequest> leaves,
  }) async {
    if (userId.isEmpty) return;

    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final tomorrowKey = formatWorkDate(tomorrow);
    final prefs = await SharedPreferences.getInstance();

    for (final leave in leaves) {
      if (leave.status.toLowerCase() != 'approved') continue;
      if (!leave.coversWorkDate(tomorrowKey)) continue;

      final dedupeKey = '$_prefPrefix${userId}_${leave.id}_$tomorrowKey';
      if (prefs.getBool(dedupeKey) == true) continue;

      await NotificationService.instance.showLeaveReminder(
        leaveId: leave.id,
        leaveDate: tomorrowKey,
        companyName: leave.companyName,
      );
      await prefs.setBool(dedupeKey, true);
    }
  }
}
