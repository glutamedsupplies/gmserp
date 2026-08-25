import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';

class EmployeeTimeInOutScreen extends StatefulWidget {
  const EmployeeTimeInOutScreen({super.key});

  @override
  State<EmployeeTimeInOutScreen> createState() =>
      _EmployeeTimeInOutScreenState();
}

class _EmployeeTimeInOutScreenState extends State<EmployeeTimeInOutScreen> {
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  String? _loadedKey;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _loadIfReady() {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;

    final key = '${user.id}:${company.id}';
    if (_loadedKey == key) return;
    _loadedKey = key;
    context.read<TimeEntryProvider>().loadForCompany(
          user: user,
          company: company,
        );
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final colors = AppColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: AppColors.onPrimary,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _clockIn() async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;

    final timeEntries = context.read<TimeEntryProvider>();
    if (!timeEntries.canClockInToday) {
      SnackBarHelper.showError(
        context,
        timeEntries.pendingClockIn != null
            ? 'Your time-in request is already pending approval.'
            : timeEntries.activeEntry != null
                ? 'You are already clocked in.'
                : 'You already completed time in / time out for today.',
      );
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Confirm time in',
      message:
          'Submit a time-in request for ${company.name} now?\n\n'
          'An admin or super admin must approve it before it is saved.\n'
          'Only one time in / time out is allowed per day.',
      confirmLabel: 'Request time in',
    );
    if (!confirmed || !mounted) return;

    final ok = await context.read<TimeEntryProvider>().requestClockIn(
          user: user,
          company: company,
        );
    if (!mounted) return;
    if (ok) {
      final pending = context.read<TimeEntryProvider>().pendingClockIn;
      SnackBarHelper.showSuccess(
        context,
        pending == null
            ? 'Time-in request submitted for approval.'
            : 'Time-in request submitted at ${pending.requestedAtLabel}. Waiting for approval.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        context.read<TimeEntryProvider>().errorMessage ??
            'Could not submit time-in request.',
      );
    }
  }

  Future<void> _clockOut() async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;

    final timeEntries = context.read<TimeEntryProvider>();
    if (!timeEntries.canClockOutToday) {
      SnackBarHelper.showError(
        context,
        timeEntries.pendingClockOut != null
            ? 'Your time-out request is already pending approval.'
            : 'No approved time-in yet. Wait for approval before timing out.',
      );
      return;
    }

    final active = timeEntries.activeEntry;
    final started = active == null
        ? ''
        : '\nStarted at ${formatClockTime(active.timeIn)}.';

    final confirmed = await _confirmAction(
      title: 'Confirm time out',
      message:
          'Submit a time-out request for ${company.name} now?$started\n\n'
          'An admin or super admin must approve it before it is saved.\n'
          'You will not be able to time in again today after approval.',
      confirmLabel: 'Request time out',
    );
    if (!confirmed || !mounted) return;

    final ok = await context.read<TimeEntryProvider>().requestClockOut(
          user: user,
          company: company,
        );
    if (!mounted) return;
    if (ok) {
      final pending = context.read<TimeEntryProvider>().pendingClockOut;
      SnackBarHelper.showSuccess(
        context,
        pending == null
            ? 'Time-out request submitted for approval.'
            : 'Time-out request submitted at ${pending.requestedAtLabel}. Waiting for approval.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        context.read<TimeEntryProvider>().errorMessage ??
            'Could not submit time-out request.',
      );
    }
  }

  String _formatDate(DateTime value) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekday = weekdays[value.weekday - 1];
    final month = months[value.month - 1];
    return '$weekday, $month ${value.day}, ${value.year}';
  }

  Duration _sessionElapsed(TimeEntry? active) {
    if (active == null) return Duration.zero;
    return _now.difference(active.timeIn);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final company = context.watch<CompanyProvider>().selectedCompany;
    final timeEntries = context.watch<TimeEntryProvider>();
    final colors = AppColors.of(context);

    if (user != null && company != null) {
      final key = '${user.id}:${company.id}';
      if (_loadedKey != key) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
      }
    } else {
      _loadedKey = null;
    }

    final active = timeEntries.activeEntry;
    final clockedIn = active != null;
    final completedToday = timeEntries.hasCompletedToday;
    final canClockIn = timeEntries.canClockInToday;
    final canClockOut = timeEntries.canClockOutToday;
    final pendingIn = timeEntries.pendingClockIn;
    final pendingOut = timeEntries.pendingClockOut;
    final sessionElapsed = _sessionElapsed(active);
    final todayRecord = timeEntries.todayEntries.isEmpty
        ? null
        : timeEntries.todayEntries.first;
    final statusLabel = pendingOut != null
        ? 'Time out pending approval'
        : clockedIn
            ? 'Clocked in'
            : pendingIn != null
                ? 'Time in pending approval'
                : completedToday
                    ? 'Completed for today'
                    : 'Not clocked in';
    final displayTimeIn =
        active?.timeIn ?? pendingIn?.requestedAt ?? todayRecord?.timeIn;
    final displayTimeOut =
        active?.timeOut ?? pendingOut?.requestedAt ?? todayRecord?.timeOut;

    return DashboardScaffold(
      title: 'Time in / Time out',
      currentRoute: AppRoutes.employeeTimeInOut,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Time in / Time out',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            company == null
                ? 'Select a company to record your attendance.'
                : 'Submit time in / out for ${company.name}. '
                    'Admin or super admin must approve before it is saved.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _LiveClockCard(
            now: _now,
            dateLabel: _formatDate(_now),
            clockedIn: clockedIn,
            sessionElapsed: sessionElapsed,
            timeIn: active?.timeIn,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.timelapse_rounded,
                  label: 'Today total',
                  value: formatDurationShort(timeEntries.todayWorked),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.event_available_outlined,
                  label: 'Today status',
                  value: pendingOut != null
                      ? 'Out pending'
                      : clockedIn
                          ? 'On shift'
                          : pendingIn != null
                              ? 'In pending'
                              : completedToday
                                  ? 'Done'
                                  : 'Open',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailPanel(
            user: user?.username ?? '—',
            email: user?.email ?? '—',
            company: company?.name ?? 'No company selected',
            companyId: company?.companyId ?? '—',
            status: statusLabel,
            clockedIn: clockedIn,
            timeIn: displayTimeIn,
            timeOut: displayTimeOut,
          ),
          const SizedBox(height: 20),
          if (timeEntries.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            PrimaryButton(
              label: pendingOut != null
                  ? 'Time out pending'
                  : canClockOut
                      ? 'Request time out'
                      : pendingIn != null
                          ? 'Time in pending'
                          : completedToday
                              ? 'Completed for today'
                              : 'Request time in',
              isLoading: timeEntries.isSaving,
              onPressed: company == null || timeEntries.isSaving
                  ? null
                  : canClockOut
                      ? _clockOut
                      : canClockIn
                          ? _clockIn
                          : null,
            ),
            const SizedBox(height: 12),
            Text(
              company == null
                  ? 'Open a company from Switch company before clocking in.'
                  : pendingOut != null
                      ? 'Time-out request at ${pendingOut.requestedAtLabel} is waiting for approval.'
                      : canClockOut
                          ? 'Submit time out when your shift ends. It saves only after approval.'
                          : pendingIn != null
                              ? 'Time-in request at ${pendingIn.requestedAtLabel} is waiting for approval.'
                              : completedToday
                                  ? 'You already finished attendance for today.'
                                  : 'Submit time in to start. It saves only after admin or super admin approval.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ],
          if (timeEntries.recentEntries.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              'Recent records',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            ...timeEntries.recentEntries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HistoryTile(entry: entry),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveClockCard extends StatelessWidget {
  const _LiveClockCard({
    required this.now,
    required this.dateLabel,
    required this.clockedIn,
    required this.sessionElapsed,
    required this.timeIn,
  });

  final DateTime now;
  final String dateLabel;
  final bool clockedIn;
  final Duration sessionElapsed;
  final DateTime? timeIn;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: clockedIn
              ? [
                  AppColors.primary.withValues(alpha: 0.28),
                  AppColors.primaryDark.withValues(alpha: 0.14),
                ]
              : [
                  colors.header,
                  colors.inputFill,
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: clockedIn
              ? AppColors.primary.withValues(alpha: 0.55)
              : colors.border,
          width: clockedIn ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: clockedIn ? AppColors.success : colors.textHint,
                  shape: BoxShape.circle,
                  boxShadow: clockedIn
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.45),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                clockedIn ? 'ON SHIFT' : 'OFF SHIFT',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                      color: clockedIn ? AppColors.primaryDark : colors.textSecondary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatClockTime(now),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          if (clockedIn && timeIn != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    'Current session',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatDuration(sessionElapsed),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Started at ${formatClockTime(timeIn!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    required this.user,
    required this.email,
    required this.company,
    required this.companyId,
    required this.status,
    required this.clockedIn,
    required this.timeIn,
    required this.timeOut,
  });

  final String user;
  final String email;
  final String company;
  final String companyId;
  final String status;
  final bool clockedIn;
  final DateTime? timeIn;
  final DateTime? timeOut;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          _DetailRow(label: 'Employee', value: user),
          _DetailRow(label: 'Email', value: email),
          _DetailRow(label: 'Company', value: company),
          _DetailRow(label: 'Company ID', value: companyId),
          _DetailRow(
            label: 'Status',
            value: status,
            highlight: clockedIn,
          ),
          _DetailRow(
            label: 'Time in',
            value: timeIn == null ? '—' : formatClockTime(timeIn!),
          ),
          _DetailRow(
            label: 'Time out',
            value: timeOut == null ? '—' : formatClockTime(timeOut!),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                    color: highlight ? AppColors.primaryDark : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final closed = !entry.isOpen;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (closed ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              closed ? Icons.logout_rounded : Icons.login_rounded,
              size: 18,
              color: closed ? AppColors.success : AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.workDate,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatClockTime(entry.timeIn)} → '
                  '${entry.timeOut == null ? 'Active' : formatClockTime(entry.timeOut!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Text(
            formatDurationShort(entry.duration),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
