import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/clock_request.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_change_request.dart';
import '../../providers/company_provider.dart';
import '../../services/clock_request_repository.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class SuperAdminRequestsScreen extends StatefulWidget {
  const SuperAdminRequestsScreen({
    super.key,
    this.focusRequestType,
    this.focusRequestId,
  });

  /// `leave` or `time` from a notification payload.
  final String? focusRequestType;
  final String? focusRequestId;

  @override
  State<SuperAdminRequestsScreen> createState() =>
      _SuperAdminRequestsScreenState();
}

class _SuperAdminRequestsScreenState extends State<SuperAdminRequestsScreen> {
  final _leaveRepo = LeaveRequestRepository();
  final _timeChangeRepo = TimeCardChangeRequestRepository();
  final _clockRepo = ClockRequestRepository();
  final _searchController = TextEditingController();
  final _focusKey = GlobalKey();

  List<LeaveRequest> _leaveRequests = [];
  List<TimeCardChangeRequest> _timeRequests = [];
  List<ClockRequest> _clockRequests = [];
  bool _loading = true;
  String? _error;
  String _companyFilter = 'All';
  String _typeFilter = 'All';
  String _statusFilter = 'All';
  String _search = '';
  String? _focusType;
  String? _focusId;
  bool _didApplyFocus = false;

  static const _allCompanies = 'All';

  @override
  void initState() {
    super.initState();
    _focusType = widget.focusRequestType?.trim().toLowerCase();
    _focusId = widget.focusRequestId?.trim();
    if (_focusId != null && _focusId!.isNotEmpty) {
      _statusFilter = 'Pending';
      if (_focusType == 'leave') {
        _typeFilter = 'Leave';
      } else if (_focusType == 'time') {
        _typeFilter = 'Time edit';
      } else if (_focusType == 'clock') {
        _typeFilter = 'Time in/out';
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanies();
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant SuperAdminRequestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequestId != widget.focusRequestId ||
        oldWidget.focusRequestType != widget.focusRequestType) {
      _focusType = widget.focusRequestType?.trim().toLowerCase();
      _focusId = widget.focusRequestId?.trim();
      _didApplyFocus = false;
      if (_focusId != null && _focusId!.isNotEmpty) {
        setState(() {
          _statusFilter = 'Pending';
          if (_focusType == 'leave') {
            _typeFilter = 'Leave';
          } else if (_focusType == 'time') {
            _typeFilter = 'Time edit';
          } else if (_focusType == 'clock') {
            _typeFilter = 'Time in/out';
          }
        });
        _scrollToFocus();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _leaveRepo.listAll(),
        _timeChangeRepo.listAll(),
        _clockRepo.listAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _leaveRequests = results[0] as List<LeaveRequest>;
        _timeRequests = results[1] as List<TimeCardChangeRequest>;
        _clockRequests = results[2] as List<ClockRequest>;
        _loading = false;
      });
      _scrollToFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leaveRequests = [];
        _timeRequests = [];
        _clockRequests = [];
        _loading = false;
        _error = 'Unable to load requests.';
      });
    }
  }

  bool _isFocused(_UnifiedRequest item) {
    final id = _focusId;
    if (id == null || id.isEmpty) return false;
    if (item.leave != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'leave') &&
          item.leave!.id == id;
    }
    if (item.timeEdit != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'time') &&
          item.timeEdit!.id == id;
    }
    if (item.clock != null) {
      return (_focusType == null ||
              _focusType!.isEmpty ||
              _focusType == 'clock') &&
          item.clock!.id == id;
    }
    return false;
  }

  void _scrollToFocus() {
    if (_didApplyFocus) return;
    if (_focusId == null || _focusId!.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _focusKey.currentContext;
      if (ctx == null || !mounted) return;
      _didApplyFocus = true;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  List<String> _companyOptions(CompanyProvider companies) {
    final labels = <String>{};
    for (final company in companies.companies) {
      final name = company.name.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final leave in _leaveRequests) {
      final name = leave.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final change in _timeRequests) {
      final name = change.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final clock in _clockRequests) {
      final name = clock.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    final sorted = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...sorted];
  }

  bool _matchesCompany(
    _UnifiedRequest item,
    CompanyProvider companies, {
    required String companyFilter,
  }) {
    if (companyFilter == _allCompanies) return true;

    final selected = companyFilter.trim().toLowerCase();
    if (item.companyName.trim().toLowerCase() == selected) return true;

    for (final company in companies.companies) {
      if (company.name.trim().toLowerCase() != selected) continue;
      if (item.companyId == company.id ||
          item.companyDocumentId == company.firestoreId ||
          item.companyId == company.firestoreId ||
          item.companyDocumentId == company.id) {
        return true;
      }
    }
    return false;
  }

  List<_UnifiedRequest> _filtered(
    CompanyProvider companies, {
    required String companyFilter,
  }) {
    final query = _search.trim().toLowerCase();
    final items = <_UnifiedRequest>[
      if (_typeFilter == 'All' || _typeFilter == 'Leave')
        for (final leave in _leaveRequests) _UnifiedRequest.leave(leave),
      if (_typeFilter == 'All' || _typeFilter == 'Time edit')
        for (final change in _timeRequests) _UnifiedRequest.timeEdit(change),
      if (_typeFilter == 'All' || _typeFilter == 'Time in/out')
        for (final clock in _clockRequests) _UnifiedRequest.clock(clock),
    ];

    items.sort((a, b) {
      final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byCreated != 0) return byCreated;
      return b.sortKey.compareTo(a.sortKey);
    });

    return items.where((item) {
      if (!_matchesCompany(
        item,
        companies,
        companyFilter: companyFilter,
      )) {
        return false;
      }
      if (_statusFilter != 'All' &&
          item.status.toLowerCase() != _statusFilter.toLowerCase()) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.searchText.contains(query);
    }).toList();
  }

  Future<void> _updateLeaveStatus(LeaveRequest request, String status) async {
    try {
      await _leaveRepo.updateStatus(requestId: request.id, status: status);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        status == 'approved'
            ? 'Leave request approved.'
            : 'Leave request rejected.',
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not update leave request.');
    }
  }

  Future<void> _approveTimeChange(TimeCardChangeRequest request) async {
    try {
      await _timeChangeRepo.approve(request);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Time change approved and saved to the time card.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not approve time change.',
      );
    }
  }

  Future<void> _rejectTimeChange(TimeCardChangeRequest request) async {
    try {
      await _timeChangeRepo.reject(request.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Time change request rejected. No database changes were made.',
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not reject time change.');
    }
  }

  Future<void> _approveClock(ClockRequest request) async {
    try {
      await _clockRepo.approve(request);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        request.isClockIn
            ? 'Time in approved and saved.'
            : 'Time out approved and saved.',
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not approve clock request.',
      );
    }
  }

  Future<void> _rejectClock(ClockRequest request) async {
    try {
      await _clockRepo.reject(request.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Clock request rejected. No time card changes were made.',
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not reject clock request.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final companies = context.watch<CompanyProvider>();
    final companyOptions = _companyOptions(companies);
    final companyFilter = companyOptions.contains(_companyFilter)
        ? _companyFilter
        : _allCompanies;
    if (companyFilter != _companyFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _companyFilter = companyFilter);
      });
    }
    final filtered = _filtered(
      companies,
      companyFilter: companyFilter,
    );
    final pendingCount = filtered
        .where((item) => item.status.toLowerCase() == 'pending')
        .length;
    final totalPending = [
      ..._leaveRequests.where((r) => r.status.toLowerCase() == 'pending'),
      ..._timeRequests.where((r) => r.isPending),
      ..._clockRequests.where((r) => r.isPending),
    ].length;

    return DashboardScaffold(
      title: 'Requests',
      currentRoute: AppRoutes.superAdminRequests,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          const CompactPageHeader(
            title: 'Requests',
            subtitle:
                'Review leave, employee time in/out, and admin time-card change requests.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          CompactSummaryStrip(
            items: [
              CompactSummaryItem(
                label: 'Total',
                value:
                    '${_leaveRequests.length + _timeRequests.length + _clockRequests.length}',
              ),
              CompactSummaryItem(label: 'Pending', value: '$totalPending'),
              CompactSummaryItem(label: 'Showing', value: '${filtered.length}'),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          CompactFilterDropdown(
            value: companyFilter,
            items: companyOptions,
            hint: 'Company',
            onChanged: (value) => setState(() => _companyFilter = value),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: CompactFilterDropdown(
                  value: _typeFilter,
                  items: const ['All', 'Leave', 'Time in/out', 'Time edit'],
                  hint: 'Type',
                  onChanged: (value) => setState(() => _typeFilter = value),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: CompactFilterDropdown(
                  value: _statusFilter,
                  items: const ['All', 'Pending', 'Approved', 'Rejected'],
                  hint: 'Status',
                  onChanged: (value) => setState(() => _statusFilter = value),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: 6),
          CompactSearchField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            hintText: 'Search employee, company, admin, or reason',
          ),
          if (companyFilter != _allCompanies) ...[
            const SizedBox(height: 6),
            Text(
              'Showing requests for $companyFilter'
              '${pendingCount > 0 ? ' · $pendingCount pending' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (_loading)
            const AppLoadingView(
              title: 'Loading requests',
              message: 'Fetching pending requests…',
            )
          else if (_error != null)
            _MessageCard(icon: Icons.error_outline, message: _error!)
          else if (filtered.isEmpty)
            const _MessageCard(
              icon: Icons.inbox_outlined,
              message: 'No requests match the current filters.',
            )
          else
            for (final item in filtered)
              if (item.leave != null)
                KeyedSubtree(
                  key: _isFocused(item) ? _focusKey : ValueKey('leave-${item.leave!.id}'),
                  child: _LeaveRequestCard(
                    request: item.leave!,
                    highlighted: _isFocused(item),
                    onApprove: item.leave!.status.toLowerCase() == 'pending'
                        ? () => _updateLeaveStatus(item.leave!, 'approved')
                        : null,
                    onReject: item.leave!.status.toLowerCase() == 'pending'
                        ? () => _updateLeaveStatus(item.leave!, 'rejected')
                        : null,
                  ),
                )
              else if (item.timeEdit != null)
                KeyedSubtree(
                  key: _isFocused(item)
                      ? _focusKey
                      : ValueKey('time-${item.timeEdit!.id}'),
                  child: _TimeEditRequestCard(
                    request: item.timeEdit!,
                    highlighted: _isFocused(item),
                    onApprove: item.timeEdit!.isPending
                        ? () => _approveTimeChange(item.timeEdit!)
                        : null,
                    onReject: item.timeEdit!.isPending
                        ? () => _rejectTimeChange(item.timeEdit!)
                        : null,
                  ),
                )
              else if (item.clock != null)
                KeyedSubtree(
                  key: _isFocused(item)
                      ? _focusKey
                      : ValueKey('clock-${item.clock!.id}'),
                  child: _ClockRequestCard(
                    request: item.clock!,
                    highlighted: _isFocused(item),
                    onApprove: item.clock!.isPending
                        ? () => _approveClock(item.clock!)
                        : null,
                    onReject: item.clock!.isPending
                        ? () => _rejectClock(item.clock!)
                        : null,
                  ),
                ),
        ],
      ),
    );
  }
}

class _UnifiedRequest {
  const _UnifiedRequest._({
    required this.status,
    required this.createdAt,
    required this.sortKey,
    required this.searchText,
    required this.companyId,
    required this.companyDocumentId,
    required this.companyName,
    this.leave,
    this.timeEdit,
    this.clock,
  });

  factory _UnifiedRequest.leave(LeaveRequest leave) {
    return _UnifiedRequest._(
      leave: leave,
      status: leave.status,
      createdAt: leave.createdAt,
      sortKey: leave.startDate,
      companyId: leave.companyId,
      companyDocumentId: leave.companyDocumentId,
      companyName: leave.companyName,
      searchText: [
        leave.username,
        leave.userEmail,
        leave.companyName,
        leave.reason,
        'leave',
      ].join(' ').toLowerCase(),
    );
  }

  factory _UnifiedRequest.timeEdit(TimeCardChangeRequest change) {
    return _UnifiedRequest._(
      timeEdit: change,
      status: change.status,
      createdAt: change.createdAt,
      sortKey: change.workDate,
      companyId: change.companyId,
      companyDocumentId: change.companyDocumentId,
      companyName: change.companyName,
      searchText: [
        change.employeeName,
        change.employeeEmail,
        change.companyName,
        change.requesterName,
        change.requesterEmail,
        'time',
        'edit',
      ].join(' ').toLowerCase(),
    );
  }

  factory _UnifiedRequest.clock(ClockRequest clock) {
    return _UnifiedRequest._(
      clock: clock,
      status: clock.status,
      createdAt: clock.createdAt ?? clock.requestedAt,
      sortKey: clock.workDate,
      companyId: clock.companyId,
      companyDocumentId: clock.companyDocumentId,
      companyName: clock.companyName,
      searchText: [
        clock.username,
        clock.userEmail,
        clock.companyName,
        clock.typeLabel,
        clock.workDate,
        'clock',
        'time in',
        'time out',
      ].join(' ').toLowerCase(),
    );
  }

  final LeaveRequest? leave;
  final TimeCardChangeRequest? timeEdit;
  final ClockRequest? clock;
  final String status;
  final DateTime? createdAt;
  final String sortKey;
  final String searchText;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'approved':
      return AppColors.success;
    case 'rejected':
      return AppColors.error;
    default:
      return const Color(0xFFD97706);
  }
}

String _statusLabel(String status) {
  if (status.isEmpty) return 'Pending';
  return '${status[0].toUpperCase()}${status.substring(1)}';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _RequestActions extends StatelessWidget {
  const _RequestActions({
    required this.onApprove,
    required this.onReject,
  });

  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    if (onApprove == null && onReject == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (onReject != null)
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('Reject'),
              ),
            ),
          if (onReject != null && onApprove != null) const SizedBox(width: 8),
          if (onApprove != null)
            Expanded(
              child: FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('Approve'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClockRequestCard extends StatelessWidget {
  const _ClockRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
  });

  final ClockRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final name = request.username.isEmpty ? 'Employee' : request.username;
    final email = request.userEmail.isEmpty ? '—' : request.userEmail;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;
    final when = request.requestedAt.toLocal();
    final stamp =
        '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')} '
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted ? AppColors.primaryDark : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.typeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Work date ${request.workDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
          ),
          Text(
            'Requested time $stamp',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
          ),
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }
}

class _LeaveRequestCard extends StatelessWidget {
  const _LeaveRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
  });

  final LeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final name = request.username.isEmpty ? 'Employee' : request.username;
    final email = request.userEmail.isEmpty ? '—' : request.userEmail;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted
              ? AppColors.primaryDark
              : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leave request',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '${request.startDate} → ${request.endDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
          ),
          if (request.createdAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Requested ${_formatRequestWhen(request.createdAt!)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: 10,
                  ),
            ),
          ],
          if (request.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              request.reason.trim(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }

  String _formatRequestWhen(DateTime value) {
    final local = value.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _TimeEditRequestCard extends StatelessWidget {
  const _TimeEditRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    this.highlighted = false,
  });

  final TimeCardChangeRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final employee =
        request.employeeName.isEmpty ? 'Employee' : request.employeeName;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;
    final requester =
        request.requesterName.isEmpty ? 'Admin' : request.requesterName;

    return Container(
      margin: EdgeInsets.only(bottom: density.cardGap),
      padding: density.cardPadding,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(
          color: highlighted ? AppColors.primaryDark : colors.border,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlighted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'From notification',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time card change',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      employee,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      request.employeeEmail.isEmpty
                          ? '—'
                          : request.employeeEmail,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            company,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Requested by $requester',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Date: ${request.workDate}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Current: ${request.hasPriorRecord ? '${request.currentTimeInLabel} → ${request.currentTimeOutLabel}' : 'No prior record'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontSize: 10,
                ),
          ),
          Text(
            'Proposed: ${request.proposedTimeInLabel} → ${request.proposedTimeOutLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
          ),
          _RequestActions(onApprove: onApprove, onReject: onReject),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      decoration: compactCardDecoration(context),
      child: Column(
        children: [
          Icon(icon, size: 28, color: colors.textSecondary),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
