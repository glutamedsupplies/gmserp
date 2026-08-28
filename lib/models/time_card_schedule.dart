import '../core/utils/firebase_data.dart';
import 'time_entry.dart';

enum AttendanceStatus {
  present,
  late,
  absent,
  onLeave,
  offDay,
  pending;

  String get label {
    switch (this) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.onLeave:
        return 'On Leave';
      case AttendanceStatus.offDay:
        return 'Off';
      case AttendanceStatus.pending:
        return '—';
    }
  }

  static AttendanceStatus fromLabel(String? value) {
    switch (value) {
      case 'Present':
        return AttendanceStatus.present;
      case 'Late':
        return AttendanceStatus.late;
      case 'Absent':
        return AttendanceStatus.absent;
      case 'On Leave':
        return AttendanceStatus.onLeave;
      case 'Off':
        return AttendanceStatus.offDay;
      default:
        return AttendanceStatus.pending;
    }
  }
}

enum WorkWeekPattern {
  monFri,
  monSat,
  monSun;

  String get storageValue {
    switch (this) {
      case WorkWeekPattern.monFri:
        return 'Mon–Fri';
      case WorkWeekPattern.monSat:
        return 'Mon–Sat';
      case WorkWeekPattern.monSun:
        return 'Mon–Sun';
    }
  }

  String get label {
    switch (this) {
      case WorkWeekPattern.monFri:
        return 'Monday – Friday';
      case WorkWeekPattern.monSat:
        return 'Monday – Saturday';
      case WorkWeekPattern.monSun:
        return 'Monday – Sunday';
    }
  }

  static WorkWeekPattern fromStorage(String? value) {
    switch (value) {
      case 'Mon–Sat':
        return WorkWeekPattern.monSat;
      case 'Mon–Sun':
        return WorkWeekPattern.monSun;
      default:
        return WorkWeekPattern.monFri;
    }
  }

  bool isWorkDay(DateTime date) {
    final weekday = date.weekday; // Mon=1 … Sun=7
    switch (this) {
      case WorkWeekPattern.monFri:
        return weekday >= DateTime.monday && weekday <= DateTime.friday;
      case WorkWeekPattern.monSat:
        return weekday >= DateTime.monday && weekday <= DateTime.saturday;
      case WorkWeekPattern.monSun:
        return true;
    }
  }
}

class TimeCardSchedule {
  final int workdayHours;
  final int breakMinutes;
  /// Lunch / unpaid break start hour (0–23). Default noon.
  final int breakStartHour;
  /// Lunch / unpaid break start minute (0–59).
  final int breakStartMinute;
  final int overtimeAfterHours;
  final WorkWeekPattern workWeek;
  /// Scheduled shift start hour (0–23).
  final int shiftStartHour;
  /// Scheduled shift start minute (0–59).
  final int shiftStartMinute;
  /// Minutes after shift start before arrival counts as Late.
  final int lateGraceMinutes;

  const TimeCardSchedule({
    this.workdayHours = 8,
    this.breakMinutes = 60,
    this.breakStartHour = 12,
    this.breakStartMinute = 0,
    this.overtimeAfterHours = 8,
    this.workWeek = WorkWeekPattern.monFri,
    this.shiftStartHour = 9,
    this.shiftStartMinute = 0,
    this.lateGraceMinutes = 15,
  });

  static const TimeCardSchedule defaults = TimeCardSchedule();

  /// Paid work minutes used for minute-rate payroll (excludes unpaid break).
  int get paidWorkMinutes {
    final minutes = workdayHours * 60;
    return minutes > 0 ? minutes : 8 * 60;
  }

  DateTime shiftStartOn(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      shiftStartHour,
      shiftStartMinute,
    );
  }

  DateTime breakStartOn(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      breakStartHour.clamp(0, 23),
      breakStartMinute.clamp(0, 59),
    );
  }

  DateTime breakEndOn(DateTime date) {
    final minutes = breakMinutes < 0 ? 0 : breakMinutes;
    return breakStartOn(date).add(Duration(minutes: minutes));
  }

  DateTime lateThresholdOn(DateTime date) {
    return shiftStartOn(date).add(Duration(minutes: lateGraceMinutes));
  }

  String get shiftStartLabel =>
      formatHourMinute12h(shiftStartHour, shiftStartMinute);

  factory TimeCardSchedule.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return TimeCardSchedule(
      workdayHours: parseFirebaseInt(data['workdayHours'], 8),
      breakMinutes: parseFirebaseInt(data['breakMinutes'], 60),
      breakStartHour: parseFirebaseInt(data['breakStartHour'], 12).clamp(0, 23),
      breakStartMinute:
          parseFirebaseInt(data['breakStartMinute'], 0).clamp(0, 59),
      overtimeAfterHours: parseFirebaseInt(data['overtimeAfterHours'], 8),
      workWeek: WorkWeekPattern.fromStorage(data['workWeek']?.toString()),
      shiftStartHour: parseFirebaseInt(data['shiftStartHour'], 9).clamp(0, 23),
      shiftStartMinute:
          parseFirebaseInt(data['shiftStartMinute'], 0).clamp(0, 59),
      lateGraceMinutes:
          parseFirebaseInt(data['lateGraceMinutes'], 15).clamp(0, 240),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'workdayHours': workdayHours,
      'breakMinutes': breakMinutes,
      'breakStartHour': breakStartHour,
      'breakStartMinute': breakStartMinute,
      'overtimeAfterHours': overtimeAfterHours,
      'workWeek': workWeek.storageValue,
      'shiftStartHour': shiftStartHour,
      'shiftStartMinute': shiftStartMinute,
      'lateGraceMinutes': lateGraceMinutes,
    };
  }
}
