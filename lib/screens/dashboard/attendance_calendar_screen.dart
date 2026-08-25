import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_table.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_card_settings_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../services/leave_reminder_service.dart';
import '../../services/leave_request_repository.dart';
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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected;
  List<LeaveRequest> _leaves = [];
  bool _loading = true;
  String? _error;
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _selected = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) {
      setState(() {
        _leaves = [];
        _loading = false;
        _error = company == null
            ? 'Select a company to view your attendance calendar.'
            : 'Sign in to view the calendar.';
        _loadedKey = null;
      });
      return;
    }

    final key = '${user.id}:${company.id}';
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
        _loading = false;
        _error = 'Unable to load calendar data.';
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

  AttendanceStatus _statusFor(
    DateTime day, {
    required Map<String, List<TimeEntry>> byDate,
  }) {
    final schedule = context.read<TimeCardSettingsProvider>().schedule;
    final entries = byDate[formatWorkDate(day)] ?? const <TimeEntry>[];
    return resolveAttendanceStatus(
      date: day,
      now: DateTime.now(),
      entries: entries,
      schedule: schedule,
      leaves: _leaves,
    );
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final company = context.watch<CompanyProvider>().selectedCompany;
    final timeEntries = context.watch<TimeEntryProvider>();
    final byDate = _entriesByDate(timeEntries.allEntries);
    final selected = _selected;
    final selectedStatus =
        selected == null ? null : _statusFor(selected, byDate: byDate);

    // Reload when company changes.
    final user = context.watch<AuthProvider>().user;
    final loadKey =
        user == null || company == null ? null : '${user.id}:${company.id}';
    if (loadKey != null && loadKey != _loadedKey && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(force: true));
    }

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Sunday-first grid: DateTime.weekday is Mon=1 … Sun=7.
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
            title: 'Attendance calendar',
            subtitle: company == null
                ? 'Select a company to see leave, present, late, and absent days.'
                : 'Your attendance for ${company.name}. Leave reminders arrive 1 day before.',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(force: true),
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: density.sectionGap),
          if (_loading && _loadedKey == null)
            const AppLoadingView(
              title: 'Loading calendar',
              message: 'Fetching attendance and leave…',
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
                                statusFor: (day) =>
                                    _statusFor(day, byDate: byDate),
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
            if (selected != null && selectedStatus != null)
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

  String _leaveNoteFor(DateTime day) {
    final key = formatWorkDate(day);
    final match = _leaves.where(
      (leave) => leave.isActiveLeave && leave.coversWorkDate(key),
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
        : '${out.hour.toString().padLeft(2, '0')}:${out.minute.toString().padLeft(2, '0')}';
    final inLabel =
        '${first.timeIn.hour.toString().padLeft(2, '0')}:${first.timeIn.minute.toString().padLeft(2, '0')}';
    return 'Time in $inLabel · Time out $outLabel · ${entries.length} session${entries.length == 1 ? '' : 's'}';
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
                    color: showDot
                        ? colorFor(status)
                        : Colors.transparent,
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
