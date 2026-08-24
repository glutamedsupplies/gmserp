import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_change_request.dart';
import '../../providers/company_provider.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../widgets/dashboard_scaffold.dart';

class SuperAdminRequestsScreen extends StatefulWidget {
  const SuperAdminRequestsScreen({super.key});

  @override
  State<SuperAdminRequestsScreen> createState() =>
      _SuperAdminRequestsScreenState();
}

class _SuperAdminRequestsScreenState extends State<SuperAdminRequestsScreen> {
  final _leaveRepo = LeaveRequestRepository();
  final _timeChangeRepo = TimeCardChangeRequestRepository();
  final _searchController = TextEditingController();

  List<LeaveRequest> _leaveRequests = [];
  List<TimeCardChangeRequest> _timeRequests = [];
  bool _loading = true;
  String? _error;
  String _companyFilter = 'All';
  String _typeFilter = 'All';
  String _statusFilter = 'All';
  String _search = '';

  static const _allCompanies = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanies();
    });
    _load();
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
      ]);
      if (!mounted) return;
      setState(() {
        _leaveRequests = results[0] as List<LeaveRequest>;
        _timeRequests = results[1] as List<TimeCardChangeRequest>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _leaveRequests = [];
        _timeRequests = [];
        _loading = false;
        _error = 'Unable to load requests.';
      });
    }
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

    return DashboardScaffold(
      title: 'Requests',
      currentRoute: AppRoutes.superAdminRequests,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Requests',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Review leave requests and admin time-card change requests.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          _SummaryStrip(
            total: _leaveRequests.length + _timeRequests.length,
            pending: [
              ..._leaveRequests.where((r) => r.status.toLowerCase() == 'pending'),
              ..._timeRequests.where((r) => r.isPending),
            ].length,
            showing: filtered.length,
          ),
          const SizedBox(height: 12),
          _FilterDropdown(
            value: companyFilter,
            items: companyOptions,
            hint: 'Company',
            onChanged: (value) => setState(() => _companyFilter = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _FilterDropdown(
                  value: _typeFilter,
                  items: const ['All', 'Leave', 'Time edit'],
                  hint: 'Type',
                  onChanged: (value) => setState(() => _typeFilter = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterDropdown(
                  value: _statusFilter,
                  items: const ['All', 'Pending', 'Approved', 'Rejected'],
                  hint: 'Status',
                  onChanged: (value) => setState(() => _statusFilter = value),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search employee, company, admin, or reason',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
            ),
          ),
          if (companyFilter != _allCompanies) ...[
            const SizedBox(height: 8),
            Text(
              'Showing requests for $companyFilter'
              '${pendingCount > 0 ? ' · $pendingCount pending' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _MessageCard(icon: Icons.error_outline, message: _error!)
          else if (filtered.isEmpty)
            const _MessageCard(
              icon: Icons.inbox_outlined,
              message: 'No requests match the current filters.',
            )
          else
            for (final item in filtered) ...[
              if (item.leave != null)
                _LeaveRequestCard(
                  request: item.leave!,
                  onApprove: item.leave!.status.toLowerCase() == 'pending'
                      ? () => _updateLeaveStatus(item.leave!, 'approved')
                      : null,
                  onReject: item.leave!.status.toLowerCase() == 'pending'
                      ? () => _updateLeaveStatus(item.leave!, 'rejected')
                      : null,
                )
              else if (item.timeEdit != null)
                _TimeEditRequestCard(
                  request: item.timeEdit!,
                  onApprove: item.timeEdit!.isPending
                      ? () => _approveTimeChange(item.timeEdit!)
                      : null,
                  onReject: item.timeEdit!.isPending
                      ? () => _rejectTimeChange(item.timeEdit!)
                      : null,
                ),
              const SizedBox(height: 10),
            ],
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

  final LeaveRequest? leave;
  final TimeCardChangeRequest? timeEdit;
  final String status;
  final DateTime? createdAt;
  final String sortKey;
  final String searchText;
  final String companyId;
  final String companyDocumentId;
  final String companyName;
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final displayValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: displayValue,
          isExpanded: true,
          hint: hint == null ? null : Text(hint!),
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(
                  item == 'All' && hint != null
                      ? (hint == 'Company'
                          ? 'All companies'
                          : 'All ${hint!.toLowerCase()}s')
                      : item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.pending,
    required this.showing,
  });

  final int total;
  final int pending;
  final int showing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          _SummaryItem(label: 'Total', value: '$total'),
          _SummaryItem(label: 'Pending', value: '$pending'),
          _SummaryItem(label: 'Showing', value: '$showing'),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (onReject != null)
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
                child: const Text('Reject'),
              ),
            ),
          if (onReject != null && onApprove != null) const SizedBox(width: 10),
          if (onApprove != null)
            Expanded(
              child: FilledButton(
                onPressed: onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Approve'),
              ),
            ),
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
  });

  final LeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final name = request.username.isEmpty ? 'Employee' : request.username;
    final email = request.userEmail.isEmpty ? '—' : request.userEmail;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leave request',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            company,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '${request.startDate} → ${request.endDate}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (request.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.reason.trim()),
          ],
          _RequestActions(onApprove: onApprove, onReject: onReject),
        ],
      ),
    );
  }
}

class _TimeEditRequestCard extends StatelessWidget {
  const _TimeEditRequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final TimeCardChangeRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final employee =
        request.employeeName.isEmpty ? 'Employee' : request.employeeName;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;
    final requester =
        request.requesterName.isEmpty ? 'Admin' : request.requesterName;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time card change',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      request.employeeEmail.isEmpty
                          ? '—'
                          : request.employeeEmail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            company,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Requested by $requester',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Date: ${request.workDate}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Current: ${request.hasPriorRecord ? '${request.currentTimeInLabel} → ${request.currentTimeOutLabel}' : 'No prior record'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          Text(
            'Proposed: ${request.proposedTimeInLabel} → ${request.proposedTimeOutLabel}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colors.textSecondary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
