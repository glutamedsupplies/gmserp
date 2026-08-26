import 'time_card_table.dart';
import 'time_entry.dart';

/// Default paid workday (8 hours) used when converting daily rate → minute rate.
const int kPaidMinutesPerDay = 8 * 60;

/// Payroll result for one employee over the filtered period.
///
/// Model:
/// - Hourly Rate = Daily Rate / workday hours
/// - Minute Rate = Daily Rate / paid minutes (default 480)
/// - Late Deduction = Late Minutes × Minute Rate
/// - Early Out Deduction = Early Out Minutes × Minute Rate
/// - Basic Pay = Daily Rate × Payable Days
/// - Net Pay = Basic Pay − Late − Early Out − Other + Additions (≥ 0)
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
    required this.totalEarlyOutMinutes,
    required this.totalWorkedMinutes,
    required this.grossPay,
    required this.lateDeduction,
    required this.earlyOutDeduction,
    required this.absentDeduction,
    required this.excuseDeduction,
    required this.otherDeductions,
    required this.additions,
    required this.netPay,
    required this.hourlyRate,
    required this.minuteRate,
  });

  final String employeeId;
  final String employeeName;
  final double dailyRate;
  final int presentDays;
  final int lateDays;
  final int absentDays;
  final int excuseDays;
  final int totalLateMinutes;
  final int totalEarlyOutMinutes;
  final int totalWorkedMinutes;

  /// Basic pay for the period (= dailyRate × payableDays).
  final double grossPay;
  final double lateDeduction;
  final double earlyOutDeduction;
  final double absentDeduction;
  final double excuseDeduction;
  final double otherDeductions;
  final double additions;
  final double netPay;
  final double hourlyRate;
  final double minuteRate;

  /// Present + Late days that earn the daily base salary.
  int get payableDays => presentDays + lateDays;

  double get basicPay => grossPay;

  double get totalDeductions =>
      lateDeduction +
      earlyOutDeduction +
      absentDeduction +
      excuseDeduction +
      otherDeductions;

  bool get hasRate => dailyRate > 0;

  String get formattedLateLabel {
    if (totalLateMinutes <= 0) return 'Total Late';
    return 'Total Late: $totalLateMinutes minute${totalLateMinutes == 1 ? '' : 's'}';
  }

  String get formattedEarlyOutLabel {
    if (totalEarlyOutMinutes <= 0) return 'Total Early Out';
    return 'Total Early Out: $totalEarlyOutMinutes minute${totalEarlyOutMinutes == 1 ? '' : 's'}';
  }

  /// Money display: always 2 decimal places, with thousands separators.
  static String formatMoney(double amount, {bool showMinus = false}) {
    final negative = amount < 0 || (showMinus && amount != 0);
    final abs = amount.abs();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _withThousands(parts[0]);
    final sign = negative ? '-' : '';
    return '$sign₱$whole.${parts[1]}';
  }

  static String _withThousands(String digits) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    final lead = digits.length % 3;
    if (lead > 0) buffer.write(digits.substring(0, lead));
    for (var i = lead; i < digits.length; i += 3) {
      if (buffer.isNotEmpty) buffer.write(',');
      buffer.write(digits.substring(i, i + 3));
    }
    return buffer.toString();
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
  return globalSchedule.paidWorkMinutes;
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

DateTime scheduledShiftEndOn({
  required DateTime date,
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  if (weeklySchedule != null) {
    final shift = weeklySchedule.forDate(date);
    if (shift.isWorkDay) return shift.timeOutOn(date);
  }
  // Global wall end = shift start + paid work + unpaid break.
  final breakMinutes =
      globalSchedule.breakMinutes < 0 ? 0 : globalSchedule.breakMinutes;
  return globalSchedule.shiftStartOn(date).add(
        Duration(minutes: globalSchedule.paidWorkMinutes + breakMinutes),
      );
}

/// Minutes of unpaid break overlapping `[from, to)`.
int unpaidBreakOverlapMinutes({
  required DateTime from,
  required DateTime to,
  required DateTime breakStart,
  required DateTime breakEnd,
}) {
  if (!to.isAfter(from) || !breakEnd.isAfter(breakStart)) return 0;
  final overlapStart = from.isAfter(breakStart) ? from : breakStart;
  final overlapEnd = to.isBefore(breakEnd) ? to : breakEnd;
  if (!overlapEnd.isAfter(overlapStart)) return 0;
  return overlapEnd.difference(overlapStart).inMinutes;
}

/// Payable late minutes from scheduled start to clock-in, excluding lunch break.
///
/// Examples (9:00–18:00, lunch 12:00–13:00):
/// - Time in 13:00 → 180 (not 240)
/// - Time in 14:00 → 240
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

  final wallMinutes = timeIn.difference(shiftStart).inMinutes;
  final lunchSkipped = unpaidBreakOverlapMinutes(
    from: shiftStart,
    to: timeIn,
    breakStart: globalSchedule.breakStartOn(date),
    breakEnd: globalSchedule.breakEndOn(date),
  );
  final payable = wallMinutes - lunchSkipped;
  return payable < 0 ? 0 : payable;
}

/// Payable early-out minutes from clock-out to scheduled end, excluding lunch.
///
/// Examples (9:00–18:00, lunch 12:00–13:00):
/// - Time out 17:00 → 60
/// - Time out 12:30 → 300 (330 wall − 30 remaining lunch)
int earlyOutMinutesForClockOut({
  required DateTime date,
  required DateTime timeOut,
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
}) {
  final shiftEnd = scheduledShiftEndOn(
    date: date,
    weeklySchedule: weeklySchedule,
    globalSchedule: globalSchedule,
  );
  if (!timeOut.isBefore(shiftEnd)) return 0;

  final wallMinutes = shiftEnd.difference(timeOut).inMinutes;
  final lunchSkipped = unpaidBreakOverlapMinutes(
    from: timeOut,
    to: shiftEnd,
    breakStart: globalSchedule.breakStartOn(date),
    breakEnd: globalSchedule.breakEndOn(date),
  );
  final payable = wallMinutes - lunchSkipped;
  return payable < 0 ? 0 : payable;
}

/// Latest closed time-out for the day, or null if any session is still open /
/// there is no closed out.
DateTime? latestClosedTimeOut(Iterable<TimeEntry> dayEntries) {
  DateTime? latest;
  for (final entry in dayEntries) {
    if (entry.timeOut == null) return null;
    if (latest == null || entry.timeOut!.isAfter(latest)) {
      latest = entry.timeOut;
    }
  }
  return latest;
}

double ratePerMinute({
  required double dailyRate,
  int workMinutes = kPaidMinutesPerDay,
}) {
  if (dailyRate <= 0 || workMinutes <= 0) return 0;
  return dailyRate / workMinutes;
}

double ratePerHour({
  required double dailyRate,
  int workdayHours = 8,
}) {
  if (dailyRate <= 0 || workdayHours <= 0) return 0;
  return dailyRate / workdayHours;
}

int workedMinutesFromEntries(Iterable<TimeEntry> dayEntries) {
  var minutes = 0;
  for (final entry in dayEntries) {
    final m = entry.duration.inMinutes;
    if (m > 0) minutes += m;
  }
  return minutes;
}

int paidMinutesForDay(int workedMinutes, {int cap = kPaidMinutesPerDay}) {
  if (workedMinutes <= 0) return 0;
  return workedMinutes > cap ? cap : workedMinutes;
}

EmployeeSalaryBreakdown computeEmployeeSalaryBreakdown({
  required String employeeId,
  required String employeeName,
  required double dailyRate,
  required List<TimeCardTableRow> rows,
  List<TimeEntry> entries = const [],
  EmployeeWeeklySchedule? weeklySchedule,
  TimeCardSchedule globalSchedule = TimeCardSchedule.defaults,
  double otherDeductions = 0,
  double additions = 0,
}) {
  var presentDays = 0;
  var lateDays = 0;
  var absentDays = 0;
  var excuseDays = 0;
  var totalLateMinutes = 0;
  var totalEarlyOutMinutes = 0;
  var totalWorkedMinutes = 0;
  var lateDeduction = 0.0;
  var earlyOutDeduction = 0.0;

  final entriesByDate = <String, List<TimeEntry>>{};
  for (final entry in entries) {
    entriesByDate.putIfAbsent(entry.workDate, () => []).add(entry);
  }

  final paidMinutes = globalSchedule.paidWorkMinutes;
  final minuteRate = ratePerMinute(
    dailyRate: dailyRate,
    workMinutes: paidMinutes,
  );
  final hourlyRate = ratePerHour(
    dailyRate: dailyRate,
    workdayHours: globalSchedule.workdayHours > 0
        ? globalSchedule.workdayHours
        : 8,
  );

  // One pay day per workDate (daily filter may emit multiple session rows).
  final countedDates = <String>{};

  for (final row in rows) {
    switch (row.status) {
      case 'Present':
      case 'Late':
        if (!countedDates.add(row.workDate)) continue;

        if (row.status == 'Present') {
          presentDays++;
        } else {
          lateDays++;
        }

        final date = parseWorkDateString(row.workDate);
        final dayEntries = entriesByDate[row.workDate] ?? const <TimeEntry>[];
        final worked = paidMinutesForDay(
          workedMinutesFromEntries(dayEntries),
          cap: paidMinutes,
        );
        totalWorkedMinutes += worked;

        if (date == null || dayEntries.isEmpty) continue;

        if (row.status == 'Late') {
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
          if (dailyRate > 0) {
            lateDeduction += minutes * minuteRate;
          }
        }

        final lastOut = latestClosedTimeOut(dayEntries);
        if (lastOut != null) {
          final earlyMinutes = earlyOutMinutesForClockOut(
            date: date,
            timeOut: lastOut,
            weeklySchedule: weeklySchedule,
            globalSchedule: globalSchedule,
          );
          totalEarlyOutMinutes += earlyMinutes;
          if (dailyRate > 0) {
            earlyOutDeduction += earlyMinutes * minuteRate;
          }
        }
      case 'Absent':
        if (!countedDates.add(row.workDate)) continue;
        absentDays++;
      case 'On Leave':
        if (!countedDates.add(row.workDate)) continue;
        excuseDays++;
      default:
        break;
    }
  }

  final payableDays = presentDays + lateDays;
  final basicPay = dailyRate > 0 ? dailyRate * payableDays : 0.0;
  const absentDeduction = 0.0;
  const excuseDeduction = 0.0;
  final other = otherDeductions < 0 ? 0.0 : otherDeductions;
  final adds = additions < 0 ? 0.0 : additions;
  final rawNet = basicPay -
      lateDeduction -
      earlyOutDeduction -
      absentDeduction -
      excuseDeduction -
      other +
      adds;
  final netPay = rawNet < 0 ? 0.0 : rawNet;

  return EmployeeSalaryBreakdown(
    employeeId: employeeId,
    employeeName: employeeName,
    dailyRate: dailyRate < 0 ? 0 : dailyRate,
    presentDays: presentDays,
    lateDays: lateDays,
    absentDays: absentDays,
    excuseDays: excuseDays,
    totalLateMinutes: totalLateMinutes,
    totalEarlyOutMinutes: totalEarlyOutMinutes,
    totalWorkedMinutes: totalWorkedMinutes,
    grossPay: basicPay,
    lateDeduction: lateDeduction,
    earlyOutDeduction: earlyOutDeduction,
    absentDeduction: absentDeduction,
    excuseDeduction: excuseDeduction,
    otherDeductions: other,
    additions: adds,
    netPay: netPay,
    hourlyRate: hourlyRate,
    minuteRate: minuteRate,
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
