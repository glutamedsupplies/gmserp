import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/company_model.dart';
import '../../models/leave_request.dart';
import '../../models/staff_assignment.dart';
import '../../models/time_card_table.dart';
import '../../models/time_entry.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_card_settings_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../services/leave_reminder_service.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_entry_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class AttendanceCalendarScreen extends StatefulWidget {
  const AttendanceCalendarScreen({super.key});

  @override
  State<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState extends State<AttendanceCalendarScreen> {
  final _leaveRepo = LeaveRequestRepository();
  final _timeEntriesRepo = TimeEntryRepository();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;
  List<LeaveRequest> _leaves = [];
  List<TimeEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String? _loadedKey;

  /// Super Admin / Admin: selected company document id.
  String? _companyId;

  /// Super Admin / Admin: selected employee user id. `null` = all employees.
  String? _employeeId;

  /// Full company datasets for manager "All employees" day breakdown.
  List<TimeEntry> _companyEntries = [];
  List<LeaveRequest> _companyLeaves = [];

  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  bool get _isManager {
    final role = context.read<AuthProvider>().user?.role;
    return role == UserRole.admin || role == UserRole.superAdmin;
  }

  bool get _isSuperAdmin =>
      context.read<AuthProvider>().user?.role == UserRole.superAdmin;

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    context.read<TimeCardSettingsProvider>().ensureLoaded();
    final auth = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();

    if (auth?.role == UserRole.superAdmin) {
      await companies.loadCompanies();
      if (!mounted) return;
      final initial = companies.selectedCompany?.id ??
          (companies.companies.isNotEmpty ? companies.companies.first.id : null);
      if (initial != null) {
        await _selectCompany(initial);
      } else {
        setState(() {
          _loading = false;
          _error = 'No companies yet. Create a company first.';
        });
      }
      return;
    }

    if (auth?.role == UserRole.admin) {
      final company = companies.selectedCompany;
      if (company == null) {
        setState(() {
          _loading = false;
          _error = 'Select a company to view employee schedules.';
        });
        return;
      }
      _companyId = company.id;
      await companies.loadStaff(company.id);
      if (!mounted) return;
      // Default to all employees.
      _employeeId = null;
      await _load(force: true);
      return;
    }

    await _load(force: true);
  }

  List<StaffAssignment> _employeeStaff(CompanyProvider companies) {
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final role = companies.userById(member.userId)?.role;
      return role == UserRole.employee;
    }).toList();
  }

  CompanyModel? _activeCompany(CompanyProvider companies) {
    if (_isSuperAdmin) {
      final id = _companyId;
      if (id == null) return null;
      for (final company in companies.companies) {
        if (company.id == id) return company;
      }
      return null;
    }
    return companies.selectedCompany;
  }

  StaffAssignment? _selectedStaff(CompanyProvider companies) {
    final id = _employeeId;
    if (id == null) return null;
    for (final member in companies.staff) {
      if (member.userId == id) return member;
    }
    return null;
  }

  Future<void> _selectCompany(String companyId) async {
    CompanyModel? company;
    for (final item in context.read<CompanyProvider>().companies) {
      if (item.id == companyId) {
        company = item;
        break;
      }
    }

    setState(() {
      _companyId = companyId;
      _employeeId = null; // All employees
      _loadedKey = null;
      _leaves = [];
      _entries = [];
      _companyEntries = [];
      _companyLeaves = [];
    });

    final companies = context.read<CompanyProvider>();
    companies.loadUsers();
    await companies.loadStaff(companyId);
    if (!mounted) return;

    await _load(
      force: true,
      companyDocumentId: company?.firestoreId,
    );
  }

  Future<void> _selectEmployee(String? employeeId) async {
    setState(() {
      _employeeId = employeeId;
      _loadedKey = null;
    });
    await _load(force: true);
  }

  Future<void> _load({bool force = false, String? companyDocumentId}) async {
    final user = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();
    if (user == null) {
      setState(() {
        _leaves = [];
        _entries = [];
        _loading = false;
        _error = 'Sign in to view the calendar.';
        _loadedKey = null;
      });
      return;
    }

    final manager = user.role == UserRole.admin ||
        user.role == UserRole.superAdmin;

    if (!manager) {
      final company = companies.selectedCompany;
      if (company == null) {
        setState(() {
          _leaves = [];
          _entries = [];
          _loading = false;
          _error = 'Select a company to view your attendance calendar.';
          _loadedKey = null;
        });
        return;
      }

      final key = 'self:${user.id}:${company.id}';
      if (!force && _loadedKey == key && !_loading) return;

      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        context.read<TimeCardSettingsProvider>().ensureLoaded();
        await context.read<TimeEntryProvider>().loadDetailsForCompany(
              user: user,
              company: company,
            );
        final leaves = await _leaveRepo.listForUserCompany(
          userId: user.id,
          companyId: company.id,
        );
        if (!mounted) return;
        setState(() {
          _leaves = leaves;
          _entries = context.read<TimeEntryProvider>().allEntries;
          _loading = false;
          _loadedKey = key;
        });
        await LeaveReminderService.instance.syncUpcomingLeaveReminders(
          userId: user.id,
          leaves: leaves,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _leaves = [];
          _entries = [];
          _loading = false;
          _error = 'Unable to load calendar data.';
        });
      }
      return;
    }

    // Admin / Super Admin: company schedules (one employee or all).
    final company = _activeCompany(companies);
    if (company == null) {
      setState(() {
        _leaves = [];
        _entries = [];
        _companyEntries = [];
        _companyLeaves = [];
        _loading = false;
        _error = 'Select a company to view employee schedules.';
        _loadedKey = null;
      });
      return;
    }

    final staff = _employeeStaff(companies);
    if (staff.isEmpty) {
      setState(() {
        _leaves = [];
        _entries = [];
        _companyEntries = [];
        _companyLeaves = [];
        _loading = false;
        _error = 'No employees in this company yet.';
        _loadedKey = null;
      });
      return;
    }

    final employeeId = _employeeId;
    final key = 'mgr:${company.id}:${employeeId ?? 'all'}';
    if (!force && _loadedKey == key && !_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      context.read<TimeCardSettingsProvider>().ensureLoaded();
      final results = await Future.wait([
        _timeEntriesRepo.listByCompanyId(
          company.id,
          companyDocumentId: companyDocumentId ?? company.firestoreId,
        ),
        _leaveRepo.listByCompanyId(company.id),
      ]);
      if (!mounted) return;

      final allEntries = results[0] as List<TimeEntry>;
      final allLeaves = results[1] as List<LeaveRequest>;

      setState(() {
        _companyEntries = allEntries;
        _companyLeaves = allLeaves;
        if (employeeId == null) {
          _entries = allEntries;
          _leaves = allLeaves;
        } else {
          _entries =
              allEntries.where((e) => e.userId == employeeId).toList();
          _leaves =
              allLeaves.where((l) => l.userId == employeeId).toList();
        }
        _loading = false;
        _loadedKey = key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leaves = [];
        _entries = [];
        _companyEntries = [];
        _companyLeaves = [];
        _loading = false;
        _error = 'Unable to load employee schedule.';
      });
    }
  }

  Map<String, List<TimeEntry>> _entriesByDate(List<TimeEntry> all) {
    final map = <String, List<TimeEntry>>{};
    for (final entry in all) {
      map.putIfAbsent(entry.workDate, () => []).add(entry);
    }
    return map;
  }

  EmployeeWeeklySchedule? _employeeSchedule(CompanyProvider companies) {
    if (!_isManager || _employeeId == null) return null;
    return _selectedStaff(companies)?.timeCardProfile.weeklySchedule;
  }

  AttendanceStatus _statusForEmployee(
    DateTime day, {
    required StaffAssignment member,
    required Map<String, List<TimeEntry>> companyByDate,
  }) {
    final schedule = context.read<TimeCardSettingsProvider>().schedule;
    final workDate = formatWorkDate(day);
    final entries = (companyByDate[workDate] ?? const <TimeEntry>[])
        .where((e) => e.userId == member.userId)
        .toList();
    final leaves =
        _companyLeaves.where((l) => l.userId == member.userId).toList();
    return resolveAttendanceStatus(
      date: day,
      now: DateTime.now(),
      entries: entries,
      schedule: schedule,
      leaves: leaves,
      employeeSchedule: member.timeCardProfile.weeklySchedule,
    );
  }

  AttendanceStatus _statusFor(
    DateTime day, {
    required Map<String, List<TimeEntry>> byDate,
    required EmployeeWeeklySchedule? employeeSchedule,
    required List<StaffAssignment> staffList,
    required Map<String, List<TimeEntry>> companyByDate,
  }) {
    // All employees: show the most severe status among staff for calendar dots.
    if (_isManager && _employeeId == null) {
      return _aggregateStatusForDay(
        day,
        staffList: staffList,
        companyByDate: companyByDate,
      );
    }

    final schedule = context.read<TimeCardSettingsProvider>().schedule;
    final entries = byDate[formatWorkDate(day)] ?? const <TimeEntry>[];
    return resolveAttendanceStatus(
      date: day,
      now: DateTime.now(),
      entries: entries,
      schedule: schedule,
      leaves: _leaves,
      employeeSchedule: employeeSchedule,
    );
  }

  AttendanceStatus _aggregateStatusForDay(
    DateTime day, {
    required List<StaffAssignment> staffList,
    required Map<String, List<TimeEntry>> companyByDate,
  }) {
    if (staffList.isEmpty) return AttendanceStatus.pending;
    var best = AttendanceStatus.offDay;
    for (final member in staffList) {
      final status = _statusForEmployee(
        day,
        member: member,
        companyByDate: companyByDate,
      );
      if (_statusSeverity(status) > _statusSeverity(best)) {
        best = status;
      }
    }
    return best;
  }

  int _statusSeverity(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.absent:
        return 5;
      case AttendanceStatus.late:
        return 4;
      case AttendanceStatus.onLeave:
        return 3;
      case AttendanceStatus.present:
        return 2;
      case AttendanceStatus.pending:
        return 1;
      case AttendanceStatus.offDay:
        return 0;
    }
  }

  List<_EmployeeDayRow> _employeeRowsForDay(
    DateTime day, {
    required List<StaffAssignment> staffList,
    required Map<String, List<TimeEntry>> companyByDate,
  }) {
    final workDate = formatWorkDate(day);
    return [
      for (final member in staffList)
        _EmployeeDayRow(
          member: member,
          status: _statusForEmployee(
            day,
            member: member,
            companyByDate: companyByDate,
          ),
          scheduleLabel:
              member.timeCardProfile.weeklySchedule.forDate(day).rangeLabel,
          leaveNote: _leaveNoteForUser(day, member.userId),
          sessions: (companyByDate[workDate] ?? const <TimeEntry>[])
              .where((e) => e.userId == member.userId)
              .toList(),
        ),
    ];
  }

  Color _statusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return AppColors.success;
      case AttendanceStatus.late:
        return const Color(0xFFD97706);
      case AttendanceStatus.absent:
        return AppColors.error;
      case AttendanceStatus.onLeave:
        return const Color(0xFF2563EB);
      case AttendanceStatus.offDay:
        return AppColors.of(context).textHint;
      case AttendanceStatus.pending:
        return AppColors.of(context).border;
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  String _subtitle({
    required bool manager,
    required CompanyModel? company,
    required StaffAssignment? staff,
  }) {
    if (!manager) {
      return company == null
          ? 'Select a company to see leave, present, late, and absent days.'
          : 'Your attendance for ${company.name}. Leave reminders arrive 1 day before.';
    }
    if (company == null) {
      return 'Select a company to browse employee schedules.';
    }
    if (_employeeId == null) {
      return 'All employees · ${company.name}. Tap a date to see everyone’s status.';
    }
    if (staff == null) {
      return 'Attendance calendar for ${company.name}.';
    }
    return '${staff.username} · ${company.name}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final companies = context.watch<CompanyProvider>();
    final user = context.watch<AuthProvider>().user;
    final manager = user?.role == UserRole.admin ||
        user?.role == UserRole.superAdmin;
    final isSuperAdmin = user?.role == UserRole.superAdmin;
    final company = manager
        ? _activeCompany(companies)
        : companies.selectedCompany;
    final staffList = manager ? _employeeStaff(companies) : const <StaffAssignment>[];
    final selectedStaff = manager ? _selectedStaff(companies) : null;
    final employeeSchedule = _employeeSchedule(companies);
    final byDate = _entriesByDate(_entries);
    final companyByDate = _entriesByDate(_companyEntries);
    final viewingAllEmployees = manager && _employeeId == null;
    final selected = _selected;
    final selectedStatus = selected == null
        ? null
        : _statusFor(
            selected,
            byDate: byDate,
            employeeSchedule: employeeSchedule,
            staffList: staffList,
            companyByDate: companyByDate,
          );
    final allEmployeeRows = (manager &&
            viewingAllEmployees &&
            selected != null)
        ? _employeeRowsForDay(
            selected,
            staffList: staffList,
            companyByDate: companyByDate,
          )
        : const <_EmployeeDayRow>[];

    // Keep a specific employee filter valid when staff list changes.
    if (manager &&
        _employeeId != null &&
        staffList.isNotEmpty &&
        !staffList.any((m) => m.userId == _employeeId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectEmployee(null);
      });
    }

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = firstOfMonth.weekday % 7;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return DashboardScaffold(
      title: 'Calendar',
      currentRoute: AppRoutes.timeCardCalendar,
      child: ListView(
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: manager ? 'Employee schedules' : 'Attendance calendar',
            subtitle: _subtitle(
              manager: manager,
              company: company,
              staff: selectedStaff,
            ),
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: density.sectionGap),
          if (manager) ...[
            if (isSuperAdmin)
              _CalendarDropdownShell(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _companyId != null &&
                            companies.companies.any((c) => c.id == _companyId)
                        ? _companyId
                        : null,
                    isExpanded: true,
                    isDense: density.compact,
                    style: density.compact
                        ? Theme.of(context).textTheme.bodySmall
                        : Theme.of(context).textTheme.bodyMedium,
                    hint: const Text('Select company'),
                    items: [
                      for (final item in ([...companies.companies]
                        ..sort((a, b) =>
                            a.name.toLowerCase().compareTo(b.name.toLowerCase()))))
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            '${item.name}  •  ${item.companyId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) _selectCompany(id);
                    },
                  ),
                ),
              ),
            if (isSuperAdmin) SizedBox(height: density.sectionGap),
            _CalendarDropdownShell(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _employeeId != null &&
                          staffList.any((m) => m.userId == _employeeId)
                      ? _employeeId
                      : null,
                  isExpanded: true,
                  isDense: density.compact,
                  style: density.compact
                      ? Theme.of(context).textTheme.bodySmall
                      : Theme.of(context).textTheme.bodyMedium,
                  hint: const Text('All employees'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All employees'),
                    ),
                    for (final member in staffList)
                      DropdownMenuItem<String?>(
                        value: member.userId,
                        child: Text(
                          member.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _selectEmployee,
                ),
              ),
            ),
            SizedBox(height: density.sectionGap),
          ],
          if (_loading && _loadedKey == null)
            AppLoadingView(
              title: 'Loading calendar',
              message: manager
                  ? 'Fetching employee schedule…'
                  : 'Fetching attendance and leave…',
            )
          else if (_error != null)
            _MessageCard(message: _error!)
          else ...[
            Container(
              padding: density.cardPadding,
              decoration: compactCardDecoration(context),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => _shiftMonth(-1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Expanded(
                        child: Text(
                          monthYearLabel(_month),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => _shiftMonth(1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final label in const [
                        'Sun',
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                      ])
                        Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var row = 0; row < rows; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: _DayCell(
                                dayIndex: row * 7 + col,
                                leading: leading,
                                daysInMonth: daysInMonth,
                                month: _month,
                                selected: selected,
                                statusFor: (day) => _statusFor(
                                  day,
                                  byDate: byDate,
                                  employeeSchedule: employeeSchedule,
                                  staffList: staffList,
                                  companyByDate: companyByDate,
                                ),
                                colorFor: _statusColor,
                                onTap: (day) =>
                                    setState(() => _selected = day),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: density.sectionGap),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _LegendDot(color: AppColors.success, label: 'Present'),
                _LegendDot(color: const Color(0xFFD97706), label: 'Late'),
                _LegendDot(color: AppColors.error, label: 'Absent'),
                _LegendDot(color: const Color(0xFF2563EB), label: 'Leave'),
                _LegendDot(color: colors.textHint, label: 'Off'),
              ],
            ),
            SizedBox(height: density.sectionGap),
            if (selected != null && viewingAllEmployees)
              _AllEmployeesDayPanel(
                day: selected,
                rows: allEmployeeRows,
                colorFor: _statusColor,
                sessionsNote: _sessionsNote,
              )
            else if (selected != null && selectedStatus != null)
              Container(
                width: double.infinity,
                padding: density.cardPadding,
                decoration: compactCardDecoration(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${weekdayLabel(selected)} · ${formatWorkDate(selected)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    SizedBox(height: density.titleSubtitleGap),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _statusColor(selectedStatus),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          selectedStatus.label == '—'
                              ? 'No status yet'
                              : selectedStatus.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (manager && selectedStaff != null) ...[
                      SizedBox(height: density.cardGap),
                      Text(
                        _scheduleNote(selected, selectedStaff),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                    if (selectedStatus == AttendanceStatus.onLeave) ...[
                      SizedBox(height: density.cardGap),
                      Text(
                        _leaveNoteFor(selected),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                    if ((byDate[formatWorkDate(selected)] ?? const [])
                        .isNotEmpty) ...[
                      SizedBox(height: density.cardGap),
                      Text(
                        _sessionsNote(byDate[formatWorkDate(selected)]!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _scheduleNote(DateTime day, StaffAssignment staff) {
    final daySchedule = staff.timeCardProfile.weeklySchedule.forDate(day);
    return 'Scheduled: ${daySchedule.rangeLabel}';
  }

  String _leaveNoteFor(DateTime day) {
    final id = _employeeId;
    if (id == null) return 'Marked as leave.';
    return _leaveNoteForUser(day, id);
  }

  String _leaveNoteForUser(DateTime day, String userId) {
    final key = formatWorkDate(day);
    final source =
        _companyLeaves.isNotEmpty ? _companyLeaves : _leaves;
    final match = source.where(
      (leave) =>
          leave.userId == userId &&
          leave.isActiveLeave &&
          leave.coversWorkDate(key),
    );
    if (match.isEmpty) return 'Marked as leave.';
    final leave = match.first;
    final range = leave.startDate == leave.endDate
        ? leave.startDate
        : '${leave.startDate} → ${leave.endDate}';
    final reason = leave.reason.trim().isEmpty ? 'Leave' : leave.reason.trim();
    return '$reason · $range (${leave.status})';
  }

  String _sessionsNote(List<TimeEntry> entries) {
    final sorted = [...entries]..sort((a, b) => a.timeIn.compareTo(b.timeIn));
    final first = sorted.first;
    final last = sorted.last;
    final out = last.timeOut;
    final outLabel = out == null
        ? 'in progress'
        : formatClockTime(out, withSeconds: false);
    final inLabel = formatClockTime(first.timeIn, withSeconds: false);
    return 'Time in $inLabel · Time out $outLabel · ${entries.length} session${entries.length == 1 ? '' : 's'}';
  }
}

class _CalendarDropdownShell extends StatelessWidget {
  const _CalendarDropdownShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      height: density.filterHeight,
      padding: EdgeInsets.symmetric(horizontal: density.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayIndex,
    required this.leading,
    required this.daysInMonth,
    required this.month,
    required this.selected,
    required this.statusFor,
    required this.colorFor,
    required this.onTap,
  });

  final int dayIndex;
  final int leading;
  final int daysInMonth;
  final DateTime month;
  final DateTime? selected;
  final AttendanceStatus Function(DateTime day) statusFor;
  final Color Function(AttendanceStatus status) colorFor;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final dayNum = dayIndex - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(month.year, month.month, dayNum);
    final status = statusFor(day);
    final isSelected = selected != null &&
        selected!.year == day.year &&
        selected!.month == day.month &&
        selected!.day == day.day;
    final isToday = formatWorkDate(day) == formatWorkDate(DateTime.now());
    final colors = AppColors.of(context);
    final showDot = status == AttendanceStatus.present ||
        status == AttendanceStatus.late ||
        status == AttendanceStatus.absent ||
        status == AttendanceStatus.onLeave;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.22)
            : colors.inputFill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(day),
          child: SizedBox(
            height: 44,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNum',
                  style: TextStyle(
                    fontWeight: isToday || isSelected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    fontSize: 13,
                    color: isToday
                        ? AppColors.primaryDark
                        : colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: showDot ? colorFor(status) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      width: double.infinity,
      padding: density.cardPadding,
      decoration: compactCardDecoration(context),
      child: Text(
        message,
        style: TextStyle(
          color: colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmployeeDayRow {
  const _EmployeeDayRow({
    required this.member,
    required this.status,
    required this.scheduleLabel,
    required this.leaveNote,
    required this.sessions,
  });

  final StaffAssignment member;
  final AttendanceStatus status;
  final String scheduleLabel;
  final String leaveNote;
  final List<TimeEntry> sessions;
}

class _AllEmployeesDayPanel extends StatelessWidget {
  const _AllEmployeesDayPanel({
    required this.day,
    required this.rows,
    required this.colorFor,
    required this.sessionsNote,
  });

  final DateTime day;
  final List<_EmployeeDayRow> rows;
  final Color Function(AttendanceStatus status) colorFor;
  final String Function(List<TimeEntry> entries) sessionsNote;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);

    return Container(
      width: double.infinity,
      padding: density.cardPadding,
      decoration: compactCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weekdayLabel(day)} · ${formatWorkDate(day)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          SizedBox(height: density.titleSubtitleGap),
          Text(
            rows.isEmpty
                ? 'No employees in this company.'
                : '${rows.length} employee${rows.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (rows.isNotEmpty) ...[
            SizedBox(height: density.cardGap),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) ...[
                SizedBox(height: density.cardGap),
                Divider(height: 1, color: colors.border),
                SizedBox(height: density.cardGap),
              ],
              _EmployeeDayTile(
                row: rows[i],
                colorFor: colorFor,
                sessionsNote: sessionsNote,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmployeeDayTile extends StatelessWidget {
  const _EmployeeDayTile({
    required this.row,
    required this.colorFor,
    required this.sessionsNote,
  });

  final _EmployeeDayRow row;
  final Color Function(AttendanceStatus status) colorFor;
  final String Function(List<TimeEntry> entries) sessionsNote;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final statusLabel =
        row.status.label == '—' ? 'No status yet' : row.status.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colorFor(row.status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.member.username,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        SizedBox(height: density.titleSubtitleGap),
        Text(
          'Scheduled: ${row.scheduleLabel}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
        if (row.status == AttendanceStatus.onLeave) ...[
          SizedBox(height: density.titleSubtitleGap),
          Text(
            row.leaveNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
        if (row.sessions.isNotEmpty) ...[
          SizedBox(height: density.titleSubtitleGap),
          Text(
            sessionsNote(row.sessions),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ],
    );
  }
}
