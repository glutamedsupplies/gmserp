import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/time_card_salary.dart';
import 'package:new_gmserp/models/time_card_schedule.dart';
import 'package:new_gmserp/models/time_card_table.dart';
import 'package:new_gmserp/models/time_entry.dart';

void main() {
  const schedule = TimeCardSchedule.defaults; // 9:00, lunch 12–13, 8h / 480 min

  group('lateMinutesForClockIn (lunch excluded)', () {
    test('on-time or early is 0', () {
      final date = DateTime(2026, 8, 26);
      expect(
        lateMinutesForClockIn(
          date: date,
          timeIn: DateTime(2026, 8, 26, 9, 0),
          globalSchedule: schedule,
        ),
        0,
      );
      expect(
        lateMinutesForClockIn(
          date: date,
          timeIn: DateTime(2026, 8, 26, 8, 45),
          globalSchedule: schedule,
        ),
        0,
      );
    });

    test('1:00 PM clock-in = 180 payable late minutes (not 240)', () {
      expect(
        lateMinutesForClockIn(
          date: DateTime(2026, 8, 26),
          timeIn: DateTime(2026, 8, 26, 13, 0),
          globalSchedule: schedule,
        ),
        180,
      );
    });

    test('2:00 PM clock-in = 240 payable late minutes', () {
      expect(
        lateMinutesForClockIn(
          date: DateTime(2026, 8, 26),
          timeIn: DateTime(2026, 8, 26, 14, 0),
          globalSchedule: schedule,
        ),
        240,
      );
    });

    test('90 minutes late before lunch is 90', () {
      expect(
        lateMinutesForClockIn(
          date: DateTime(2026, 8, 26),
          timeIn: DateTime(2026, 8, 26, 10, 30),
          globalSchedule: schedule,
        ),
        90,
      );
    });
  });

  group('earlyOutMinutesForClockOut (lunch excluded)', () {
    test('on-time or late out is 0', () {
      expect(
        earlyOutMinutesForClockOut(
          date: DateTime(2026, 8, 26),
          timeOut: DateTime(2026, 8, 26, 18, 0),
          globalSchedule: schedule,
        ),
        0,
      );
      expect(
        earlyOutMinutesForClockOut(
          date: DateTime(2026, 8, 26),
          timeOut: DateTime(2026, 8, 26, 18, 30),
          globalSchedule: schedule,
        ),
        0,
      );
    });

    test('5:00 PM clock-out = 60 payable early minutes', () {
      expect(
        earlyOutMinutesForClockOut(
          date: DateTime(2026, 8, 26),
          timeOut: DateTime(2026, 8, 26, 17, 0),
          globalSchedule: schedule,
        ),
        60,
      );
    });

    test('12:30 PM clock-out excludes remaining lunch', () {
      expect(
        earlyOutMinutesForClockOut(
          date: DateTime(2026, 8, 26),
          timeOut: DateTime(2026, 8, 26, 12, 30),
          globalSchedule: schedule,
        ),
        300, // 330 wall − 30 lunch left
      );
    });
  });

  group('daily / monthly pay formulas', () {
    TimeEntry entry({
      required DateTime timeIn,
      DateTime? timeOut,
    }) {
      final out = timeOut ??
          DateTime(timeIn.year, timeIn.month, timeIn.day, 18, 0);
      final workDate =
          '${timeIn.year.toString().padLeft(4, '0')}-'
          '${timeIn.month.toString().padLeft(2, '0')}-'
          '${timeIn.day.toString().padLeft(2, '0')}';
      return TimeEntry(
        id: 'e-${timeIn.millisecondsSinceEpoch}',
        userId: 'u1',
        userEmail: 'a@b.com',
        username: 'Alice',
        companyId: 'c1',
        companyDocumentId: 'c1',
        companyName: 'Co',
        status: TimeEntryStatus.closed,
        timeIn: timeIn,
        timeOut: out,
        workDate: workDate,
      );
    }

    TimeCardTableRow row({
      required String workDate,
      required String status,
    }) {
      return TimeCardTableRow(
        workDate: workDate,
        weekday: 'Mon',
        sessionCount: 1,
        timeIn: '—',
        timeOut: '—',
        duration: '—',
        status: status,
        employeeId: 'u1',
        employeeName: 'Alice',
        isToday: false,
        hasData: true,
      );
    }

    test('₱500 day, 90 min late → deduction 93.75, net 406.25', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [row(workDate: '2026-08-26', status: 'Late')],
        entries: [
          entry(timeIn: DateTime(2026, 8, 26, 10, 30)),
        ],
        globalSchedule: schedule,
      );

      expect(breakdown.hourlyRate, 62.5);
      expect(breakdown.minuteRate, closeTo(500 / 480, 1e-9));
      expect(breakdown.payableDays, 1);
      expect(breakdown.basicPay, 500);
      expect(breakdown.totalLateMinutes, 90);
      expect(breakdown.lateDeduction, closeTo(93.75, 1e-9));
      expect(breakdown.totalEarlyOutMinutes, 0);
      expect(breakdown.netPay, closeTo(406.25, 1e-9));
    });

    test('₱500 day, 60 min early out → deduction 62.50, net 437.50', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [row(workDate: '2026-08-26', status: 'Present')],
        entries: [
          entry(
            timeIn: DateTime(2026, 8, 26, 9, 0),
            timeOut: DateTime(2026, 8, 26, 17, 0),
          ),
        ],
        globalSchedule: schedule,
      );

      expect(breakdown.totalEarlyOutMinutes, 60);
      expect(breakdown.earlyOutDeduction, closeTo(62.5, 1e-9));
      expect(breakdown.netPay, closeTo(437.5, 1e-9));
    });

    test('late + early out both deduct from basic pay', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [row(workDate: '2026-08-26', status: 'Late')],
        entries: [
          entry(
            timeIn: DateTime(2026, 8, 26, 10, 30),
            timeOut: DateTime(2026, 8, 26, 17, 0),
          ),
        ],
        globalSchedule: schedule,
      );

      expect(breakdown.lateDeduction, closeTo(93.75, 1e-9));
      expect(breakdown.earlyOutDeduction, closeTo(62.5, 1e-9));
      expect(breakdown.netPay, closeTo(500 - 93.75 - 62.5, 1e-9));
    });

    test('open shift does not apply early-out deduction', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [row(workDate: '2026-08-26', status: 'Present')],
        entries: [
          TimeEntry(
            id: 'open',
            userId: 'u1',
            userEmail: 'a@b.com',
            username: 'Alice',
            companyId: 'c1',
            companyDocumentId: 'c1',
            companyName: 'Co',
            status: TimeEntryStatus.open,
            timeIn: DateTime(2026, 8, 26, 9, 0),
            timeOut: null,
            workDate: '2026-08-26',
          ),
        ],
        globalSchedule: schedule,
      );
      expect(breakdown.totalEarlyOutMinutes, 0);
      expect(breakdown.earlyOutDeduction, 0);
      expect(breakdown.netPay, 500);
    });

    test('monthly: basic = rate × payable days; net subtracts late', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [
          for (var d = 1; d <= 26; d++)
            row(
              workDate:
                  '2026-08-${d.toString().padLeft(2, '0')}',
              status: d == 1 ? 'Late' : 'Present',
            ),
        ],
        entries: [
          entry(timeIn: DateTime(2026, 8, 1, 10, 30)),
          for (var d = 2; d <= 26; d++)
            entry(timeIn: DateTime(2026, 8, d, 9, 0)),
        ],
        globalSchedule: schedule,
      );

      expect(breakdown.payableDays, 26);
      expect(breakdown.basicPay, 13000);
      expect(breakdown.totalLateMinutes, 90);
      expect(breakdown.lateDeduction, closeTo(93.75, 1e-9));
      expect(breakdown.totalEarlyOutMinutes, 0);
      expect(breakdown.netPay, closeTo(13000 - 93.75, 1e-9));
    });

    test('net pay never goes below 0', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [row(workDate: '2026-08-26', status: 'Late')],
        entries: [
          entry(
            timeIn: DateTime(2026, 8, 26, 18, 0),
            timeOut: DateTime(2026, 8, 26, 18, 1),
          ),
        ],
        globalSchedule: schedule,
      );
      expect(breakdown.netPay, greaterThanOrEqualTo(0));
    });

    test('daily filter multi-session rows do not double-count payable days', () {
      final breakdown = computeEmployeeSalaryBreakdown(
        employeeId: 'u1',
        employeeName: 'Alice',
        dailyRate: 500,
        rows: [
          row(workDate: '2026-08-26', status: 'Present'),
          row(workDate: '2026-08-26', status: 'Present'),
        ],
        entries: [
          entry(
            timeIn: DateTime(2026, 8, 26, 9, 0),
            timeOut: DateTime(2026, 8, 26, 12, 0),
          ),
          entry(
            timeIn: DateTime(2026, 8, 26, 13, 0),
            timeOut: DateTime(2026, 8, 26, 18, 0),
          ),
        ],
        globalSchedule: schedule,
      );
      expect(breakdown.payableDays, 1);
      expect(breakdown.basicPay, 500);
      expect(breakdown.totalEarlyOutMinutes, 0);
      expect(breakdown.netPay, 500);
    });

    test('formatMoney uses 2 decimals and thousands separators', () {
      expect(EmployeeSalaryBreakdown.formatMoney(500), '₱500.00');
      expect(EmployeeSalaryBreakdown.formatMoney(13000), '₱13,000.00');
      expect(
        EmployeeSalaryBreakdown.formatMoney(338.54, showMinus: true),
        '-₱338.54',
      );
    });
  });
}

