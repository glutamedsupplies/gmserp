import '../core/utils/firebase_data.dart';
import 'employee_time_card_profile.dart';
import 'salary_rate_change.dart';

/// Audit trail when an admin updates an employee's time card settings.
class TimeCardProfileChange {
  const TimeCardProfileChange({
    required this.id,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    required this.employeeId,
    required this.employeeName,
    required this.employeeEmail,
    required this.actorId,
    required this.actorName,
    required this.previousRate,
    required this.newRate,
    required this.previousScheduleSummary,
    required this.newScheduleSummary,
    required this.recipientIds,
    this.createdAt,
  });

  final String id;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
  final String employeeId;
  final String employeeName;
  final String employeeEmail;
  final String actorId;
  final String actorName;
  final double previousRate;
  final double newRate;
  final String previousScheduleSummary;
  final String newScheduleSummary;
  final List<String> recipientIds;
  final DateTime? createdAt;

  bool get rateChanged => (previousRate - newRate).abs() > 0.0001;

  bool get scheduleChanged =>
      previousScheduleSummary.trim() != newScheduleSummary.trim();

  String get rateChangeLabel => rateChanged
      ? '${SalaryRateChange.formatRate(previousRate)} → '
          '${SalaryRateChange.formatRate(newRate)}'
      : SalaryRateChange.formatRate(newRate);

  String get scheduleChangeLabel => scheduleChanged
      ? '$previousScheduleSummary → $newScheduleSummary'
      : newScheduleSummary;

  String get changeSummary {
    final parts = <String>[];
    if (rateChanged) parts.add(rateChangeLabel);
    if (scheduleChanged) parts.add(scheduleChangeLabel);
    if (parts.isEmpty) return 'Time card settings updated';
    return parts.join(' · ');
  }

  Map<String, dynamic> toFirestore() {
    return {
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'actorId': actorId,
      'actorName': actorName,
      'previousRate': previousRate,
      'newRate': newRate,
      'previousScheduleSummary': previousScheduleSummary,
      'newScheduleSummary': newScheduleSummary,
      'recipientIds': recipientIdsToMap(recipientIds),
      'createdAt': serverTimestamp(),
      'type': 'timeCardProfile',
    };
  }

  factory TimeCardProfileChange.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    double asRate(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return TimeCardProfileChange(
      id: id,
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      employeeId: data['employeeId']?.toString() ?? '',
      employeeName: data['employeeName']?.toString() ?? '',
      employeeEmail: data['employeeEmail']?.toString() ?? '',
      actorId: data['actorId']?.toString() ?? '',
      actorName: data['actorName']?.toString() ?? '',
      previousRate: asRate(data['previousRate']),
      newRate: asRate(data['newRate']),
      previousScheduleSummary:
          data['previousScheduleSummary']?.toString() ?? '',
      newScheduleSummary: data['newScheduleSummary']?.toString() ?? '',
      recipientIds: parseRecipientIds(data['recipientIds']),
      createdAt: parseFirebaseDate(data['createdAt']),
    );
  }

  static bool profilesEqual(
    EmployeeTimeCardProfile a,
    EmployeeTimeCardProfile b,
  ) {
    if ((a.dailyRate - b.dailyRate).abs() > 0.0001) return false;
    for (final day in EmployeeWeeklySchedule.weekdayLabels.keys) {
      final left = a.weeklySchedule.forWeekday(day);
      final right = b.weeklySchedule.forWeekday(day);
      if (left.isWorkDay != right.isWorkDay ||
          left.timeInHour != right.timeInHour ||
          left.timeInMinute != right.timeInMinute ||
          left.timeOutHour != right.timeOutHour ||
          left.timeOutMinute != right.timeOutMinute) {
        return false;
      }
    }
    return true;
  }
}
