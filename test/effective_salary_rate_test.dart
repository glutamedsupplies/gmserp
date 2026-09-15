import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/time_card_table.dart';
import 'package:new_gmserp/models/time_card_salary.dart';
import 'package:new_gmserp/models/time_entry.dart';

void main() {
  const history = {'0001-01-01': 450.0, '2026-09-16': 500.0};
  TimeCardTableRow row(int day, {String status = 'Present'}) =>
      TimeCardTableRow(
        workDate: '2026-09-${day.toString().padLeft(2, '0')}',
        weekday: 'Wed',
        sessionCount: 1,
        timeIn: '',
        timeOut: '',
        duration: '',
        status: status,
      );
  TimeEntry entry(int day, {int hour = 9}) => TimeEntry(
    id: '$day',
    userId: 'u',
    userEmail: '',
    username: 'Employee',
    companyId: 'c',
    companyDocumentId: 'c',
    companyName: 'Company',
    status: TimeEntryStatus.closed,
    workDate: row(day).workDate,
    timeIn: DateTime(2026, 9, day, hour),
    timeOut: DateTime(2026, 9, day, 18),
  );
  test('September 1–15 keeps 450; September 16 onward uses 500', () {
    final result = computeEmployeeSalaryBreakdown(
      employeeId: 'u',
      employeeName: 'Employee',
      dailyRate: 500,
      rateHistory: history,
      rows: [for (var d = 1; d <= 30; d++) row(d)],
      entries: [for (var d = 1; d <= 30; d++) entry(d)],
    );
    expect(result.basicPay, 15 * 450 + 15 * 500);
    expect(result.netPay, 14250);
    expect(result.appliedDailyRates, [450, 500]);
  });
  test('deductions use each day rate and duplicate rows do not double pay', () {
    final result = computeEmployeeSalaryBreakdown(
      employeeId: 'u',
      employeeName: 'Employee',
      dailyRate: 500,
      rateHistory: history,
      rows: [
        row(15, status: 'Late'),
        row(16, status: 'Late'),
        row(16, status: 'Late'),
      ],
      entries: [entry(15, hour: 10), entry(16, hour: 10)],
    );
    expect(result.basicPay, 950);
    expect(result.lateDeduction, closeTo(450 / 8 + 500 / 8, 0.001));
  });
  test('old period display and emergency pay retain historical rate', () {
    final result = computeEmployeeSalaryBreakdown(
      employeeId: 'u',
      employeeName: 'Employee',
      dailyRate: 500,
      rateHistory: history,
      rows: [row(15, status: 'Emergency')],
    );
    expect(result.dailyRate, 450);
    expect(result.basicPay, 450);
    expect(result.minuteRate, 450 / 480);
  });
  test(
    'history survives storage and future changes preserve earlier dates',
    () {
      final profile = EmployeeTimeCardProfile(
        dailyRate: 500,
        rateHistory: history,
        weeklySchedule: EmployeeWeeklySchedule.defaults(),
      );
      final loaded = EmployeeTimeCardProfile.fromStaffData(
        profile.toStaffFields(),
      );
      expect(loaded.rateOn('2026-09-15'), 450);
      expect(loaded.rateOn('2026-09-16'), 500);
      expect(loaded.rateOn('2026-10-01'), 500);
      expect(
        EmployeeTimeCardProfile.fromStaffData({'timeCardDailyRate': 450})
            .rateOn('2025-01-01'),
        450,
      );
    },
  );
}
