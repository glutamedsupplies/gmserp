import 'time_card_schedule.dart';

/// One day's scheduled time in / time out for an employee.
class DayShiftSchedule {
  const DayShiftSchedule({
    required this.isWorkDay,
    this.timeInHour = 9,
    this.timeInMinute = 0,
    this.timeOutHour = 18,
    this.timeOutMinute = 0,
  });

  final bool isWorkDay;
  final int timeInHour;
  final int timeInMinute;
  final int timeOutHour;
  final int timeOutMinute;

  static const DayShiftSchedule off = DayShiftSchedule(isWorkDay: false);

  static const DayShiftSchedule nineToSix = DayShiftSchedule(
    isWorkDay: true,
    timeInHour: 9,
    timeInMinute: 0,
    timeOutHour: 18,
    timeOutMinute: 0,
  );

  static const DayShiftSchedule tenToSeven = DayShiftSchedule(
    isWorkDay: true,
    timeInHour: 10,
    timeInMinute: 0,
    timeOutHour: 19,
    timeOutMinute: 0,
  );

  DateTime timeInOn(DateTime date) => DateTime(
        date.year,
        date.month,
        date.day,
        timeInHour.clamp(0, 23),
        timeInMinute.clamp(0, 59),
      );

  DateTime timeOutOn(DateTime date) {
    var end = DateTime(
      date.year,
      date.month,
      date.day,
      timeOutHour.clamp(0, 23),
      timeOutMinute.clamp(0, 59),
    );
    final start = timeInOn(date);
    if (!end.isAfter(start)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  DateTime lateThresholdOn(DateTime date, int graceMinutes) {
    return timeInOn(date).add(Duration(minutes: graceMinutes));
  }

  String get timeInLabel => _formatClock(timeInHour, timeInMinute);

  String get timeOutLabel => _formatClock(timeOutHour, timeOutMinute);

  String get rangeLabel {
    if (!isWorkDay) return 'Off';
    return '$timeInLabel – $timeOutLabel';
  }

  DayShiftSchedule copyWith({
    bool? isWorkDay,
    int? timeInHour,
    int? timeInMinute,
    int? timeOutHour,
    int? timeOutMinute,
  }) {
    return DayShiftSchedule(
      isWorkDay: isWorkDay ?? this.isWorkDay,
      timeInHour: timeInHour ?? this.timeInHour,
      timeInMinute: timeInMinute ?? this.timeInMinute,
      timeOutHour: timeOutHour ?? this.timeOutHour,
      timeOutMinute: timeOutMinute ?? this.timeOutMinute,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'work': isWorkDay,
      'inH': timeInHour,
      'inM': timeInMinute,
      'outH': timeOutHour,
      'outM': timeOutMinute,
    };
  }

  factory DayShiftSchedule.fromFirestore(dynamic raw) {
    if (raw is! Map) return DayShiftSchedule.off;
    final data = Map<String, dynamic>.from(raw);
    return DayShiftSchedule(
      isWorkDay: data['work'] == true,
      timeInHour: _int(data['inH'], 9).clamp(0, 23),
      timeInMinute: _int(data['inM'], 0).clamp(0, 59),
      timeOutHour: _int(data['outH'], 18).clamp(0, 23),
      timeOutMinute: _int(data['outM'], 0).clamp(0, 59),
    );
  }

  static String _formatClock(int hour24, int minute) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final h = hour12.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  static int _int(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

/// Per-employee weekly time in / time out schedule.
class EmployeeWeeklySchedule {
  const EmployeeWeeklySchedule(this.days);

  /// Keys: [DateTime.monday] (1) … [DateTime.sunday] (7).
  final Map<int, DayShiftSchedule> days;

  static const _weekdayKeys = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  static const weekdayLabels = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  /// Default Mon–Fri 9:00 AM – 6:00 PM.
  factory EmployeeWeeklySchedule.defaults() {
    return EmployeeWeeklySchedule({
      for (final day in _weekdayKeys)
        day: day <= DateTime.friday
            ? DayShiftSchedule.nineToSix
            : DayShiftSchedule.off,
    });
  }

  DayShiftSchedule forWeekday(int weekday) {
    return days[weekday] ?? DayShiftSchedule.off;
  }

  DayShiftSchedule forDate(DateTime date) => forWeekday(date.weekday);

  bool isWorkDay(DateTime date) => forDate(date).isWorkDay;

  String get summaryLabel {
    final workDays = _weekdayKeys
        .where((day) => forWeekday(day).isWorkDay)
        .toList(growable: false);
    if (workDays.isEmpty) return 'No work days';

    final first = forWeekday(workDays.first);
    final sameHours = workDays.every((day) {
      final shift = forWeekday(day);
      return shift.timeInHour == first.timeInHour &&
          shift.timeInMinute == first.timeInMinute &&
          shift.timeOutHour == first.timeOutHour &&
          shift.timeOutMinute == first.timeOutMinute;
    });

    final daySpan = workDays.length == 5 &&
            workDays.first == DateTime.monday &&
            workDays.last == DateTime.friday
        ? 'Mon–Fri'
        : workDays.map((d) => weekdayLabels[d]).join(', ');

    if (sameHours) return '$daySpan · ${first.rangeLabel}';
    return '$daySpan · custom hours';
  }

  EmployeeWeeklySchedule copyWithDay(int weekday, DayShiftSchedule shift) {
    return EmployeeWeeklySchedule({
      ...days,
      weekday: shift,
    });
  }

  EmployeeWeeklySchedule applyShiftToWorkDays(DayShiftSchedule shift) {
    return EmployeeWeeklySchedule({
      for (final day in _weekdayKeys)
        day: forWeekday(day).isWorkDay
            ? shift.copyWith(isWorkDay: true)
            : forWeekday(day),
    });
  }

  Map<String, dynamic> toFirestore() {
    return {
      for (final day in _weekdayKeys) '$day': forWeekday(day).toFirestore(),
    };
  }

  factory EmployeeWeeklySchedule.fromFirestore(dynamic raw) {
    if (raw is! Map) return EmployeeWeeklySchedule.defaults();
    final data = Map<String, dynamic>.from(raw);
    return EmployeeWeeklySchedule({
      for (final day in _weekdayKeys)
        day: DayShiftSchedule.fromFirestore(data['$day']),
    });
  }
}

/// Daily rate + weekly schedule for one employee in a company.
class EmployeeTimeCardProfile {
  const EmployeeTimeCardProfile({
    this.dailyRate = 0,
    required this.weeklySchedule,
  });

  final double dailyRate;
  final EmployeeWeeklySchedule weeklySchedule;

  static EmployeeTimeCardProfile defaults() {
    return EmployeeTimeCardProfile(
      weeklySchedule: EmployeeWeeklySchedule.defaults(),
    );
  }

  bool get hasRate => dailyRate > 0;

  String get rateLabel {
    if (!hasRate) return 'No rate set';
    final whole = dailyRate == dailyRate.roundToDouble();
    final amount = whole
        ? dailyRate.toStringAsFixed(0)
        : dailyRate.toStringAsFixed(2);
    return '₱$amount / day';
  }

  EmployeeTimeCardProfile copyWith({
    double? dailyRate,
    EmployeeWeeklySchedule? weeklySchedule,
  }) {
    return EmployeeTimeCardProfile(
      dailyRate: dailyRate ?? this.dailyRate,
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
    );
  }

  /// Builds a [TimeCardSchedule]-compatible late check using this employee's day.
  DateTime lateThresholdOn(DateTime date, TimeCardSchedule global) {
    final shift = weeklySchedule.forDate(date);
    if (!shift.isWorkDay) {
      return global.lateThresholdOn(date);
    }
    return shift.lateThresholdOn(date, global.lateGraceMinutes);
  }

  Map<String, dynamic> toStaffFields() {
    return {
      'timeCardDailyRate': dailyRate,
      'timeCardWeek': weeklySchedule.toFirestore(),
    };
  }

  factory EmployeeTimeCardProfile.fromStaffData(Map<String, dynamic> data) {
    final rateRaw = data['timeCardDailyRate'];
    final rate = rateRaw is num
        ? rateRaw.toDouble()
        : double.tryParse(rateRaw?.toString() ?? '') ?? 0;
    return EmployeeTimeCardProfile(
      dailyRate: rate < 0 ? 0 : rate,
      weeklySchedule: EmployeeWeeklySchedule.fromFirestore(data['timeCardWeek']),
    );
  }
}
