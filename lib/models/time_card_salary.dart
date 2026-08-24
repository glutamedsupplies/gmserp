import 'time_card_table.dart';
import 'time_entry.dart';

/// Paid workday used for hourly conversion of the daily rate.
const int kPaidMinutesPerDay = 8 * 60;

/// Payroll result for one employee over the filtered period.
class EmployeeSalaryBreakdown {
  const EmployeeSalaryBreakdown({
    required this.employeeId,
    required this.employeeName,
    required this.dailyRate,
    required this.presentDays,
    required this.lateDays,
    required this.absentDays,
    required this.excuseDays,
    required this.totalLateMinutes,
    required this.totalWorkedMinutes,
    required this.grossPay,
    required this.lateDeduction,
    required this.absentDeduction,
    required this.excuseDeduction,
    required this.netPay,
  });

  final String employeeId;
  final String employeeName;
  final double dailyRate;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final int excuseDays;
  final int totalLateMinutes;
  final int totalWorkedMinutes;
  final double grossPay;
  final double lateDeduction;
  final double absentDeduction;
  final double excuseDeduction;
  final double netPay;

  double get totalDeductions =>
      lateDeduction + absentDeduction + excuseDeduction;

  bool get hasRate => dailyRate > 0;

  /// Label for hours-worked row, e.g. `Worked (3 hours)` or `Worked (45 mins)`.
  String get formattedWorkedLabel =>
      _durationCountLabel('Worked', totalWorkedMinutes);

  /// Label for late row, e.g. `Late (2 hours)` or `Late (45 mins)`.
  String get formattedLateLabel =>
      _durationCountLabel('Late', totalLateMinutes);

  static String _durationCountLabel(String prefix, int totalMinutes) {
    if (totalMinutes <= 0) return prefix;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes == 0) {
      return '$prefix ($hours hour${hours == 1 ? '' : 's'})';
    }
    if (hours > 0) {
      return '$prefix ($hours hour${hours == 1 ? '' : 's'} $minutes min)';
    }
    return '$prefix ($minutes min${minutes == 1 ? '' : 's'})';
  }

  static String formatMoney(double amount) {
    final whole = amount == amount.roundToDouble();
    final text = whole
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '₱$text';
  }
}

DateTime? parseWorkDateString(String workDate) {
  final parts = workDate.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

int scheduledWorkMinutes({
  required DateTime date,
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  if (weeklySchedule != null) {
    final shift = weeklySchedule.forDate(date);
    if (!shift.isWorkDay) {
      return globalSchedule.workdayHours * 60;
    }
    final minutes =
        shift.timeOutOn(date).difference(shift.timeInOn(date)).inMinutes;
    return minutes > 0 ? minutes : globalSchedule.workdayHours * 60;
  }
  return globalSchedule.workdayHours * 60;
}

DateTime scheduledShiftStartOn({
  required DateTime date,
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  if (weeklySchedule != null) {
    return weeklySchedule.forDate(date).timeInOn(date);
  }
  return globalSchedule.shiftStartOn(date);
}

int lateMinutesForClockIn({
  required DateTime date,
  required DateTime timeIn,
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  final shiftStart = scheduledShiftStartOn(
    date: date,
    weeklySchedule: weeklySchedule,
    globalSchedule: globalSchedule,
  );
  if (!timeIn.isAfter(shiftStart)) return 0;
  return timeIn.difference(shiftStart).inMinutes;
}

double ratePerMinute({
  required double dailyRate,
  int workMinutes = kPaidMinutesPerDay,
}) {
  if (dailyRate <= 0 || workMinutes <= 0) return 0;
  return dailyRate / workMinutes;
}

int workedMinutesFromEntries(Iterable<TimeEntry> dayEntries) {
  var minutes = 0;
  for (final entry in dayEntries) {
    final m = entry.duration.inMinutes;
    if (m > 0) minutes += m;
  }
  return minutes;
}

int paidMinutesForDay(int workedMinutes) {
  if (workedMinutes <= 0) return 0;
  return workedMinutes > kPaidMinutesPerDay
      ? kPaidMinutesPerDay
      : workedMinutes;
}

EmployeeSalaryBreakdown computeEmployeeSalaryBreakdown({
  required String employeeId,
  required String employeeName,
  required double dailyRate,
  required List<TimeCardTableRow> rows,
  List<TimeEntry> entries = const [],
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  var presentDays = 0;
  var lateDays = 0;
  var absentDays = 0;
  var excuseDays = 0;
  var totalLateMinutes = 0;
  var totalWorkedMinutes = 0;
  var lateDeduction = 0.0;
  var earnedPay = 0.0;

  final entriesByDate = <String, List<TimeEntry>>{};
  for (final entry in entries) {
    entriesByDate.putIfAbsent(entry.workDate, () => []).add(entry);
  }

  final minuteRate = ratePerMinute(dailyRate: dailyRate);

  for (final row in rows) {
    switch (row.status) {
      case 'Present':
      case 'Late':
        if (row.status == 'Present') {
          presentDays++;
        } else {
          lateDays++;
        }
        final date = parseWorkDateString(row.workDate);
        final dayEntries = entriesByDate[row.workDate] ?? const <TimeEntry>[];
        final worked = paidMinutesForDay(workedMinutesFromEntries(dayEntries));
        totalWorkedMinutes += worked;
        if (dailyRate > 0) {
          earnedPay += worked * minuteRate;
        }
        if (row.status == 'Late' && date != null && dayEntries.isNotEmpty) {
          final firstIn = dayEntries
              .map((e) => e.timeIn)
              .reduce((a, b) => a.isBefore(b) ? a : b);
          final minutes = lateMinutesForClockIn(
            date: date,
            timeIn: firstIn,
            weeklySchedule: weeklySchedule,
            globalSchedule: globalSchedule,
          );
          totalLateMinutes += minutes;
          lateDeduction += minutes * minuteRate;
        }
      case 'Absent':
        absentDays++;
      case 'On Leave':
        excuseDays++;
      default:
        break;
    }
  }

  if (dailyRate <= 0) {
    return EmployeeSalaryBreakdown(
      employeeId: employeeId,
      employeeName: employeeName,
      dailyRate: 0,
      presentDays: presentDays,
      lateDays: lateDays,
      absentDays: absentDays,
      excuseDays: excuseDays,
      totalLateMinutes: totalLateMinutes,
      totalWorkedMinutes: totalWorkedMinutes,
      grossPay: 0,
      lateDeduction: 0,
      absentDeduction: 0,
      excuseDeduction: 0,
      netPay: 0,
    );
  }

  const absentDeduction = 0.0;
  const excuseDeduction = 0.0;
  final netPay = earnedPay < 0 ? 0.0 : earnedPay;

  return EmployeeSalaryBreakdown(
    employeeId: employeeId,
    employeeName: employeeName,
    dailyRate: dailyRate,
    presentDays: presentDays,
    lateDays: lateDays,
    absentDays: absentDays,
    excuseDays: excuseDays,
    totalLateMinutes: totalLateMinutes,
    totalWorkedMinutes: totalWorkedMinutes,
    grossPay: earnedPay,
    lateDeduction: lateDeduction,
    absentDeduction: absentDeduction,
    excuseDeduction: excuseDeduction,
    netPay: netPay,
  );
}

List<EmployeeSalaryBreakdown> computeSalaryBreakdowns({
  required List<TimeCardTableRow> rows,
  required Map<String, double> dailyRatesByUserId,
  Map<String, String> namesByUserId = const {},
  Map<String, List<TimeEntry>> entriesByUserId = const {},
  Map<String, EmployeeWeeklySchedule> weeklySchedulesByUserId = const {},
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  final grouped = <String, List<TimeCardTableRow>>{};
  for (final row in rows) {
    if (row.status == 'Off' || row.status == '—') continue;
    final key = row.employeeId.isEmpty ? '_single' : row.employeeId;
    grouped.putIfAbsent(key, () => []).add(row);
  }

  if (grouped.isEmpty) return const [];

  final breakdowns = <EmployeeSalaryBreakdown>[];
  for (final entry in grouped.entries) {
    final employeeId = entry.key == '_single' ? '' : entry.key;
    final sample = entry.value.first;
    final name = employeeId.isEmpty
        ? (sample.employeeName.isEmpty ? 'Employee' : sample.employeeName)
        : (namesByUserId[employeeId] ??
            (sample.employeeName.isEmpty ? 'Employee' : sample.employeeName));
    final rate = employeeId.isEmpty
        ? (dailyRatesByUserId.isEmpty ? 0.0 : dailyRatesByUserId.values.first)
        : (dailyRatesByUserId[employeeId] ?? 0.0);
    final employeeEntries = employeeId.isEmpty
        ? entriesByUserId.values.expand((list) => list).toList()
        : (entriesByUserId[employeeId] ?? const []);
    EmployeeWeeklySchedule? weeklySchedule;
    if (employeeId.isEmpty) {
      if (weeklySchedulesByUserId.isNotEmpty) {
        weeklySchedule = weeklySchedulesByUserId.values.first;
      }
    } else {
      weeklySchedule = weeklySchedulesByUserId[employeeId];
    }

    breakdowns.add(
      computeEmployeeSalaryBreakdown(
        employeeId: employeeId,
        employeeName: name,
        dailyRate: rate,
        rows: entry.value,
        entries: employeeEntries,
        weeklySchedule: weeklySchedule,
        globalSchedule: globalSchedule,
      ),
    );
  }

  breakdowns.sort(
    (a, b) => a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase()),
  );
  return breakdowns;
}

double totalNetSalary(Iterable<EmployeeSalaryBreakdown> breakdowns) {
  return breakdowns.fold(0, (sum, item) => sum + item.netPay);
}
