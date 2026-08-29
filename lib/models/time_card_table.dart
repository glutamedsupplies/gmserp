import 'employee_time_card_profile.dart';
import 'leave_request.dart';
import 'time_card_schedule.dart';
import 'time_entry.dart';
import '../providers/time_entry_provider.dart';

export 'time_card_schedule.dart';
export 'employee_time_card_profile.dart';

enum TimeCardPeriodFilter {
  daily,
  last15Days,
  days16ToEnd,
  wholeMonth;

  String get label {
    switch (this) {
      case TimeCardPeriodFilter.daily:
        return 'Daily';
      case TimeCardPeriodFilter.last15Days:
        return '1–15';
      case TimeCardPeriodFilter.days16ToEnd:
        return '16–31';
      case TimeCardPeriodFilter.wholeMonth:
        return 'Whole month';
    }
  }
}

class TimeCardTableRow {
  const TimeCardTableRow({
    required this.workDate,
    required this.weekday,
    required this.sessionCount,
    required this.timeIn,
    required this.timeOut,
    required this.duration,
    required this.status,
    this.employeeId = '',
    this.employeeName = '',
    this.isToday = false,
    this.hasData = true,
  });

  final String workDate;
  final String weekday;
  final int sessionCount;
  final String timeIn;
  final String timeOut;
  final String duration;
  final String status;
  final String employeeId;
  final String employeeName;
  final bool isToday;
  final bool hasData;

  bool get hasEmployee => employeeName.trim().isNotEmpty;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdayLabel(DateTime date) => _weekdays[date.weekday - 1];

String monthYearLabel(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

/// Moves [date] by [months], clamping the day to the target month length.
DateTime shiftCalendarMonth(DateTime date, int months) {
  final target = DateTime(date.year, date.month + months);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  final day = date.day > lastDay ? lastDay : date.day;
  return DateTime(target.year, target.month, day);
}

String periodSubtitle(TimeCardPeriodFilter filter, DateTime now) {
  switch (filter) {
    case TimeCardPeriodFilter.daily:
      return formatWorkDate(now);
    case TimeCardPeriodFilter.last15Days:
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month, 15);
      return '${formatWorkDate(start)} – ${formatWorkDate(end)}';
    case TimeCardPeriodFilter.days16ToEnd:
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      if (lastDay < 16) {
        return monthYearLabel(now);
      }
      final start = DateTime(now.year, now.month, 16);
      final end = DateTime(now.year, now.month, lastDay);
      return '${formatWorkDate(start)} – ${formatWorkDate(end)}';
    case TimeCardPeriodFilter.wholeMonth:
      return monthYearLabel(now);
  }
}

List<DateTime> _datesForFilter(TimeCardPeriodFilter filter, DateTime now) {
  switch (filter) {
    case TimeCardPeriodFilter.daily:
      return [DateTime(now.year, now.month, now.day)];
    case TimeCardPeriodFilter.last15Days:
      return List.generate(
        15,
        (index) => DateTime(now.year, now.month, index + 1),
      );
    case TimeCardPeriodFilter.days16ToEnd:
      final lastDay = DateTime(now.year, now.month + 1, 0).day;
      if (lastDay < 16) return const [];
      return List.generate(
        lastDay - 15,
        (index) => DateTime(now.year, now.month, 16 + index),
      );
    case TimeCardPeriodFilter.wholeMonth:
      final last = DateTime(now.year, now.month + 1, 0);
      final days = last.day;
      return List.generate(
        days,
        (index) => DateTime(now.year, now.month, index + 1),
      );
  }
}

AttendanceStatus resolveAttendanceStatus({
  required DateTime date,
  required DateTime now,
  required List<TimeEntry> entries,
  required TimeCardSchedule schedule,
  required List<LeaveRequest> leaves,
  EmployeeWeeklySchedule? employeeSchedule,
}) {
  final workDate = formatWorkDate(date);
  final dayStart = DateTime(date.year, date.month, date.day);
  final todayStart = DateTime(now.year, now.month, now.day);

  if (hasLeaveOnDate(leaves: leaves, workDate: workDate)) {
    return AttendanceStatus.onLeave;
  }

  final isWorkDay = employeeSchedule != null
      ? employeeSchedule.isWorkDay(date)
      : schedule.workWeek.isWorkDay(date);

  if (!isWorkDay) {
    return AttendanceStatus.offDay;
  }

  final lateThreshold = employeeSchedule != null
      ? employeeSchedule.forDate(date).lateThresholdOn(date, 0)
      : schedule.lateThresholdOn(date);

  // Future work days have no attendance yet.
  if (dayStart.isAfter(todayStart)) {
    return AttendanceStatus.pending;
  }

  if (entries.isEmpty) {
    if (dayStart.isBefore(todayStart)) {
      return AttendanceStatus.absent;
    }
    // Today with no clock-in yet: absent only after late threshold.
    if (now.isAfter(lateThreshold)) {
      return AttendanceStatus.absent;
    }
    return AttendanceStatus.pending;
  }

  final sorted = [...entries]..sort((a, b) => a.timeIn.compareTo(b.timeIn));
  final firstIn = sorted.first.timeIn;
  if (firstIn.isAfter(lateThreshold)) {
    return AttendanceStatus.late;
  }
  return AttendanceStatus.present;
}

TimeCardTableRow _rowForDate({
  required DateTime date,
  required List<TimeEntry> entries,
  required DateTime now,
  required TimeCardPeriodFilter filter,
  required TimeCardSchedule schedule,
  required List<LeaveRequest> leaves,
  EmployeeWeeklySchedule? employeeSchedule,
  String employeeId = '',
  String employeeName = '',
}) {
  final workDate = formatWorkDate(date);
  final isToday = workDate == formatWorkDate(now);
  final status = resolveAttendanceStatus(
    date: date,
    now: now,
    entries: entries,
    schedule: schedule,
    leaves: leaves,
    employeeSchedule: employeeSchedule,
  );

  if (entries.isEmpty) {
    return TimeCardTableRow(
      workDate: workDate,
      weekday: weekdayLabel(date),
      sessionCount: 0,
      timeIn: '—',
      timeOut: '—',
      duration: '—',
      status: status.label,
      employeeId: employeeId,
      employeeName: employeeName,
      isToday: isToday,
      hasData: false,
    );
  }

  if (filter == TimeCardPeriodFilter.daily) {
    return _rowForSessions(
      workDate: workDate,
      date: date,
      entries: entries,
      now: now,
      isToday: isToday,
      status: status,
      employeeId: employeeId,
      employeeName: employeeName,
    );
  }

  final sorted = [...entries]..sort((a, b) => a.timeIn.compareTo(b.timeIn));
  final earliest = sorted.first.timeIn;
  final hasOpen = sorted.any((entry) => entry.isOpen);
  final closed = sorted.where((entry) => entry.timeOut != null).toList();
  final latestOut = hasOpen
      ? null
      : closed.isEmpty
          ? null
          : closed.map((e) => e.timeOut!).reduce(
                (a, b) => a.isAfter(b) ? a : b,
              );

  return TimeCardTableRow(
    workDate: workDate,
    weekday: weekdayLabel(date),
    sessionCount: entries.length,
    timeIn: formatClockTime(earliest),
    timeOut: hasOpen
        ? 'Active'
        : latestOut == null
            ? '—'
            : formatClockTime(latestOut),
    duration: formatDurationShort(sumEntriesDuration(entries, now)),
    status: status.label,
    employeeId: employeeId,
    employeeName: employeeName,
    isToday: isToday,
    hasData: true,
  );
}

TimeCardTableRow _rowForSessions({
  required String workDate,
  required DateTime date,
  required List<TimeEntry> entries,
  required DateTime now,
  required bool isToday,
  required AttendanceStatus status,
  String employeeId = '',
  String employeeName = '',
}) {
  final sorted = [...entries]..sort((a, b) => a.timeIn.compareTo(b.timeIn));
  final entry = sorted.first;
  return TimeCardTableRow(
    workDate: workDate,
    weekday: weekdayLabel(date),
    sessionCount: 1,
    timeIn: formatClockTime(entry.timeIn),
    timeOut: entry.timeOut == null ? 'Active' : formatClockTime(entry.timeOut!),
    duration: formatDurationShort(entryDuration(entry, now)),
    status: status.label,
    employeeId: employeeId,
    employeeName: employeeName,
    isToday: isToday,
    hasData: true,
  );
}

List<TimeCardTableRow> buildTimeCardTableRows({
  required List<TimeEntry> allEntries,
  required TimeCardPeriodFilter filter,
  required DateTime now,
  DateTime? viewDate,
  TimeCardSchedule schedule = TimeCardSchedule.defaults,
  List<LeaveRequest> leaves = const [],
  EmployeeWeeklySchedule? employeeSchedule,
}) {
  final grouped = groupEntriesByWorkDate(allEntries);
  final periodDate = viewDate ?? now;
  final dates = _datesForFilter(filter, periodDate);
  final rows = <TimeCardTableRow>[];

  if (filter == TimeCardPeriodFilter.daily) {
    final todayKey = formatWorkDate(periodDate);
    final todayEntries = grouped[todayKey] ?? [];
    final isViewingToday = todayKey == formatWorkDate(now);
    final status = resolveAttendanceStatus(
      date: dates.first,
      now: now,
      entries: todayEntries,
      schedule: schedule,
      leaves: leaves,
      employeeSchedule: employeeSchedule,
    );
    if (todayEntries.isEmpty) {
      rows.add(
        _rowForDate(
          date: dates.first,
          entries: const [],
          now: now,
          filter: filter,
          schedule: schedule,
          leaves: leaves,
          employeeSchedule: employeeSchedule,
        ),
      );
    } else {
      final sorted = [...todayEntries]
        ..sort((a, b) => a.timeIn.compareTo(b.timeIn));
      for (final entry in sorted) {
        rows.add(
          _rowForSessions(
            workDate: todayKey,
            date: dates.first,
            entries: [entry],
            now: now,
            isToday: isViewingToday,
            status: status,
          ),
        );
      }
    }
    return rows;
  }

  for (final date in dates) {
    final key = formatWorkDate(date);
    rows.add(
      _rowForDate(
        date: date,
        entries: grouped[key] ?? [],
        now: now,
        filter: filter,
        schedule: schedule,
        leaves: leaves,
        employeeSchedule: employeeSchedule,
      ),
    );
  }

  return rows;
}

Duration totalDurationForRows(
  List<TimeEntry> allEntries,
  TimeCardPeriodFilter filter,
  DateTime now, {
  DateTime? viewDate,
}) {
  final dates = _datesForFilter(filter, viewDate ?? now);
  if (dates.isEmpty) return Duration.zero;

  final rangeStart = DateTime(
    dates.first.year,
    dates.first.month,
    dates.first.day,
  );
  final rangeEnd = DateTime(
    dates.last.year,
    dates.last.month,
    dates.last.day,
    23,
    59,
    59,
    999,
  );

  return sumEntriesInRange(allEntries, rangeStart, rangeEnd, now);
}

class StaffTimeCardSource {
  const StaffTimeCardSource({
    required this.userId,
    required this.username,
    required this.entries,
    required this.leaves,
    this.weeklySchedule,
  });

  final String userId;
  final String username;
  final List<TimeEntry> entries;
  final List<LeaveRequest> leaves;
  final EmployeeWeeklySchedule? weeklySchedule;
}

/// Builds attendance rows for one or more staff members (admin view).
List<TimeCardTableRow> buildStaffTimeCardTableRows({
  required List<StaffTimeCardSource> staff,
  required TimeCardPeriodFilter filter,
  required DateTime now,
  DateTime? viewDate,
  TimeCardSchedule schedule = TimeCardSchedule.defaults,
}) {
  final rows = <TimeCardTableRow>[];
  final sortedStaff = [...staff]
    ..sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );

  for (final member in sortedStaff) {
    final memberRows = buildTimeCardTableRows(
      allEntries: member.entries,
      filter: filter,
      now: now,
      viewDate: viewDate,
      schedule: schedule,
      leaves: member.leaves,
      employeeSchedule: member.weeklySchedule,
    );
    for (final row in memberRows) {
      rows.add(
        TimeCardTableRow(
          workDate: row.workDate,
          weekday: row.weekday,
          sessionCount: row.sessionCount,
          timeIn: row.timeIn,
          timeOut: row.timeOut,
          duration: row.duration,
          status: row.status,
          employeeId: member.userId,
          employeeName: member.username,
          isToday: row.isToday,
          hasData: row.hasData,
        ),
      );
    }
  }

  rows.sort((a, b) {
    final byDate = a.workDate.compareTo(b.workDate);
    if (byDate != 0) return byDate;
    return a.employeeName.toLowerCase().compareTo(b.employeeName.toLowerCase());
  });
  return rows;
}
