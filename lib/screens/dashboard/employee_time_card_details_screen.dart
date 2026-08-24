import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/company_model.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_table.dart';
import '../../models/time_card_salary.dart';
import '../../models/time_entry.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_card_settings_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_entry_repository.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/time_card_month_filter.dart';
import '../../widgets/time_card_report_table.dart';
import 'time_card_png_preview_screen.dart';

class EmployeeTimeCardDetailsScreen extends StatefulWidget {
  const EmployeeTimeCardDetailsScreen({super.key});

  @override
  State<EmployeeTimeCardDetailsScreen> createState() =>
      _EmployeeTimeCardDetailsScreenState();
}

class _EmployeeTimeCardDetailsScreenState
    extends State<EmployeeTimeCardDetailsScreen> {
  Timer? _refreshTimer;
  DateTime _now = DateTime.now();
  String? _loadedKey;
  bool _summaryExpanded = false;
  TimeCardPeriodFilter _periodFilter = TimeCardPeriodFilter.wholeMonth;
  DateTime _viewDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  List<LeaveRequest> _leaves = [];
  final _leaveRepository = LeaveRequestRepository();
  final _timeEntryRepository = TimeEntryRepository();

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadIfReady() async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;

    final key = '${user.id}:${company.id}';
    if (_loadedKey == key) return;
    _loadedKey = key;

    context.read<TimeCardSettingsProvider>().ensureLoaded();
    context.read<TimeEntryProvider>().loadDetailsForCompany(
          user: user,
          company: company,
        );

    try {
      final leaves = await _leaveRepository.listForUserCompany(
        userId: user.id,
        companyId: company.id,
      );
      if (!mounted || _loadedKey != key) return;
      setState(() => _leaves = leaves);
    } catch (_) {
      if (!mounted || _loadedKey != key) return;
      setState(() => _leaves = []);
    }
  }

  void _openPngPreview({
    required UserModel user,
    required CompanyModel company,
    required List<TimeCardTableRow> rows,
    required String totalHours,
    required double dailyRate,
    required List<TimeEntry> entries,
    EmployeeWeeklySchedule? weeklySchedule,
    required TimeCardSchedule globalSchedule,
  }) {
    final salaryBreakdowns = [
      computeEmployeeSalaryBreakdown(
        employeeId: user.id,
        employeeName: user.username,
        dailyRate: dailyRate,
        rows: rows,
        entries: entries,
        weeklySchedule: weeklySchedule,
        globalSchedule: globalSchedule,
      ),
    ];

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimeCardPngPreviewScreen(
          employeeName: user.username,
          employeeEmail: user.email,
          companyName: company.name,
          companyId: company.companyId,
          filter: _periodFilter,
          rows: rows,
          totalHours: totalHours,
          generatedAt: _now,
          periodDate: _viewDate,
          salaryBreakdowns: salaryBreakdowns,
        ),
      ),
    );
  }

  Future<void> _openEditEntryModal({
    required UserModel user,
    required CompanyModel company,
    required TimeCardTableRow row,
    required List<TimeEntry> entries,
  }) async {
    final entryCandidates = entries.where((e) => e.workDate == row.workDate);
    final existing = entryCandidates.isEmpty
        ? null
        : entryCandidates.reduce((a, b) => a.timeIn.isBefore(b.timeIn) ? a : b);

    // Initialize form values from existing entry.
    final workDate = parseWorkDateString(row.workDate) ?? _viewDate;
    TimeOfDay timeIn = TimeOfDay(
      hour: existing?.timeIn.hour ?? 9,
      minute: existing?.timeIn.minute ?? 0,
    );
    var isActive = existing?.timeOut == null;
    TimeOfDay timeOut = TimeOfDay(
      hour: (existing?.timeOut ?? existing?.timeIn ?? DateTime(workDate.year, workDate.month, workDate.day, 18)).hour,
      minute: (existing?.timeOut ?? existing?.timeIn ?? DateTime(workDate.year, workDate.month, workDate.day, 18)).minute,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var saving = false;

        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> _pickTimeIn() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: timeIn,
              );
              if (picked == null) return;
              setStateDialog(() => timeIn = picked);
            }

            Future<void> _pickTimeOut() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: timeOut,
              );
              if (picked == null) return;
              setStateDialog(() => timeOut = picked);
            }

            return AlertDialog(
              title: const Text('Edit time in / time out'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time in'),
                      trailing: Text(timeIn.format(context)),
                      onTap: saving ? null : _pickTimeIn,
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Still on shift (no time out)'),
                      value: isActive,
                      onChanged: saving
                          ? null
                          : (v) => setStateDialog(() => isActive = v),
                    ),
                    if (!isActive)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Time out'),
                        trailing: Text(timeOut.format(context)),
                        onTap: saving ? null : _pickTimeOut,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setStateDialog(() => saving = true);
                          try {
                            final newTimeIn = DateTime(
                              workDate.year,
                              workDate.month,
                              workDate.day,
                              timeIn.hour,
                              timeIn.minute,
                            );
                            final newTimeOut = isActive
                                ? null
                                : DateTime(
                                    workDate.year,
                                    workDate.month,
                                    workDate.day,
                                    timeOut.hour,
                                    timeOut.minute,
                                  );

                            await _timeEntryRepository.adminSaveEntry(
                              entryId: existing?.id,
                              userId: user.id,
                              userEmail: user.email,
                              username: user.username,
                              company: company,
                              timeIn: newTimeIn,
                              timeOut: newTimeOut,
                            );

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                            await context.read<TimeEntryProvider>().loadDetailsForCompany(
                                  user: user,
                                  company: company,
                                );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Time entry updated.')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e is StateError ? e.message : 'Could not update time entry.')),
                            );
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final company = companies.selectedCompany;
    final timeEntries = context.watch<TimeEntryProvider>();
    final schedule = context.watch<TimeCardSettingsProvider>().schedule;
    final colors = AppColors.of(context);

    if (user != null && company != null) {
      final key = '${user.id}:${company.id}';
      if (_loadedKey != key) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
      }
    } else {
      _loadedKey = null;
      _leaves = [];
    }

    EmployeeWeeklySchedule? employeeSchedule;
    var dailyRate = 0.0;
    if (user != null) {
      for (final member in companies.staff) {
        if (member.userId == user.id) {
          employeeSchedule = member.timeCardProfile.weeklySchedule;
          dailyRate = member.timeCardProfile.dailyRate;
          break;
        }
      }
    }

    final tableRows = buildTimeCardTableRows(
      allEntries: timeEntries.allEntries,
      filter: _periodFilter,
      now: _now,
      viewDate: _viewDate,
      schedule: schedule,
      leaves: _leaves,
      employeeSchedule: employeeSchedule,
    );
    final periodTotal = formatDurationShort(
      totalDurationForRows(
        timeEntries.allEntries,
        _periodFilter,
        _now,
        viewDate: _viewDate,
      ),
    );
    final active = timeEntries.activeEntry;
    final todayTotal =
        formatDurationShort(sumEntriesDuration(timeEntries.todayEntries, _now));
    final weekTotal = formatDurationShort(
      sumEntriesInRange(
        timeEntries.allEntries,
        startOfWeek(_now),
        _now,
        _now,
      ),
    );
    final monthTotal = formatDurationShort(
      sumEntriesInRange(
        timeEntries.allEntries,
        startOfMonth(_now),
        _now,
        _now,
      ),
    );

    return DashboardScaffold(
      title: 'Time card details',
      currentRoute: AppRoutes.employeeTimeCardDetails,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Text(
            company == null
                ? 'Select a company to view records.'
                : '${company.name} · ${timeEntries.allEntries.length} entries',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          if (company == null)
            _EmptyState(
              icon: Icons.business_outlined,
              message: 'Open a company from Switch company first.',
            )
          else if (timeEntries.isLoading && timeEntries.allEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (active != null) ...[
              _ActiveShiftChip(entry: active, now: _now),
              const SizedBox(height: 8),
            ],
            _ExpandableTile(
              expanded: _summaryExpanded,
              onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
              leading: Icon(
                Icons.bar_chart_rounded,
                size: 18,
                color: AppColors.primaryDark,
              ),
              title: 'Summary',
              trailing: Text(
                'Today $todayTotal',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: _CompactStatsRow(
                  stats: [
                    _StatItem(label: 'Today', value: todayTotal),
                    _StatItem(label: 'Week', value: weekTotal),
                    _StatItem(label: 'Month', value: monthTotal),
                    _StatItem(
                      label: 'Sessions',
                      value: '${timeEntries.todayEntries.length}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _PeriodFilterBar(
              filter: _periodFilter,
              viewDate: _viewDate,
              periodLabel: periodSubtitle(_periodFilter, _viewDate),
              totalHours: periodTotal,
              onFilterChanged: (value) =>
                  setState(() => _periodFilter = value),
              onViewDateChanged: (value) => setState(() => _viewDate = value),
              onViewPressed: user == null
                  ? null
                  : () => _openPngPreview(
                        user: user,
                        company: company,
                        rows: tableRows,
                        totalHours: periodTotal,
                        dailyRate: dailyRate,
                        entries: timeEntries.allEntries,
                        weeklySchedule: employeeSchedule,
                        globalSchedule: schedule,
                      ),
            ),
            const SizedBox(height: 8),
            TimeCardReportTable(
              rows: tableRows,
              compact: true,
              onEditRow: (row) {
                _openEditEntryModal(
                  user: user!,
                  company: company,
                  row: row,
                  entries: timeEntries.allEntries,
                );
              },
            ),
            const SizedBox(height: 8),
            _TableFooter(
              rowCount: tableRows.where((row) => row.hasData).length,
              totalHours: periodTotal,
              filter: _periodFilter,
            ),
            if (timeEntries.allEntries.isEmpty) ...[
              const SizedBox(height: 8),
              _EmptyState(
                icon: Icons.schedule_outlined,
                message: 'No records yet. Use Time in / Time out to track.',
              ),
            ],
          ],
          if (timeEntries.errorMessage != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: timeEntries.errorMessage!),
          ],
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _PeriodFilterBar extends StatelessWidget {
  const _PeriodFilterBar({
    required this.filter,
    required this.viewDate,
    required this.periodLabel,
    required this.totalHours,
    required this.onFilterChanged,
    required this.onViewDateChanged,
    required this.onViewPressed,
  });

  final TimeCardPeriodFilter filter;
  final DateTime viewDate;
  final String periodLabel;
  final String totalHours;
  final ValueChanged<TimeCardPeriodFilter> onFilterChanged;
  final ValueChanged<DateTime> onViewDateChanged;
  final VoidCallback? onViewPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimeCardMonthFilter(
            viewDate: viewDate,
            onViewDateChanged: onViewDateChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  periodLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                ),
              ),
              Text(
                totalHours,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TimeCardPeriodFilter>(
                      value: filter,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(10),
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.textSecondary,
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                      items: [
                        for (final option in TimeCardPeriodFilter.values)
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onFilterChanged(value);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onViewPressed,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('View'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableFooter extends StatelessWidget {
  const _TableFooter({
    required this.rowCount,
    required this.totalHours,
    required this.filter,
  });

  final int rowCount;
  final String totalHours;
  final TimeCardPeriodFilter filter;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filter == TimeCardPeriodFilter.daily
                  ? '$rowCount session(s)'
                  : '$rowCount day(s) with records',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
          Text(
            'Total $totalHours',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
          ),
        ],
      ),
    );
  }
}

class _ActiveShiftChip extends StatelessWidget {
  const _ActiveShiftChip({required this.entry, required this.now});

  final TimeEntry entry;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final elapsed = entryDuration(entry, now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'On shift · in ${formatClockTime(entry.timeIn)} · '
              '${formatDurationShort(elapsed)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactStatsRow extends StatelessWidget {
  const _CompactStatsRow({required this.stats});

  final List<_StatItem> stats;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 28,
              color: colors.border,
            ),
          Expanded(
            child: Column(
              children: [
                Text(
                  stats[i].label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  stats[i].value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ExpandableTile extends StatelessWidget {
  const _ExpandableTile({
    required this.expanded,
    required this.onTap,
    required this.leading,
    required this.title,
    this.trailing,
    required this.child,
  });

  final bool expanded;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: colors.header,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      trailing!,
                    ],
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: child,
                crossFadeState: expanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colors.textHint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
