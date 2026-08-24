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
    this.overtimeAfterHours = 8,
    this.workWeek = WorkWeekPattern.monFri,
    this.shiftStartHour = 9,
    this.shiftStartMinute = 0,
    this.lateGraceMinutes = 15,
  });

  static const TimeCardSchedule defaults = TimeCardSchedule();

  DateTime shiftStartOn(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      shiftStartHour,
      shiftStartMinute,
    );
  }

  DateTime lateThresholdOn(DateTime date) {
    return shiftStartOn(date).add(Duration(minutes: lateGraceMinutes));
  }

  String get shiftStartLabel {
    final hour24 = shiftStartHour;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final h = hour12.toString().padLeft(2, '0');
    final m = shiftStartMinute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  factory TimeCardSchedule.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    return TimeCardSchedule(
      workdayHours: _int(data['workdayHours'], 8),
      breakMinutes: _int(data['breakMinutes'], 60),
      overtimeAfterHours: _int(data['overtimeAfterHours'], 8),
      workWeek: WorkWeekPattern.fromStorage(data['workWeek']?.toString()),
      shiftStartHour: _int(data['shiftStartHour'], 9).clamp(0, 23),
      shiftStartMinute: _int(data['shiftStartMinute'], 0).clamp(0, 59),
      lateGraceMinutes: _int(data['lateGraceMinutes'], 15).clamp(0, 240),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'workdayHours': workdayHours,
      'breakMinutes': breakMinutes,
      'overtimeAfterHours': overtimeAfterHours,
      'workWeek': workWeek.storageValue,
      'shiftStartHour': shiftStartHour,
      'shiftStartMinute': shiftStartMinute,
      'lateGraceMinutes': lateGraceMinutes,
    };
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
