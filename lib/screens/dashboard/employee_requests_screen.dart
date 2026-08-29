import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/navigation/app_navigator.dart';
import '../../core/navigation/notification_sync.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/active_page_load.dart';
import '../../core/utils/rtdb_platform.dart';
import '../../models/clock_request.dart';
import '../../models/company_model.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_change_request.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../services/clock_request_repository.dart';
import '../../services/leave_request_repository.dart';
import '../../services/rtdb/rtdb_desktop_limiter.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

/// Employee inbox for their own pending leave, time-card, and clock requests.
class EmployeeRequestsScreen extends StatefulWidget {
  const EmployeeRequestsScreen({super.key});

  @override
  State<EmployeeRequestsScreen> createState() => _EmployeeRequestsScreenState();
}

class _EmployeeRequestsScreenState extends State<EmployeeRequestsScreen>
    with ActivePageLoad {
  final _leaveRepo = LeaveRequestRepository();
  final _timeChangeRepo = TimeCardChangeRequestRepository();
  final _clockRepo = ClockRequestRepository();

  List<_EmployeePendingRequest> _items = [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  Set<String> _trackedPendingKeys = {};
  bool _hadLoadedOnce = false;
  Timer? _pollTimer;

  @override
  void onPageActivated() {
    if (preferRtdbPolling) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && TickerMode.valuesOf(context).enabled) _load();
      });
    } else {
      _load();
    }
    _startPolling();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _loadGeneration++;
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      _load(refresh: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _matchesCompany({
    required String companyId,
    required String companyDocumentId,
    required String companyName,
    required CompanyModel? company,
  }) {
    if (company == null) return true;
    if (companyId == company.id ||
        companyDocumentId == company.firestoreId ||
        companyId == company.firestoreId ||
        companyDocumentId == company.id) {
      return true;
    }
    return companyName.trim().toLowerCase() ==
        company.name.trim().toLowerCase();
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_loadGeneration;
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Sign in to view your requests.';
      });
      return;
    }

    final companies = context.read<CompanyProvider>();
    final company = companies.selectedCompany;
    if (!refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      await RtdbDesktopLimiter.runHeavy(() async {
        late List<LeaveRequest> leaves;
        late List<TimeCardChangeRequest> timeEdits;
        late List<ClockRequest> clocks;
        if (preferRtdbPolling) {
          leaves = await _leaveRepo.listByUserId(user.id);
          if (generation != _loadGeneration || !mounted) return;
          timeEdits = await _timeChangeRepo.listByEmployeeId(user.id);
          if (generation != _loadGeneration || !mounted) return;
          clocks = await _clockRepo.listForUser(user.id);
        } else {
          final results = await Future.wait([
            _leaveRepo.listByUserId(user.id),
            _timeChangeRepo.listByEmployeeId(user.id),
            _clockRepo.listForUser(user.id),
          ]);
          leaves = results[0] as List<LeaveRequest>;
          timeEdits = results[1] as List<TimeCardChangeRequest>;
          clocks = results[2] as List<ClockRequest>;
        }
        if (generation != _loadGeneration || !mounted) return;

        final pending = <_EmployeePendingRequest>[
          for (final leave in leaves)
            if (leave.status.toLowerCase() == 'pending' &&
                _matchesCompany(
                  companyId: leave.companyId,
                  companyDocumentId: leave.companyDocumentId,
                  companyName: leave.companyName,
                  company: company,
                ))
              _EmployeePendingRequest.leave(leave),
          for (final edit in timeEdits)
            if (edit.isPending &&
                _matchesCompany(
                  companyId: edit.companyId,
                  companyDocumentId: edit.companyDocumentId,
                  companyName: edit.companyName,
                  company: company,
                ))
              _EmployeePendingRequest.timeEdit(edit),
          for (final clock in clocks)
            if (clock.isPending &&
                _matchesCompany(
                  companyId: clock.companyId,
                  companyDocumentId: clock.companyDocumentId,
                  companyName: clock.companyName,
                  company: company,
                ))
              _EmployeePendingRequest.clock(clock),
        ]..sort((a, b) {
            final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
            if (byCreated != 0) return byCreated;
            return b.sortKey.compareTo(a.sortKey);
          });

        final newKeys = pending.map((item) => item.key).toSet();
        final resolved =
            _hadLoadedOnce ? _trackedPendingKeys.difference(newKeys) : <String>{};

        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _items = pending;
          _loading = false;
          _error = null;
          _trackedPendingKeys = newKeys;
          _hadLoadedOnce = true;
        });

        if (resolved.isNotEmpty) {
          syncUserNotificationProviders(context);
          AppNavigator.openShellRoute(AppRoutes.notifications);
        }
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _items = [];
        _loading = false;
        _error = 'Unable to load your pending requests.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final companyName =
        context.watch<CompanyProvider>().selectedCompany?.name ?? 'your company';

    return DashboardScaffold(
      title: 'Requests',
      currentRoute: AppRoutes.employeeRequests,
      child: ListView(
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Pending requests',
            subtitle:
                'Leave, time-card edits, and time in/out waiting for review at $companyName. '
                'When a request is approved or declined, you are taken to Notifications.',
          ),
          SizedBox(height: density.sectionGap),
          CompactSummaryStrip(
            items: [
              CompactSummaryItem(label: 'Pending', value: '${_items.length}'),
            ],
          ),
          SizedBox(height: density.cardGap),
          Row(
            children: [
              const Spacer(),
              IconButton(
                visualDensity: density.compact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
                tooltip: 'Refresh',
                onPressed: _loading ? null : () => _load(refresh: true),
                icon: Icon(
                  Icons.refresh_rounded,
                  size: density.compact ? 20 : 22,
                ),
                color: AppColors.primaryDark,
              ),
            ],
          ),
          SizedBox(height: density.sectionGap),
          if (_loading)
            const AppLoadingView(
              title: 'Loading requests',
              message: 'Fetching your pending requests…',
            )
          else if (_error != null)
            _MessageCard(icon: Icons.error_outline, message: _error!)
          else if (_items.isEmpty)
            const _MessageCard(
              icon: Icons.inbox_outlined,
              message:
                  'No pending requests. Submit leave, time in/out, or time-card '
                  'changes from the other Time Card pages.',
            )
          else
            for (final item in _items) ...[
              _PendingRequestCard(item: item),
              SizedBox(height: density.cardGap),
            ],
        ],
      ),
    );
  }
}

enum _EmployeeRequestKind { leave, timeEdit, clock }

class _EmployeePendingRequest {
  const _EmployeePendingRequest._({
    required this.kind,
    required this.key,
    required this.sortKey,
    required this.title,
    required this.subtitle,
    required this.companyName,
    required this.detailLines,
    required this.createdAt,
  });

  factory _EmployeePendingRequest.leave(LeaveRequest leave) {
    return _EmployeePendingRequest._(
      kind: _EmployeeRequestKind.leave,
      key: 'leave:${leave.id}',
      sortKey: leave.startDate,
      title: 'Leave request',
      subtitle: '${leave.startDate} → ${leave.endDate}',
      companyName: leave.companyName,
      detailLines: [
        if (leave.reason.trim().isNotEmpty) 'Reason: ${leave.reason.trim()}',
        'Waiting for admin review.',
      ],
      createdAt: leave.createdAt ?? leave.updatedAt,
    );
  }

  factory _EmployeePendingRequest.timeEdit(TimeCardChangeRequest edit) {
    return _EmployeePendingRequest._(
      kind: _EmployeeRequestKind.timeEdit,
      key: 'time:${edit.id}',
      sortKey: edit.workDate,
      title: 'Time card change',
      subtitle: 'Date: ${edit.workDate}',
      companyName: edit.companyName,
      detailLines: [
        'Current: ${edit.hasPriorRecord ? '${edit.currentTimeInLabel} → ${edit.currentTimeOutLabel}' : 'No prior record'}',
        'Proposed: ${edit.proposedTimeInLabel} → ${edit.proposedTimeOutLabel}',
        if (edit.note.trim().isNotEmpty) 'Note: ${edit.note.trim()}',
        'Waiting for admin review.',
      ],
      createdAt: edit.createdAt ?? edit.updatedAt,
    );
  }

  factory _EmployeePendingRequest.clock(ClockRequest clock) {
    return _EmployeePendingRequest._(
      kind: _EmployeeRequestKind.clock,
      key: 'clock:${clock.id}',
      sortKey: clock.workDate,
      title: clock.typeLabel,
      subtitle: '${clock.workDate} · ${clock.requestedAtLabel}',
      companyName: clock.companyName,
      detailLines: [
        if (clock.note.trim().isNotEmpty) 'Note: ${clock.note.trim()}',
        'Waiting for admin review.',
      ],
      createdAt: clock.createdAt ?? clock.updatedAt ?? clock.requestedAt,
    );
  }

  final _EmployeeRequestKind kind;
  final String key;
  final String sortKey;
  final String title;
  final String subtitle;
  final String companyName;
  final List<String> detailLines;
  final DateTime? createdAt;
}

class _PendingRequestCard extends StatelessWidget {
  const _PendingRequestCard({required this.item});

  final _EmployeePendingRequest item;

  IconData get _icon {
    switch (item.kind) {
      case _EmployeeRequestKind.leave:
        return Icons.event_busy_outlined;
      case _EmployeeRequestKind.timeEdit:
        return Icons.edit_calendar_outlined;
      case _EmployeeRequestKind.clock:
        return Icons.login_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    const statusColor = Color(0xFFD97706);

    return Container(
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _icon,
                size: density.compact ? 18 : 20,
                color: AppColors.primaryDark,
              ),
              SizedBox(width: density.compact ? 8 : 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: density.chipLabelSize,
                          ),
                    ),
                    SizedBox(height: density.compact ? 2 : 4),
                    Text(
                      item.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: density.cardTitleSize,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: density.compact ? 8 : 10,
                  vertical: density.compact ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  'Pending',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: density.chipLabelSize,
                      ),
                ),
              ),
            ],
          ),
          if (item.createdAt != null) ...[
            SizedBox(height: density.cardGap),
            Text(
              'Submitted: ${formatDateTime12h(item.createdAt!)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: density.captionSize,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          SizedBox(height: density.titleSubtitleGap),
          Text(
            item.companyName.isEmpty ? 'Company' : item.companyName,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: density.bodySize,
                  fontWeight: FontWeight.w600,
                ),
          ),
          SizedBox(height: density.cardGap),
          for (final line in item.detailLines)
            Padding(
              padding: EdgeInsets.only(bottom: density.compact ? 2 : 4),
              child: Text(
                line,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: density.captionSize,
                      color: colors.textSecondary,
                      fontWeight: line.startsWith('Proposed')
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: density.compact ? 20 : 24,
        horizontal: density.compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: density.compact ? 26 : 28,
            color: colors.textSecondary,
          ),
          SizedBox(height: density.cardGap),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: density.bodySize,
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
