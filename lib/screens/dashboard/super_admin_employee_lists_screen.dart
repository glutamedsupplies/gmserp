import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../models/company_model.dart';
import '../../models/company_task.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SuperAdminEmployeeListsScreen extends StatefulWidget {
  const SuperAdminEmployeeListsScreen({super.key});

  @override
  State<SuperAdminEmployeeListsScreen> createState() =>
      _SuperAdminEmployeeListsScreenState();
}

class _SuperAdminEmployeeListsScreenState
    extends State<SuperAdminEmployeeListsScreen> {
  final _search = TextEditingController();
  String? _companyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final companies = context.read<CompanyProvider>();
      await companies.loadCompanies();
      if (!mounted) return;
      if (companies.companies.isNotEmpty) {
        await _selectCompany(companies.companies.first.id);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectCompany(String companyId) async {
    setState(() {
      _companyId = companyId;
      _search.clear();
    });
    await context.read<CompanyProvider>().loadCompanyUsers(companyId);
  }

  CompanyModel? _selectedCompany(CompanyProvider companies) {
    final id = _companyId;
    if (id == null) return null;
    for (final company in companies.companies) {
      if (company.id == id) return company;
    }
    return null;
  }

  List<StaffAssignment> _filteredStaff(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    final staff = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    if (query.isEmpty) return staff;
    return staff.where((member) {
      final user = companies.userById(member.userId);
      final level = (user?.role ?? UserRole.user).label.toLowerCase();
      return member.username.toLowerCase().contains(query) ||
          member.email.toLowerCase().contains(query) ||
          member.userId.toLowerCase().contains(query) ||
          member.tasks.any((task) => task.toLowerCase().contains(query)) ||
          member.jobRole.toLowerCase().contains(query) ||
          level.contains(query);
    }).toList();
  }

  Future<void> _addEmployee() async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) {
      SnackBarHelper.showInfo(context, 'Select a company first.');
      return;
    }

    final companies = context.read<CompanyProvider>();
    final available = companies.usersNotInCompany();
    if (available.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        'Every user is already in this company, or there are no users to add.',
      );
      return;
    }

    final selected = await showModalBottomSheet<UserModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AddEmployeeSheet(users: available),
    );
    if (selected == null || !mounted) return;

    final ok = await companies.addCompanyMember(
      companyId: company.id,
      user: selected,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        '${selected.username} was added to ${company.name}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not add the employee.',
      );
    }
  }

  Future<void> _removeEmployee(StaffAssignment member) async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove employee'),
        content: Text(
          'Remove ${member.username} from ${company.name}? Their account stays in the system.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final companies = context.read<CompanyProvider>();
    final ok = await companies.removeCompanyMember(
      companyId: company.id,
      userId: member.userId,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(context, '${member.username} was removed.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not remove the employee.',
      );
    }
  }

  Future<void> _assignRoleAndTasks(StaffAssignment member) async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) return;

    final companies = context.read<CompanyProvider>();
    if (companies.roles.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        'Add roles under Role lists first, then assign them here.',
      );
      return;
    }

    final selected = await showModalBottomSheet<_StaffRoleTaskPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AssignEmployeeSheet(
        member: member,
        roles: companies.roles,
        tasks: companies.tasks,
      ),
    );
    if (selected == null || !mounted) return;

    final ok = await companies.assignStaff(
      companyId: company.id,
      assignment: StaffAssignment(
        userId: member.userId,
        username: member.username,
        email: member.email,
        roleId: selected.roleId,
        jobRole: selected.roleName,
        tasks: selected.tasks,
      ),
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        selected.tasks.isEmpty
            ? '${member.username} has no role or tasks assigned.'
            : '${member.username} was assigned ${selected.roleName} • ${selected.tasks.join(', ')}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not save the assignment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final company = _selectedCompany(companies);
    final members = _filteredStaff(companies);
    final total = companies.staff.length;
    final assigned = companies.staff
        .where((member) => member.jobRole.isNotEmpty || member.tasks.isNotEmpty)
        .length;

    return DashboardScaffold(
      title: 'Employee lists',
      currentRoute: AppRoutes.superAdminEmployees,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(
            'Employee lists',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Select a company, add people, then tap to assign role and tasks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (companies.companies.isEmpty)
            _EmptyState(
              icon: Icons.business_rounded,
              title: 'No companies yet',
              message: 'Create a company first, then add employees here.',
            )
          else ...[
            _SummaryCard(
              companyName: company?.name ?? 'Select company',
              total: total,
              assigned: assigned,
              showing: members.length,
              hasSearch: _search.text.trim().isNotEmpty,
            ),
            const SizedBox(height: 12),
            _CompanySearchDropdown(
              companies: companies.companies,
              selectedId: _companyId,
              logoFor: companies.logoFor,
              onSelected: _selectCompany,
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
                      hintText: 'Search name, email, role, or task',
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
                  onPressed:
                      companies.isLoading || company == null ? null : _addEmployee,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (companies.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (companies.staff.isEmpty)
              _EmptyState(
                icon: Icons.groups_outlined,
                title: 'No employees yet',
                message: 'Add someone to this company to get started.',
                actionLabel: 'Add employee',
                onAction: company == null ? null : _addEmployee,
              )
            else if (members.isEmpty)
              _EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'No matches',
                message: 'Try another search term.',
                actionLabel: 'Clear search',
                onAction: () {
                  _search.clear();
                  setState(() {});
                },
              )
            else
              ...members.map((member) {
                final user = companies.userById(member.userId);
                final level = user?.role ?? UserRole.user;
                return _EmployeeCard(
                  member: member,
                  levelLabel: level.label,
                  onTap: () => _assignRoleAndTasks(member),
                  onRemove: () => _removeEmployee(member),
                );
              }),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.companyName,
    required this.total,
    required this.assigned,
    required this.showing,
    required this.hasSearch,
  });

  final String companyName;
  final int total;
  final int assigned;
  final int showing;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final countLabel =
        hasSearch ? 'Showing $showing of $total' : '$total employees';

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
                  companyName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$countLabel  •  $assigned assigned',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySearchDropdown extends StatelessWidget {
  const _CompanySearchDropdown({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
    required this.onSelected,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;
  final ValueChanged<String> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CompanyPickerSheet(
        companies: companies,
        selectedId: selectedId,
        logoFor: logoFor,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    CompanyModel? selected;
    for (final company in companies) {
      if (company.id == selectedId) {
        selected = company;
        break;
      }
    }

    return Material(
      color: colors.inputFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openPicker(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Company',
            isDense: true,
            filled: true,
            fillColor: colors.inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.border),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colors.textSecondary,
            ),
          ),
          child: Row(
            children: [
              if (selected != null) ...[
                UserAvatar(
                  bytes: logoFor(selected.id),
                  name: selected.name,
                  size: 28,
                ),
                const SizedBox(width: 10),
              ] else
                Icon(
                  Icons.business_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
              if (selected == null) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selected == null
                      ? 'Search and select a company'
                      : '${selected.name}  •  ${selected.companyId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: selected == null
                            ? colors.textHint
                            : colors.textPrimary,
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

class _CompanyPickerSheet extends StatefulWidget {
  const _CompanyPickerSheet({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;

  @override
  State<_CompanyPickerSheet> createState() => _CompanyPickerSheetState();
}

class _CompanyPickerSheetState extends State<_CompanyPickerSheet> {
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
              'Select company',
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
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final company = items[index];
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
                            onTap: () => Navigator.pop(context, company.id),
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

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.member,
    required this.levelLabel,
    required this.onTap,
    required this.onRemove,
  });

  final StaffAssignment member;
  final String levelLabel;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final name =
        member.username.isEmpty ? 'Unnamed employee' : member.username;

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
                  name: name,
                  bytes: null,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _MiniChip(
                            label: levelLabel,
                            fill: colors.chip,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member.email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniChip(
                            label: member.jobRole.isEmpty
                                ? 'No role'
                                : member.jobRole,
                            fill: member.jobRole.isEmpty
                                ? colors.inputFill
                                : AppColors.primary.withValues(alpha: 0.16),
                            bold: member.jobRole.isNotEmpty,
                          ),
                          if (member.tasks.isEmpty)
                            _MiniChip(
                              label: 'No tasks',
                              fill: colors.inputFill,
                            )
                          else
                            ...member.tasks.take(3).map(
                                  (task) => _MiniChip(
                                    label: task,
                                    fill: colors.inputFill,
                                  ),
                                ),
                          if (member.tasks.length > 3)
                            _MiniChip(
                              label: '+${member.tasks.length - 3}',
                              fill: colors.inputFill,
                              bold: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Assign role & tasks',
                  visualDensity: VisualDensity.compact,
                  onPressed: onTap,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.person_remove_outlined,
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
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
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
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _AddEmployeeSheet extends StatelessWidget {
  const _AddEmployeeSheet({required this.users});

  final List<UserModel> users;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
              'Add employee',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Choose an account to add to this company.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: users.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final user = users[index];
                  return Material(
                    color: colors.inputFill,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: UserAvatar(
                        name: user.username,
                        bytes: null,
                        size: 36,
                      ),
                      title: Text(user.username),
                      subtitle: Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _MiniChip(
                        label: user.role.label,
                        fill: colors.chip,
                      ),
                      onTap: () => Navigator.pop(context, user),
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

class _StaffRoleTaskPick {
  const _StaffRoleTaskPick({
    required this.roleId,
    required this.roleName,
    required this.tasks,
  });

  final String roleId;
  final String roleName;
  final List<String> tasks;
}

class _AssignEmployeeSheet extends StatefulWidget {
  const _AssignEmployeeSheet({
    required this.member,
    required this.roles,
    required this.tasks,
  });

  final StaffAssignment member;
  final List<CompanyJobRole> roles;
  final List<CompanyTask> tasks;

  @override
  State<_AssignEmployeeSheet> createState() => _AssignEmployeeSheetState();
}

class _AssignEmployeeSheetState extends State<_AssignEmployeeSheet> {
  late String _roleId;
  late Set<String> _selectedTasks;

  @override
  void initState() {
    super.initState();
    final existingRole =
        widget.roles.any((role) => role.id == widget.member.roleId)
            ? widget.member.roleId
            : widget.roles.first.id;
    _roleId = existingRole;
    final matching = _tasksForRole(_roleId);
    final allowed = matching.map((task) => task.title).toSet();
    _selectedTasks = widget.member.tasks.where(allowed.contains).toSet();
  }

  List<CompanyTask> _tasksForRole(String roleId) {
    return widget.tasks.where((task) => task.roleId == roleId).toList();
  }

  CompanyJobRole? _roleById(String roleId) {
    for (final role in widget.roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  void _toggleTask(String title) {
    setState(() {
      if (_selectedTasks.contains(title)) {
        _selectedTasks.remove(title);
      } else {
        _selectedTasks.add(title);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final name = widget.member.username.isEmpty
        ? widget.member.email
        : widget.member.username;
    final filtered = _tasksForRole(_roleId);
    final role = _roleById(_roleId);

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
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Pick a role, then select tasks.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isDense: true,
              initialValue: widget.roles.any((item) => item.id == _roleId)
                  ? _roleId
                  : widget.roles.first.id,
              decoration: const InputDecoration(
                labelText: 'Role',
                isDense: true,
              ),
              items: [
                for (final item in widget.roles)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _roleId = value;
                  final allowed =
                      _tasksForRole(value).map((task) => task.title).toSet();
                  _selectedTasks =
                      _selectedTasks.where(allowed.contains).toSet();
                });
              },
            ),
            const SizedBox(height: 10),
            if (filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  'No tasks for this role yet. Add them under Task lists.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final task = filtered[index];
                    final selected = _selectedTasks.contains(task.title);
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
                          selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: colors.textPrimary,
                          size: 22,
                        ),
                        title: Text(task.title),
                        subtitle: task.description.isEmpty
                            ? null
                            : Text(
                                task.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => _toggleTask(task.title),
                      ),
                    );
                  },
                ),
              ),
            if (_selectedTasks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${_selectedTasks.length} selected',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Save assignment',
              onPressed: role == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        _StaffRoleTaskPick(
                          roleId: role.id,
                          roleName: role.name,
                          tasks: _selectedTasks.toList()..sort(),
                        ),
                      ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _StaffRoleTaskPick(
                        roleId: '',
                        roleName: '',
                        tasks: [],
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
