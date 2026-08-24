import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../models/company_model.dart';
import '../../models/company_task.dart';
import '../../providers/company_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SuperAdminTaskListsScreen extends StatefulWidget {
  const SuperAdminTaskListsScreen({super.key});

  @override
  State<SuperAdminTaskListsScreen> createState() =>
      _SuperAdminTaskListsScreenState();
}

class _SuperAdminTaskListsScreenState extends State<SuperAdminTaskListsScreen> {
  final _search = TextEditingController();
  String? _companyFilter;
  String? _roleFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadAllTasks();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> _roleNames(CompanyProvider companies) {
    final names = <String>{};
    for (final item in companies.allTasks) {
      final name = item.task.roleName.trim();
      if (name.isNotEmpty) names.add(name);
    }
    final sorted = names.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  List<CompanyTaskListing> _filtered(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    final role = _roleFilter?.trim();
    final companyId = _companyFilter;

    return companies.allTasks.where((item) {
      if (companyId != null &&
          companyId.isNotEmpty &&
          item.company.id != companyId) {
        return false;
      }
      if (role != null &&
          role.isNotEmpty &&
          item.task.roleName.trim().toLowerCase() != role.toLowerCase()) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.task.title.toLowerCase().contains(query) ||
          item.task.description.toLowerCase().contains(query) ||
          item.task.roleName.toLowerCase().contains(query) ||
          item.company.name.toLowerCase().contains(query) ||
          item.company.companyId.toLowerCase().contains(query);
    }).toList();
  }

  String? _selectedCompanyName(CompanyProvider companies) {
    final id = _companyFilter;
    if (id == null) return null;
    for (final company in companies.companies) {
      if (company.id == id) return company.name;
    }
    return null;
  }

  void _clearFilters() {
    setState(() {
      _companyFilter = null;
      _roleFilter = null;
      _search.clear();
    });
  }

  Future<void> _addTask() async {
    final companies = context.read<CompanyProvider>();
    if (companies.companies.isEmpty) {
      await companies.loadCompanies();
    }
    if (!mounted) return;
    if (companies.companies.isEmpty) {
      SnackBarHelper.showInfo(context, 'Create a company first.');
      return;
    }

    final saved = await showModalBottomSheet<(String, String, String, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddTaskSheet(companies: companies.companies),
    );
    if (saved == null || !mounted) return;

    final ok = await companies.addCompanyTask(
      companyId: saved.$1,
      title: saved.$2,
      description: saved.$3,
      roleId: saved.$4,
      roleName: saved.$5,
    );
    if (!mounted) return;
    if (ok) {
      await companies.loadAllTasks();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, 'Task added.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not add the task.',
      );
    }
  }

  void _openTask(CompanyTaskListing item) {
    Navigator.of(context).pushNamed(
      AppRoutes.superAdminTaskDetails,
      arguments: item,
    );
  }

  Future<void> _deleteTask(CompanyTaskListing item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task'),
        content: Text(
          'Delete "${item.task.title}" from ${item.company.name}?',
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
    final ok = await companies.deleteCompanyTask(
      companyId: item.company.id,
      taskId: item.task.id,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(context, 'Task deleted.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not delete the task.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final roleNames = _roleNames(companies);
    final tasks = _filtered(companies);
    final total = companies.allTasks.length;
    final hasSearch = _search.text.trim().isNotEmpty;
    final hasFilters =
        _companyFilter != null || _roleFilter != null || hasSearch;
    final companyFilterName = _selectedCompanyName(companies);

    return DashboardScaffold(
      title: 'Task lists',
      currentRoute: AppRoutes.superAdminTasks,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Task lists',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Browse company tasks. Filter by company or role, then tap to edit.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _SummaryCard(
                    total: total,
                    showing: tasks.length,
                    companyFilter: companyFilterName,
                    roleFilter: _roleFilter,
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
                        child: roleNames.isEmpty
                            ? _FilterDropdownShell(
                                label: 'Role',
                                icon: Icons.badge_outlined,
                                value: 'No roles yet',
                                enabled: false,
                                muted: true,
                                onTap: () {},
                              )
                            : _RoleNameFilterDropdown(
                                roleNames: roleNames,
                                selected: _roleFilter,
                                onSelected: (name) =>
                                    setState(() => _roleFilter = name),
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
                            hintText: 'Search task, company, or ID',
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
                        onPressed: companies.isLoading ? null : _addTask,
                        icon: const Icon(Icons.add_task_rounded, size: 18),
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
                  icon: Icons.task_alt_rounded,
                  title: 'No tasks yet',
                  message: 'Add a task for a company to get started.',
                  actionLabel: 'Add task',
                  onAction: companies.isLoading ? null : _addTask,
                ),
              ),
            )
          else if (tasks.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverToBoxAdapter(
                child: _EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'No matching tasks',
                  message:
                      'Try another company, role filter, or clear your search.',
                  actionLabel: 'Clear filters',
                  onAction: _clearFilters,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList.builder(
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final item = tasks[index];
                  return _TaskCard(
                    item: item,
                    logoBytes: companies.logoFor(item.company.id),
                    onTap: () => _openTask(item),
                    onDelete: () => _deleteTask(item),
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
    required this.roleFilter,
    required this.hasFilters,
  });

  final int total;
  final int showing;
  final String? companyFilter;
  final String? roleFilter;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final countLabel =
        hasFilters ? 'Showing $showing of $total' : '$total tasks';
    final filterParts = [
      ?companyFilter,
      ?roleFilter,
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
              Icons.task_alt_rounded,
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

class _RoleNameFilterDropdown extends StatelessWidget {
  const _RoleNameFilterDropdown({
    required this.roleNames,
    required this.selected,
    required this.onSelected,
  });

  final List<String> roleNames;
  final String? selected;
  final ValueChanged<String?> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _RoleNameFilterPickerSheet(
        roleNames: roleNames,
        selected: selected,
      ),
    );
    if (picked == null) return;
    onSelected(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return _FilterDropdownShell(
      label: 'Role',
      icon: Icons.badge_outlined,
      muted: selected == null,
      value: selected ?? 'All roles',
      onTap: () => _openPicker(context),
    );
  }
}

class _RoleNameFilterPickerSheet extends StatefulWidget {
  const _RoleNameFilterPickerSheet({
    required this.roleNames,
    required this.selected,
  });

  final List<String> roleNames;
  final String? selected;

  @override
  State<_RoleNameFilterPickerSheet> createState() =>
      _RoleNameFilterPickerSheetState();
}

class _RoleNameFilterPickerSheetState extends State<_RoleNameFilterPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.roleNames;
    return widget.roleNames
        .where((name) => name.toLowerCase().contains(needle))
        .toList();
  }

  bool _isSelected(String name) {
    return widget.selected?.toLowerCase() == name.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;
    final allSelected = widget.selected == null;

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
              'Filter by role',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Search role names linked to tasks.',
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
                hintText: 'Search roles...',
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
                        'No roles match that search.',
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
                                Icons.badge_outlined,
                                color: colors.textSecondary,
                                size: 22,
                              ),
                              title: const Text('All roles'),
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
                        final name = items[index - 1];
                        final selected = _isSelected(name);
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
                            leading: Icon(
                              Icons.badge_outlined,
                              color: colors.textSecondary,
                              size: 22,
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primaryDark,
                                    size: 20,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, name),
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

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.item,
    required this.logoBytes,
    required this.onTap,
    required this.onDelete,
  });

  final CompanyTaskListing item;
  final Uint8List? logoBytes;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final task = item.task;

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
                        task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          task.description,
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
                          if (task.roleName.isNotEmpty)
                            _MiniChip(
                              label: task.roleName,
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
                  tooltip: 'Open task',
                  visualDensity: VisualDensity.compact,
                  onPressed: onTap,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Delete task',
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

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet({required this.companies});

  final List<CompanyModel> companies;

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  late String _companyId;
  late String _roleId;
  List<CompanyJobRole> _roles = [];
  bool _loadingRoles = false;

  @override
  void initState() {
    super.initState();
    _companyId = widget.companies.first.id;
    _roleId = '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoles());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  CompanyModel? _companyById(String id) {
    for (final company in widget.companies) {
      if (company.id == id) return company;
    }
    return null;
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    final provider = context.read<CompanyProvider>();
    await provider.loadCompanyRoles(_companyId);
    if (!mounted) return;
    final roles = [...provider.roles];
    setState(() {
      _roles = roles;
      _loadingRoles = false;
      if (roles.isEmpty) {
        _roleId = '';
      } else if (!roles.any((role) => role.id == _roleId)) {
        _roleId = roles.first.id;
      }
    });
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_roleId.isEmpty) return;
    CompanyJobRole? role;
    for (final item in _roles) {
      if (item.id == _roleId) {
        role = item;
        break;
      }
    }
    if (role == null) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop((
      _companyId,
      _title.text.trim(),
      _description.text.trim(),
      role.id,
      role.name,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final company = _companyById(_companyId);

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
                'Add task',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                company == null
                    ? 'Choose a company and role for this task.'
                    : 'This task will be saved to ${company.name}.',
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
                  _loadRoles();
                },
              ),
              const SizedBox(height: 12),
              if (_loadingRoles)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                )
              else if (_roles.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.inputFill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'No roles for this company yet. Add roles on the company page first.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey('role-$_roleId'),
                  initialValue: _roles.any((role) => role.id == _roleId)
                      ? _roleId
                      : _roles.first.id,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [
                    for (final role in _roles)
                      DropdownMenuItem(
                        value: role.id,
                        child: Text(role.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _roleId = value);
                  },
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _title,
                  label: 'Task name',
                  hint: 'e.g. Count inventory',
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Task name is required.';
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
                  label: 'Save task',
                  onPressed: _save,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
