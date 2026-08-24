import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';

enum _MemberRoleFilter { all, admin, employee }

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _MemberRoleFilter _roleFilter = _MemberRoleFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final companies = context.read<CompanyProvider>();
      final company = companies.selectedCompany;
      if (company == null) {
        return;
      }
      companies.loadUsers();
      companies.loadStaff(company.id);
    });
  }

  UserRole? _roleFilterValue(_MemberRoleFilter filter) {
    switch (filter) {
      case _MemberRoleFilter.all:
        return null;
      case _MemberRoleFilter.admin:
        return UserRole.admin;
      case _MemberRoleFilter.employee:
        return UserRole.employee;
    }
  }

  List<StaffAssignment> _filteredMembers(CompanyProvider companies) {
    final filterRole = _roleFilterValue(_roleFilter);
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final user = companies.userById(member.userId);
      final role = user?.role;
      if (role != UserRole.admin && role != UserRole.employee) {
        return false;
      }
      if (filterRole == null) return true;
      return role == filterRole;
    }).toList();
  }

  int _countByRole(CompanyProvider companies, UserRole role) {
    return companies.staff
        .where((member) => companies.userById(member.userId)?.role == role)
        .length;
  }

  Future<void> _assign(UserModel member) async {
    final company = context.read<CompanyProvider>().selectedCompany;
    if (company == null) return;

    final roleController = TextEditingController();
    final taskController = TextEditingController();
    final existing = context
        .read<CompanyProvider>()
        .staff
        .where((item) => item.userId == member.id)
        .toList();
    if (existing.isNotEmpty) {
      roleController.text = existing.first.jobRole;
      taskController.text = existing.first.tasks.join(', ');
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Assign ${member.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextField(
                controller: roleController,
                label: 'Role',
                hint: 'e.g. Cashier, Inventory',
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: taskController,
                label: 'Task',
                hint: 'e.g. Handle POS, Count stock',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true || !mounted) {
      roleController.dispose();
      taskController.dispose();
      return;
    }

    final ok = await context.read<CompanyProvider>().assignStaff(
          companyId: company.id,
          assignment: StaffAssignment(
            userId: member.id,
            username: member.username,
            email: member.email,
            roleId: existing.isNotEmpty ? existing.first.roleId : '',
            jobRole: roleController.text.trim(),
            tasks: taskController.text
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
          ),
        );
    roleController.dispose();
    taskController.dispose();
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(context, 'Assignment saved.');
    } else {
      SnackBarHelper.showError(context, 'Could not save assignment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final company = companies.selectedCompany;
    final members = _filteredMembers(companies);
    final total = companies.staff
        .where((member) {
          final role = companies.userById(member.userId)?.role;
          return role == UserRole.admin || role == UserRole.employee;
        })
        .length;
    final adminCount = _countByRole(companies, UserRole.admin);
    final employeeCount = _countByRole(companies, UserRole.employee);
    final colors = AppColors.of(context);

    return DashboardScaffold(
      title: 'Staff',
      currentRoute: AppRoutes.adminDashboard,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            company?.name ?? 'Company',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Assign admins and employees a specific role and task for this company.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$total members ($adminCount admin, $employeeCount employee)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Role',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _RoleFilterChip(
                  label: 'All',
                  selected: _roleFilter == _MemberRoleFilter.all,
                  onSelected: () =>
                      setState(() => _roleFilter = _MemberRoleFilter.all),
                ),
                const SizedBox(width: 8),
                _RoleFilterChip(
                  label: 'Admin',
                  selected: _roleFilter == _MemberRoleFilter.admin,
                  onSelected: () =>
                      setState(() => _roleFilter = _MemberRoleFilter.admin),
                ),
                const SizedBox(width: 8),
                _RoleFilterChip(
                  label: 'Employee',
                  selected: _roleFilter == _MemberRoleFilter.employee,
                  onSelected: () =>
                      setState(() => _roleFilter = _MemberRoleFilter.employee),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (companies.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (total == 0)
            const Text(
              'No admins or employees in this company yet. Ask Super Admin to add members.',
            )
          else if (members.isEmpty)
            TextButton(
              onPressed: () => setState(() => _roleFilter = _MemberRoleFilter.all),
              child: const Text('Clear role filter'),
            )
          else
            ...members.map((member) {
              final user = companies.userById(member.userId);
              final levelLabel = user?.role.label ?? 'Member';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(member.username),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.chip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        levelLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  member.jobRole.isEmpty && member.tasks.isEmpty
                      ? member.email
                      : '${member.jobRole.isEmpty ? 'No role' : member.jobRole} • ${member.tasks.isEmpty ? 'No tasks' : member.tasks.join(', ')}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () {
                  final userModel = user ??
                      UserModel(
                        id: member.userId,
                        username: member.username,
                        email: member.email,
                        phoneNumber: '',
                        role: UserRole.employee,
                      );
                  _assign(userModel);
                },
              );
            }),
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
        color: colors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
