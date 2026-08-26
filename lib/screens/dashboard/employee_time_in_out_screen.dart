import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/staff_assignment.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../widgets/compact_page.dart';
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
  int _clockDeclineCount = 0;

  bool get _clockRequestsLocked =>
      _clockDeclineCount >= StaffAssignment.clockDeclineLimit;

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

  Future<void> _loadIfReady() async {
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
    final declines = await context.read<CompanyProvider>().clockDeclineCountFor(
          companyId: company.id,
          userId: user.id,
        );
    if (!mounted) return;
    setState(() => _clockDeclineCount = declines);
  }

  Future<String?> _promptNote({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final colors = AppColors.of(context);
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Required — reason or details for this request',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.of(dialogContext).pop(value);
              },
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
    controller.dispose();
    return note;
  }

  Future<void> _clockIn() async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) return;

    if (_clockRequestsLocked) {
      SnackBarHelper.showError(
        context,
        'Time in/out requests are locked after '
        '${StaffAssignment.clockDeclineLimit} declines. '
        'Ask an admin or super admin to edit your time card settings to unlock.',
      );
      return;
    }

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

    final note = await _promptNote(
      title: 'Request time in',
      message:
          'Submit a time-in request for ${company.name}.\n\n'
          'Add a note (required). An admin or super admin must approve it '
          'before it is saved. After 3 declines, new requests are locked '
          'until an admin edits your time card settings.',
      confirmLabel: 'Request time in',
    );
    if (note == null || !mounted) return;

    final ok = await context.read<TimeEntryProvider>().requestClockIn(
          user: user,
          company: company,
          note: note,
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

    if (_clockRequestsLocked) {
      SnackBarHelper.showError(
        context,
        'Time in/out requests are locked after '
        '${StaffAssignment.clockDeclineLimit} declines. '
        'Ask an admin or super admin to edit your time card settings to unlock.',
      );
      return;
    }

    final timeEntries = context.read<TimeEntryProvider>();
    if (!timeEntries.canClockOutToday) {
      SnackBarHelper.showError(
        context,
        timeEntries.pendingClockOut != null
            ? 'Your time-out request is already pending approval.'
            : 'Submit a time-in request for today before timing out.',
      );
      return;
    }

    final active = timeEntries.activeEntry;
    final pendingIn = timeEntries.pendingClockIn;
    final started = active != null
        ? '\nStarted at ${formatClockTime(active.timeIn)}.'
        : pendingIn != null
            ? '\nPending time in at ${pendingIn.requestedAtLabel} '
                '(still waiting for approval).'
            : '';

    final note = await _promptNote(
      title: 'Request time out',
      message:
          'Submit a time-out request for ${company.name}.$started\n\n'
          'Add a note (required). Time in and time out each need their own '
          'approval. After 3 declines, new requests are locked until an admin '
          'edits your time card settings.',
      confirmLabel: 'Request time out',
    );
    if (note == null || !mounted) return;

    final ok = await context.read<TimeEntryProvider>().requestClockOut(
          user: user,
          company: company,
          note: note,
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
    final density = CompactPageStyle.of(context);

    if (user != null && company != null) {
      final key = '${user.id}:${company.id}';
      if (_loadedKey != key) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfReady());
      }
    } else {
      _loadedKey = null;
      _clockDeclineCount = 0;
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
    final statusLabel = pendingOut != null && pendingIn != null
        ? 'In & out pending approval'
        : pendingOut != null
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
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Time in / Time out',
            subtitle: company == null
                ? 'Select a company to record your attendance.'
                : 'Submit time in / out for ${company.name}. '
                    'A note is required. Admin or super admin must approve '
                    'before it is saved.',
          ),
          if (_clockRequestsLocked) ...[
            SizedBox(height: density.cardGap),
            Container(
              width: double.infinity,
              padding: density.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(density.radius),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                'Requests locked after $_clockDeclineCount/'
                '${StaffAssignment.clockDeclineLimit} declines. '
                'Ask an admin or super admin to edit your time card settings '
                'or unlock your clock requests.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: density.captionSize,
                    ),
              ),
            ),
          ] else if (_clockDeclineCount > 0) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Declines: $_clockDeclineCount/'
              '${StaffAssignment.clockDeclineLimit}. '
              'After ${StaffAssignment.clockDeclineLimit}, new requests are locked.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: density.captionSize,
                  ),
            ),
          ],
          SizedBox(height: density.sectionGap + 4),
          _LiveClockCard(
            now: _now,
            dateLabel: _formatDate(_now),
            clockedIn: clockedIn,
            sessionElapsed: sessionElapsed,
            timeIn: active?.timeIn,
          ),
          SizedBox(height: density.cardGap + 4),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.timelapse_rounded,
                  label: 'Today total',
                  value: formatDurationShort(timeEntries.todayWorked),
                ),
              ),
              SizedBox(width: density.cardGap + 4),
              Expanded(
                child: _StatTile(
                  icon: Icons.event_available_outlined,
                  label: 'Today status',
                  value: pendingOut != null && pendingIn != null
                      ? 'Both pending'
                      : pendingOut != null
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
          SizedBox(height: density.cardGap + 4),
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
          SizedBox(height: density.sectionGap + 4),
          if (timeEntries.isLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: density.sectionGap),
              child: const Center(child: CircularProgressIndicator()),
            )
          else ...[
            PrimaryButton(
              label: _clockRequestsLocked
                  ? 'Requests locked'
                  : pendingOut != null
                      ? 'Time out pending'
                      : canClockOut
                          ? 'Request time out'
                          : pendingIn != null
                              ? 'Time in pending'
                              : completedToday
                                  ? 'Completed for today'
                                  : 'Request time in',
              isLoading: timeEntries.isSaving,
              onPressed: company == null ||
                      timeEntries.isSaving ||
                      _clockRequestsLocked
                  ? null
                  : canClockOut
                      ? _clockOut
                      : canClockIn
                          ? _clockIn
                          : null,
            ),
            SizedBox(height: density.cardGap + 2),
            Text(
              company == null
                  ? 'Open a company from Switch company before clocking in.'
                  : _clockRequestsLocked
                      ? 'New time in/out requests are locked until an admin '
                          'or super admin edits your time card settings.'
                      : pendingOut != null
                          ? pendingIn != null
                              ? 'Time in (${pendingIn.requestedAtLabel}) and time out (${pendingOut.requestedAtLabel}) are waiting for approval.'
                              : 'Time-out request at ${pendingOut.requestedAtLabel} is waiting for approval.'
                          : canClockOut
                              ? pendingIn != null
                                  ? 'Time in is still pending — you can still request time out now for continuous flow.'
                                  : 'Submit time out when your shift ends. It saves only after approval.'
                              : pendingIn != null
                                  ? 'Time-in request at ${pendingIn.requestedAtLabel} is waiting for approval.'
                                  : completedToday
                                      ? 'You already finished attendance for today.'
                                      : 'Submit time in with a required note. It saves only after approval.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: density.captionSize,
                    color: colors.textSecondary,
                  ),
            ),
          ],
          if (timeEntries.recentEntries.isNotEmpty) ...[
            SizedBox(height: density.sectionGap + 12),
            Text(
              'Recent records',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: density.sectionTitleSize,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            SizedBox(height: density.cardGap + 2),
            ...timeEntries.recentEntries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: density.cardGap),
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
    final density = CompactPageStyle.of(context);

    return Container(
      padding: density.cardPadding.add(
        EdgeInsets.all(density.compact ? 6 : 8),
      ),
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
        borderRadius: BorderRadius.circular(density.compact ? 16 : 22),
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
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: density.compact ? 36 : 44,
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
              padding: EdgeInsets.symmetric(
                horizontal: density.compact ? 12 : 14,
                vertical: density.compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: colors.card.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(density.radius),
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
    final density = CompactPageStyle.of(context);

    return Container(
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: density.compact ? 18 : 22,
            color: AppColors.primaryDark,
          ),
          SizedBox(width: density.compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: density.captionSize,
                        color: colors.textSecondary,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: density.cardTitleSize,
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
    final density = CompactPageStyle.of(context);

    return Container(
      padding: density.cardPadding.add(
        EdgeInsets.all(density.compact ? 2 : 4),
      ),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: density.cardTitleSize,
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: density.cardGap + 2),
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
    final density = CompactPageStyle.of(context);
    final closed = !entry.isOpen;

    return Container(
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: density.compact ? 32 : 40,
            height: density.compact ? 32 : 40,
            decoration: BoxDecoration(
              color: (closed ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(density.radius),
            ),
            child: Icon(
              closed ? Icons.logout_rounded : Icons.login_rounded,
              size: density.compact ? 16 : 20,
              color: closed ? AppColors.success : AppColors.primaryDark,
            ),
          ),
          SizedBox(width: density.compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.workDate,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontSize: density.cardTitleSize,
                      ),
                ),
                SizedBox(height: density.compact ? 2 : 4),
                Text(
                  '${formatClockTime(entry.timeIn)} → '
                  '${entry.timeOut == null ? 'Active' : formatClockTime(entry.timeOut!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: density.captionSize,
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          Text(
            formatDurationShort(entry.duration),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: density.cardTitleSize,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
