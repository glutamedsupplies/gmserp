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

class _SuperAdminRoleListsScreenState extends State<SuperAdminRoleListsScreen> {
  final _search = TextEditingController();
  String? _companyFilter;

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

  List<CompanyModel> _companiesWithRoles(CompanyProvider companies) {
    final ids = {
      for (final item in companies.allRoles) item.company.id,
    };
    return companies.companies.where((company) => ids.contains(company.id)).toList();
  }

  List<CompanyRoleListing> _filtered(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    final companyId = _companyFilter;

    return companies.allRoles.where((item) {
      if (companyId != null &&
          companyId.isNotEmpty &&
          item.company.id != companyId) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.role.name.toLowerCase().contains(query) ||
          item.role.description.toLowerCase().contains(query) ||
          item.company.name.toLowerCase().contains(query) ||
          item.company.companyId.toLowerCase().contains(query);
    }).toList();
  }

  int _taskCountForRole(CompanyProvider companies, CompanyRoleListing item) {
    return companies.allTasks
        .where(
          (listing) =>
              listing.company.id == item.company.id &&
              listing.task.roleId == item.role.id,
        )
        .length;
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

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final colors = AppColors.of(context);
    final roles = _filtered(companies);
    final total = companies.allRoles.length;
    final companyOptions = _companiesWithRoles(companies);

    return DashboardScaffold(
      title: 'Role lists',
      currentRoute: AppRoutes.superAdminRoles,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Role lists',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Every job role across companies. Tap a role to edit it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _SummaryCard(
            total: total,
            showing: roles.length,
            companyFilter: () {
              if (_companyFilter == null) return null;
              for (final company in companyOptions) {
                if (company.id == _companyFilter) return company.name;
              }
              return null;
            }(),
            hasSearch: _search.text.trim().isNotEmpty,
          ),
          const SizedBox(height: 12),
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
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded, size: 20),
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
          Text(
            'Company',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (companyOptions.isEmpty)
            Text(
              'Companies appear here once roles are created.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _companyFilter == null,
                    onSelected: () => setState(() => _companyFilter = null),
                  ),
                  for (final company in companyOptions) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: company.name,
                      selected: _companyFilter == company.id,
                      onSelected: () =>
                          setState(() => _companyFilter = company.id),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (companies.isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (total == 0)
            _EmptyState(
              icon: Icons.badge_outlined,
              title: 'No roles yet',
              message: 'Add a role for a company to get started.',
              actionLabel: 'Add role',
              onAction: companies.isLoading ? null : _addRole,
            )
          else if (roles.isEmpty)
            _EmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: 'No matching roles',
              message: 'Try another company filter or clear your search.',
              actionLabel: 'Clear filters',
              onAction: () {
                setState(() {
                  _companyFilter = null;
                  _search.clear();
                });
              },
            )
          else
            ...roles.map((item) {
              final taskCount = _taskCountForRole(companies, item);
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
            }),
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
    required this.hasSearch,
  });

  final int total;
  final int showing;
  final String? companyFilter;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final filtered = companyFilter != null || hasSearch;
    final countLabel =
        filtered ? 'Showing $showing of $total' : '$total roles';

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
                if (companyFilter != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    companyFilter!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                    maxLines: 1,
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.28),
      backgroundColor: colors.inputFill,
      side: BorderSide(
        color: selected ? AppColors.primary : colors.border,
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? colors.textPrimary : colors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
