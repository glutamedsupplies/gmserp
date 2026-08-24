import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/time_card_change_request.dart';
import '../../providers/auth_provider.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../widgets/dashboard_scaffold.dart';

class AdminSubmittedRequestsScreen extends StatefulWidget {
  const AdminSubmittedRequestsScreen({super.key});

  @override
  State<AdminSubmittedRequestsScreen> createState() =>
      _AdminSubmittedRequestsScreenState();
}

class _AdminSubmittedRequestsScreenState
    extends State<AdminSubmittedRequestsScreen> {
  final _repo = TimeCardChangeRequestRepository();

  List<TimeCardChangeRequest> _requests = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) {
      setState(() {
        _requests = [];
        _loading = false;
        _error = 'Sign in to view submitted requests.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.listByRequester(user.id);
      if (!mounted) return;
      setState(() {
        _requests = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requests = [];
        _loading = false;
        _error = 'Unable to load submitted requests.';
      });
    }
  }

  List<TimeCardChangeRequest> get _filtered {
    if (_statusFilter == 'All') return _requests;
    return _requests
        .where((r) => r.status.toLowerCase() == _statusFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final filtered = _filtered;
    final pending =
        _requests.where((r) => r.isPending).length;

    return DashboardScaffold(
      title: 'Submitted requests',
      currentRoute: AppRoutes.adminSubmittedRequests,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Submitted requests',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Track time-card change requests you sent to Super Admin.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: colors.header,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                _SummaryItem(label: 'Total', value: '${_requests.length}'),
                _SummaryItem(label: 'Pending', value: '$pending'),
                _SummaryItem(label: 'Showing', value: '${filtered.length}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(
                          value: 'Pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'Approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'Rejected',
                          child: Text('Rejected'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _statusFilter = value);
                      },
                    ),
                  ),
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
              icon: Icons.outbox_outlined,
              message: 'No submitted time-change requests yet.',
            )
          else
            for (final request in filtered) ...[
              _SubmittedRequestCard(request: request),
              const SizedBox(height: 10),
            ],
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

class _SubmittedRequestCard extends StatelessWidget {
  const _SubmittedRequestCard({required this.request});

  final TimeCardChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final statusColor = _statusColor(request.status);
    final employee =
        request.employeeName.isEmpty ? 'Employee' : request.employeeName;
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  _statusLabel(request.status),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            company,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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
          if (request.status.toLowerCase() == 'rejected') ...[
            const SizedBox(height: 8),
            Text(
              'Declined — no changes were applied.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ] else if (request.status.toLowerCase() == 'approved') ...[
            const SizedBox(height: 8),
            Text(
              'Approved — time card was updated.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Waiting for Super Admin review.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
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
