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

    return companies.allTasks.where((item) {
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
    final colors = AppColors.of(context);
    final roleNames = _roleNames(companies);
    final tasks = _filtered(companies);
    final total = companies.allTasks.length;

    return DashboardScaffold(
      title: 'Task lists',
      currentRoute: AppRoutes.superAdminTasks,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Task lists',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Browse company tasks, filter by role, or add a new one.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _SummaryCard(
            total: total,
            showing: tasks.length,
            roleFilter: _roleFilter,
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
                    hintText: 'Search task, company, or ID',
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
                onPressed: companies.isLoading ? null : _addTask,
                icon: const Icon(Icons.add_task_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Role',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (roleNames.isEmpty)
            Text(
              'Roles appear here once tasks are linked to a role.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _RoleFilterChip(
                    label: 'All',
                    selected: _roleFilter == null,
                    onSelected: () => setState(() => _roleFilter = null),
                  ),
                  for (final name in roleNames) ...[
                    const SizedBox(width: 8),
                    _RoleFilterChip(
                      label: name,
                      selected:
                          _roleFilter?.toLowerCase() == name.toLowerCase(),
                      onSelected: () => setState(() => _roleFilter = name),
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
              icon: Icons.task_alt_rounded,
              title: 'No tasks yet',
              message: 'Add a task for a company to get started.',
              actionLabel: 'Add task',
              onAction: companies.isLoading ? null : _addTask,
            )
          else if (tasks.isEmpty)
            _EmptyState(
              icon: Icons.filter_alt_off_rounded,
              title: 'No matching tasks',
              message: 'Try another role filter or clear your search.',
              actionLabel: 'Clear filters',
              onAction: () {
                setState(() {
                  _roleFilter = null;
                  _search.clear();
                });
              },
            )
          else
            ...tasks.map((item) => _TaskCard(
                  item: item,
                  logoBytes: companies.logoFor(item.company.id),
                  onTap: () => _openTask(item),
                  onDelete: () => _deleteTask(item),
                )),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.showing,
    required this.roleFilter,
    required this.hasSearch,
  });

  final int total;
  final int showing;
  final String? roleFilter;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final filtered = roleFilter != null || hasSearch;
    final countLabel =
        filtered ? 'Showing $showing of $total' : '$total tasks';

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
                if (roleFilter != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    roleFilter!,
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

class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
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
