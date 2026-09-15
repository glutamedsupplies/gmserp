import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/employee_day_schedule_override.dart';
import 'package:new_gmserp/models/leave_request.dart';
import 'package:new_gmserp/models/time_card_salary.dart';
import 'package:new_gmserp/models/time_card_table.dart';

void main() {
  const override = EmployeeDayScheduleOverride(
    id: 'override',
    userId: 'u',
    companyId: 'c',
    companyDocumentId: 'c',
    workDate: '2026-08-29',
    isDayOff: false,
    isRegularWorkDay: true,
  );
  const leave = LeaveRequest(
    id: 'leave',
    userId: 'u',
    companyId: 'c',
    companyDocumentId: 'c',
    companyName: 'Company',
    username: 'Employee',
    userEmail: '',
    reason: '',
    startDate: '2026-08-28',
    endDate: '2026-08-30',
    status: 'approved',
  );
  final date = DateTime(2026, 8, 29, 9);

  test(
    'regular day replaces leave and weekly day off without adding attendance',
    () {
      expect(
        resolveAttendanceStatus(
          date: date,
          now: DateTime(2026, 8, 30),
          entries: [],
          schedule: TimeCardSchedule.defaults,
          leaves: [leave],
          dayOverrides: [override],
          employeeId: 'u',
        ),
        AttendanceStatus.absent,
      );
      expect(
        clockInBlockReasonFor(
          at: date,
          leaves: [leave],
          dayOverrides: [override],
          employeeId: 'u',
        ),
        isNull,
      );
      expect(
        clockInBlockReasonFor(
          at: DateTime(2026, 8, 29, 7),
          leaves: [leave],
          dayOverrides: [override],
          employeeId: 'u',
        ),
        ClockInBlockReason.tooEarly,
      );
    },
  );

  test(
    'restoring one date preserves other leave dates and employee restrictions',
    () {
      expect(
        totalApprovedLeaveDaysForUser(
          leaves: [leave],
          userId: 'u',
          dayOverrides: [override],
        ),
        2,
      );
      expect(
        clockInBlockReasonFor(
          at: DateTime(2026, 8, 28, 9),
          leaves: [leave],
          dayOverrides: [override],
          employeeId: 'u',
        ),
        ClockInBlockReason.onLeave,
      );
      expect(
        clockInBlockReasonFor(
          at: date,
          dayOverrides: [override],
          employeeId: 'another',
        ),
        ClockInBlockReason.dayOff,
      );
    },
  );

  test(
    'regular day flag survives storage and defaults to false for old records',
    () {
      expect(
        EmployeeDayScheduleOverride.fromFirestore(
          id: override.id,
          data: override.toFirestore(),
        ).isRegularWorkDay,
        isTrue,
      );
      expect(
        EmployeeDayScheduleOverride.fromFirestore(
          id: 'old',
          data: {'isDayOff': true},
        ).isRegularWorkDay,
        isFalse,
      );
    },
  );
}
