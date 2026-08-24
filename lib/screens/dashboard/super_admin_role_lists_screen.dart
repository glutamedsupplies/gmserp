import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../models/company_model.dart';
import '../../providers/company_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SuperAdminRoleListsScreen extends StatefulWidget {
  const SuperAdminRoleListsScreen({super.key});

  @override
  State<SuperAdminRoleListsScreen> createState() =>
      _SuperAdminRoleListsScreenState();
}

enum _TaskLinkFilter { all, withTasks, withoutTasks }

extension _TaskLinkFilterUi on _TaskLinkFilter {
  String get label {
    switch (this) {
      case _TaskLinkFilter.all:
        return 'All roles';
      case _TaskLinkFilter.withTasks:
        return 'With tasks';
      case _TaskLinkFilter.withoutTasks:
        return 'No tasks';
    }
  }

  IconData get icon {
    switch (this) {
      case _TaskLinkFilter.all:
        return Icons.task_alt_outlined;
      case _TaskLinkFilter.withTasks:
        return Icons.playlist_add_check_rounded;
      case _TaskLinkFilter.withoutTasks:
        return Icons.playlist_remove_rounded;
    }
  }
}

class _SuperAdminRoleListsScreenState extends State<SuperAdminRoleListsScreen> {
  final _search = TextEditingController();
  String? _companyFilter;
  _TaskLinkFilter _taskLinkFilter = _TaskLinkFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadAllRoles();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, int> _taskCountLookup(CompanyProvider companies) {
    final counts = <String, int>{};
    for (final listing in companies.allTasks) {
      final key = '${listing.company.id}:${listing.task.roleId}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  int _taskCountForRole(
    Map<String, int> lookup,
    CompanyRoleListing item,
  ) {
    return lookup['${item.company.id}:${item.role.id}'] ?? 0;
  }

  List<CompanyRoleListing> _filtered(
    CompanyProvider companies,
    Map<String, int> taskCounts,
  ) {
    final query = _search.text.trim().toLowerCase();
    final companyId = _companyFilter;

    return companies.allRoles.where((item) {
      if (companyId != null &&
          companyId.isNotEmpty &&
          item.company.id != companyId) {
        return false;
      }
      final count = _taskCountForRole(taskCounts, item);
      switch (_taskLinkFilter) {
        case _TaskLinkFilter.withTasks:
          if (count == 0) return false;
        case _TaskLinkFilter.withoutTasks:
          if (count > 0) return false;
        case _TaskLinkFilter.all:
          break;
      }
      if (query.isEmpty) return true;
      return item.role.name.toLowerCase().contains(query) ||
          item.role.description.toLowerCase().contains(query) ||
          item.company.name.toLowerCase().contains(query) ||
          item.company.companyId.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _addRole() async {
    final companies = context.read<CompanyProvider>();
    if (companies.companies.isEmpty) {
      await companies.loadCompanies();
    }
    if (!mounted) return;
    if (companies.companies.isEmpty) {
      SnackBarHelper.showInfo(context, 'Create a company first.');
      return;
    }

    final saved = await showModalBottomSheet<(String, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddRoleSheet(companies: companies.companies),
    );
    if (saved == null || !mounted) return;

    final ok = await companies.addCompanyRole(
      companyId: saved.$1,
      name: saved.$2,
      description: saved.$3,
    );
    if (!mounted) return;
    if (ok) {
      await companies.loadAllRoles();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, 'Role added.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not add the role.',
      );
    }
  }

  Future<void> _deleteRole(CompanyRoleListing item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete role'),
        content: Text(
          'Delete "${item.role.name}" from ${item.company.name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final companies = context.read<CompanyProvider>();
    await companies.loadCompanyUsers(item.company.id);
    if (!mounted) return;

    final ok = await companies.deleteCompanyRole(
      companyId: item.company.id,
      roleId: item.role.id,
    );
    if (!mounted) return;
    if (ok) {
      await companies.loadAllRoles();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, 'Role deleted.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not delete the role.',
      );
    }
  }

  String? _selectedCompanyName(CompanyProvider companies) {
    final id = _companyFilter;
    if (id == null) return null;
    for (final company in companies.companies) {
      if (company.id == id) return company.name;
    }
    return null;
  }

  String? _taskLinkFilterLabel(_TaskLinkFilter filter) {
    if (filter == _TaskLinkFilter.all) return null;
    return filter.label;
  }

  void _clearFilters() {
    setState(() {
      _companyFilter = null;
      _taskLinkFilter = _TaskLinkFilter.all;
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final taskCounts = _taskCountLookup(companies);
    final roles = _filtered(companies, taskCounts);
    final total = companies.allRoles.length;
    final hasSearch = _search.text.trim().isNotEmpty;
    final hasFilters = _companyFilter != null ||
        _taskLinkFilter != _TaskLinkFilter.all ||
        hasSearch;
    final companyFilterName = _selectedCompanyName(companies);
    final taskFilterName = _taskLinkFilterLabel(_taskLinkFilter);

    return DashboardScaffold(
      title: 'Role lists',
      currentRoute: AppRoutes.superAdminRoles,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Role lists',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every job role across companies. Filter by company or tasks, then tap to edit.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    total: total,
                    showing: roles.length,
                    companyFilter: companyFilterName,
                    taskFilter: taskFilterName,
                    hasFilters: hasFilters,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: companies.companies.isEmpty
                            ? _FilterDropdownShell(
                                label: 'Company',
                                icon: Icons.business_rounded,
                                value: 'No companies yet',
                                enabled: false,
                                muted: true,
                                onTap: () {},
                              )
                            : _CompanyFilterDropdown(
                                companies: companies.companies,
                                selectedId: _companyFilter,
                                logoFor: companies.logoFor,
                                onSelected: (id) =>
                                    setState(() => _companyFilter = id),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TaskLinkFilterDropdown(
                          selected: _taskLinkFilter,
                          onSelected: (value) =>
                              setState(() => _taskLinkFilter = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search role, company, or ID',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      _search.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded,
                                        size: 20),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: companies.isLoading ? null : _addRole,
                        icon: const Icon(Icons.badge_outlined, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          if (companies.isLoading)
            const SliverPadding(
              padding: EdgeInsets.only(top: 28),
              sliver: SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (total == 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No roles yet',
                  message: 'Add a role for a company to get started.',
                  actionLabel: 'Add role',
                  onAction: companies.isLoading ? null : _addRole,
                ),
              ),
            )
          else if (roles.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'No matching roles',
                  message:
                      'Try another company, task filter, or clear your search.',
                  actionLabel: 'Clear filters',
                  onAction: _clearFilters,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.builder(
                itemCount: roles.length,
                itemBuilder: (context, index) {
                  final item = roles[index];
                  final taskCount = _taskCountForRole(taskCounts, item);
                  return _RoleCard(
                    item: item,
                    taskCount: taskCount,
                    logoBytes: companies.logoFor(item.company.id),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        AppRoutes.superAdminRoleDetails,
                        arguments: item,
                      );
                    },
                    onDelete: () => _deleteRole(item),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.showing,
    required this.companyFilter,
    required this.taskFilter,
    required this.hasFilters,
  });

  final int total;
  final int showing;
  final String? companyFilter;
  final String? taskFilter;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final countLabel =
        hasFilters ? 'Showing $showing of $total' : '$total roles';
    final filterParts = [
      ?companyFilter,
      ?taskFilter,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.badge_outlined,
              color: AppColors.primaryDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (filterParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    filterParts.join(' • '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdownShell extends StatelessWidget {
  const _FilterDropdownShell({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.muted = false,
    this.leading,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final bool enabled;
  final bool muted;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: colors.inputFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            fillColor: colors.inputFill,
            contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: enabled ? colors.textSecondary : colors.textHint,
            ),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                Icon(
                  icon,
                  size: 20,
                  color: colors.textSecondary,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: muted || !enabled
                            ? colors.textHint
                            : colors.textPrimary,
                        fontSize: 14,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyFilterDropdown extends StatelessWidget {
  const _CompanyFilterDropdown({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
    required this.onSelected,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;
  final ValueChanged<String?> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CompanyFilterPickerSheet(
        companies: companies,
        selectedId: selectedId,
        logoFor: logoFor,
      ),
    );
    if (picked == null) return;
    onSelected(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    CompanyModel? selected;
    for (final company in companies) {
      if (company.id == selectedId) {
        selected = company;
        break;
      }
    }

    return _FilterDropdownShell(
      label: 'Company',
      icon: Icons.business_rounded,
      muted: selected == null,
      leading: selected == null
          ? null
          : UserAvatar(
              bytes: logoFor(selected.id),
              name: selected.name,
              size: 24,
            ),
      value: selected == null
          ? 'All companies'
          : '${selected.name}  •  ${selected.companyId}',
      onTap: () => _openPicker(context),
    );
  }
}

class _CompanyFilterPickerSheet extends StatefulWidget {
  const _CompanyFilterPickerSheet({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;

  @override
  State<_CompanyFilterPickerSheet> createState() =>
      _CompanyFilterPickerSheetState();
}

class _CompanyFilterPickerSheetState extends State<_CompanyFilterPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CompanyModel> get _filtered {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.companies;
    return widget.companies.where((company) {
      return company.name.toLowerCase().contains(needle) ||
          company.companyId.toLowerCase().contains(needle) ||
          company.id.toLowerCase().contains(needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;
    final allSelected = widget.selectedId == null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Filter by company',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Search by company name or ID.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search companies...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No companies match that search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length + 1,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Material(
                            color: allSelected
                                ? AppColors.primary.withValues(alpha: 0.16)
                                : colors.inputFill,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              dense: true,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: allSelected
                                      ? AppColors.primary
                                      : colors.border,
                                ),
                              ),
                              leading: Icon(
                                Icons.business_rounded,
                                color: colors.textSecondary,
                                size: 28,
                              ),
                              title: const Text('All companies'),
                              trailing: allSelected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primaryDark,
                                      size: 20,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, ''),
                            ),
                          );
                        }
                        final company = items[index - 1];
                        final selected = company.id == widget.selectedId;
                        return Material(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : colors.inputFill,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : colors.border,
                              ),
                            ),
                            leading: UserAvatar(
                              bytes: widget.logoFor(company.id),
                              name: company.name,
                              size: 36,
                            ),
                            title: Text(
                              company.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('ID: ${company.companyId}'),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primaryDark,
                                    size: 20,
                                  )
                                : null,
                            onTap: () =>
                                Navigator.pop(context, company.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskLinkFilterDropdown extends StatelessWidget {
  const _TaskLinkFilterDropdown({
    required this.selected,
    required this.onSelected,
  });

  final _TaskLinkFilter selected;
  final ValueChanged<_TaskLinkFilter> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<_TaskLinkFilter>(
      context: context,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _TaskLinkFilterPickerSheet(selected: selected),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    return _FilterDropdownShell(
      label: 'Tasks',
      icon: selected.icon,
      muted: selected == _TaskLinkFilter.all,
      value: selected.label,
      onTap: () => _openPicker(context),
    );
  }
}

class _TaskLinkFilterPickerSheet extends StatelessWidget {
  const _TaskLinkFilterPickerSheet({required this.selected});

  final _TaskLinkFilter selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const options = _TaskLinkFilter.values;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Filter by tasks',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Show roles based on linked tasks.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(height: 6),
              _TaskLinkFilterOption(
                filter: options[index],
                selected: options[index] == selected,
                onTap: () => Navigator.pop(context, options[index]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskLinkFilterOption extends StatelessWidget {
  const _TaskLinkFilterOption({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _TaskLinkFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.16)
          : colors.inputFill,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.primary : colors.border,
          ),
        ),
        leading: Icon(
          filter.icon,
          color: colors.textSecondary,
          size: 22,
        ),
        title: Text(filter.label),
        trailing: selected
            ? const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primaryDark,
                size: 20,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.item,
    required this.taskCount,
    required this.logoBytes,
    required this.onTap,
    required this.onDelete,
  });

  final CompanyRoleListing item;
  final int taskCount;
  final Uint8List? logoBytes;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final role = item.role;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  bytes: logoBytes,
                  name: item.company.name,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (role.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          role.description,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    fontSize: 13,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniChip(
                            label:
                                '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                            fill: AppColors.primary.withValues(alpha: 0.16),
                            bold: true,
                          ),
                          _MiniChip(
                            label: item.company.name,
                            fill: colors.inputFill,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit role',
                  visualDensity: VisualDensity.compact,
                  onPressed: onTap,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete role',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.error,
                    size: 20,
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

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.fill,
    this.bold = false,
  });

  final String label;
  final Color fill;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: colors.textSecondary),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }
}

class _AddRoleSheet extends StatefulWidget {
  const _AddRoleSheet({required this.companies});

  final List<CompanyModel> companies;

  @override
  State<_AddRoleSheet> createState() => _AddRoleSheetState();
}

class _AddRoleSheetState extends State<_AddRoleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  late String _companyId;

  @override
  void initState() {
    super.initState();
    _companyId = widget.companies.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop((
      _companyId,
      _name.text.trim(),
      _description.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Add role',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a job role for a company. Tasks can be linked to it later.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey('company-$_companyId'),
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'Company'),
                items: [
                  for (final item in widget.companies)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _companyId = value);
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _name,
                label: 'Role name',
                hint: 'e.g. Cashier',
                textInputAction: TextInputAction.next,
                autofocus: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Role name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _description,
                label: 'Description',
                hint: 'Optional details',
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save role',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
