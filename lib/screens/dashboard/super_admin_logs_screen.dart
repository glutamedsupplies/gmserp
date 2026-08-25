import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/activity_log_entry.dart';
import '../../providers/company_provider.dart';
import '../../services/activity_log_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class SuperAdminLogsScreen extends StatefulWidget {
  const SuperAdminLogsScreen({super.key});

  @override
  State<SuperAdminLogsScreen> createState() => _SuperAdminLogsScreenState();
}

class _SuperAdminLogsScreenState extends State<SuperAdminLogsScreen> {
  final _repo = ActivityLogRepository();
  final _searchController = TextEditingController();

  List<ActivityLogEntry> _logs = [];
  bool _loading = true;
  String? _error;
  String _companyFilter = 'All';
  String _typeFilter = 'All';
  String _outcomeFilter = 'All';
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
      final logs = await _repo.listResolved();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _logs = [];
        _loading = false;
        _error = 'Unable to load activity logs.';
      });
    }
  }

  List<String> _companyOptions(CompanyProvider companies) {
    final labels = <String>{};
    for (final company in companies.companies) {
      final name = company.name.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    for (final log in _logs) {
      final name = log.companyName.trim();
      if (name.isNotEmpty) labels.add(name);
    }
    final sorted = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCompanies, ...sorted];
  }

  bool _matchesCompany(ActivityLogEntry log, CompanyProvider companies) {
    if (_companyFilter == _allCompanies) return true;
    final selected = _companyFilter.trim().toLowerCase();
    if (log.companyName.trim().toLowerCase() == selected) return true;
    for (final company in companies.companies) {
      if (company.name.trim().toLowerCase() != selected) continue;
      if (log.companyId == company.id ||
          log.companyDocumentId == company.firestoreId) {
        return true;
      }
    }
    return false;
  }

  List<ActivityLogEntry> _filtered(CompanyProvider companies) {
    final query = _search.trim().toLowerCase();
    return _logs.where((log) {
      if (!_matchesCompany(log, companies)) return false;
      if (_typeFilter == 'Time card' && log.kind != ActivityLogKind.timeEdit) {
        return false;
      }
      if (_typeFilter == 'Leave' && log.kind != ActivityLogKind.leave) {
        return false;
      }
      if (_outcomeFilter != 'All' &&
          log.status.toLowerCase() != _outcomeFilter.toLowerCase()) {
        return false;
      }
      if (query.isNotEmpty && !log.searchText.contains(query)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final companyOptions = _companyOptions(companies);
    final companyFilter = companyOptions.contains(_companyFilter)
        ? _companyFilter
        : _allCompanies;
    final filtered = _filtered(companies);
    final approvedCount = filtered.where((l) => l.isApproved).length;
    final rejectedCount = filtered.where((l) => l.isRejected).length;

    return DashboardScaffold(
      title: 'Logs',
      currentRoute: AppRoutes.superAdminLogs,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          const CompactPageHeader(
            title: 'Activity logs',
            subtitle:
                'Approved and rejected time-card edits and leave requests.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          CompactSummaryStrip(
            items: [
              CompactSummaryItem(label: 'Total', value: '${_logs.length}'),
              CompactSummaryItem(
                label: 'Approved',
                value: '$approvedCount',
                color: AppColors.success,
              ),
              CompactSummaryItem(
                label: 'Rejected',
                value: '$rejectedCount',
                color: AppColors.error,
              ),
              CompactSummaryItem(
                label: 'Showing',
                value: '${filtered.length}',
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          CompactFilterDropdown(
            value: companyFilter,
            items: companyOptions,
            hint: 'Company',
            onChanged: (v) => setState(() => _companyFilter = v),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: CompactFilterDropdown(
                  value: _typeFilter,
                  items: const ['All', 'Time card', 'Leave'],
                  hint: 'Type',
                  onChanged: (v) => setState(() => _typeFilter = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: CompactFilterDropdown(
                  value: _outcomeFilter,
                  items: const ['All', 'Approved', 'Rejected'],
                  hint: 'Outcome',
                  onChanged: (v) => setState(() => _outcomeFilter = v),
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
            onChanged: (v) => setState(() => _search = v),
            hintText: 'Search employee, company, admin, date…',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (_loading)
            const AppLoadingView(
              title: 'Loading logs',
              message: 'Fetching activity history…',
            )
          else if (_error != null)
            _EmptyCard(icon: Icons.error_outline, message: _error!)
          else if (filtered.isEmpty)
            const _EmptyCard(
              icon: Icons.history_rounded,
              message: 'No activity matches the current filters.',
            )
          else
            for (final log in filtered) _LogRow(entry: log),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final ActivityLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final statusColor = entry.isApproved
        ? AppColors.success
        : entry.isRejected
            ? AppColors.error
            : colors.textSecondary;
    final kindColor = entry.kind == ActivityLogKind.timeEdit
        ? AppColors.primaryDark
        : const Color(0xFF2563EB);

    return Container(
      margin: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
      padding: CompactPageStyle.of(context).cardPadding,
      decoration: compactCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MiniChip(
                      label: entry.kindLabel,
                      color: kindColor,
                    ),
                    _MiniChip(
                      label: entry.statusLabel,
                      color: statusColor,
                    ),
                    Text(
                      _formatWhen(entry.occurredAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.subjectName.isEmpty ? 'Employee' : entry.subjectName}'
            '${entry.companyName.isEmpty ? '' : ' · ${entry.companyName}'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (entry.kind == ActivityLogKind.timeEdit) ...[
            if (entry.workDate.isNotEmpty)
              Text(
                'Date ${entry.workDate}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
              ),
            if (entry.actorName.isNotEmpty)
              Text(
                'Requested by ${entry.actorName}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 10,
                    ),
              ),
          ],
          if (entry.kind == ActivityLogKind.leave && entry.leaveRange.isNotEmpty)
            Text(
              entry.leaveRange,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: 10,
                  ),
            ),
          const SizedBox(height: 3),
          Text(
            entry.detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime value) {
    final local = value.toLocal();
    final y = local.year;
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

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
