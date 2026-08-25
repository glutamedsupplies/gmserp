import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/time_card_change_request.dart';
import '../../providers/auth_provider.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
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
    final density = CompactPageStyle.of(context);
    final filtered = _filtered;
    final pending =
        _requests.where((r) => r.isPending).length;

    return DashboardScaffold(
      title: 'Submitted requests',
      currentRoute: AppRoutes.adminSubmittedRequests,
      child: ListView(
        padding: density.pagePadding,
        children: [
          const CompactPageHeader(
            title: 'Submitted requests',
            subtitle:
                'Track time-card change requests you sent to Super Admin.',
          ),
          SizedBox(height: density.sectionGap),
          CompactSummaryStrip(
            items: [
              CompactSummaryItem(label: 'Total', value: '${_requests.length}'),
              CompactSummaryItem(label: 'Pending', value: '$pending'),
              CompactSummaryItem(label: 'Showing', value: '${filtered.length}'),
            ],
          ),
          SizedBox(height: density.cardGap),
          Row(
            children: [
              Expanded(
                child: CompactFilterDropdown(
                  value: _statusFilter,
                  items: const ['All', 'Pending', 'Approved', 'Rejected'],
                  onChanged: (value) => setState(() => _statusFilter = value),
                  hint: 'Status',
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
          SizedBox(height: density.sectionGap),
          if (_loading)
            const AppLoadingView(
              title: 'Loading requests',
              message: 'Fetching submitted leave requests…',
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
              SizedBox(height: density.cardGap),
            ],
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
    final density = CompactPageStyle.of(context);
    final statusColor = _statusColor(request.status);
    final employee =
        request.employeeName.isEmpty ? 'Employee' : request.employeeName;
    final company =
        request.companyName.isEmpty ? 'Unknown company' : request.companyName;

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
    final density = CompactPageStyle.of(context);
    return Container(
      padding: density.compact
          ? const EdgeInsets.fromLTRB(14, 22, 14, 22)
          : const EdgeInsets.fromLTRB(16, 28, 16, 28),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(density.radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: density.compact ? 28 : 34,
            color: colors.textSecondary,
          ),
          SizedBox(height: density.cardGap),
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
