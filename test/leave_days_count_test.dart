import 'package:flutter_test/flutter_test.dart';
import 'package:new_gmserp/models/leave_request.dart';
import 'package:new_gmserp/models/time_card_table.dart';

LeaveRequest _leave({
  required String userId,
  required String start,
  required String end,
  String status = 'approved',
}) {
  return LeaveRequest(
    id: '$userId-$start',
    userId: userId,
    companyId: 'c1',
    companyDocumentId: 'c1',
    companyName: 'Co',
    username: 'User',
    userEmail: 'user@test.com',
    reason: 'Vacation',
    startDate: start,
    endDate: end,
    status: status,
  );
}

void main() {
  test('totalApprovedLeaveDaysForUser counts unique days in year', () {
    final leaves = [
      _leave(userId: 'u1', start: '2026-01-02', end: '2026-01-03'),
      _leave(userId: 'u1', start: '2026-01-03', end: '2026-01-04'),
      _leave(userId: 'u2', start: '2026-01-05', end: '2026-01-05'),
      _leave(userId: 'u1', start: '2025-12-30', end: '2026-01-01'),
    ];

    expect(
      totalApprovedLeaveDaysForUser(
        leaves: leaves,
        userId: 'u1',
        year: 2026,
      ),
      4,
    );
  });

  test('leaveDaysInTableRows counts on-leave rows in period', () {
    const rows = [
      TimeCardTableRow(
        workDate: '2026-03-01',
        weekday: 'Sun',
        sessionCount: 0,
        timeIn: '—',
        timeOut: '—',
        duration: '—',
        status: 'On Leave',
        employeeId: 'u1',
      ),
      TimeCardTableRow(
        workDate: '2026-03-02',
        weekday: 'Mon',
        sessionCount: 0,
        timeIn: '—',
        timeOut: '—',
        duration: '—',
        status: 'On Leave',
        employeeId: 'u1',
      ),
      TimeCardTableRow(
        workDate: '2026-03-03',
        weekday: 'Tue',
        sessionCount: 1,
        timeIn: '9:00 AM',
        timeOut: '6:00 PM',
        duration: '8h',
        status: 'Present',
        employeeId: 'u1',
      ),
    ];

    expect(leaveDaysInTableRows(rows, employeeId: 'u1'), 2);
  });
}
