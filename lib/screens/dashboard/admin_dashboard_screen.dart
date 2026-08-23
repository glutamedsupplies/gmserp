import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
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

  Future<void> _assign(UserModel employee) async {
    final company = context.read<CompanyProvider>().selectedCompany;
    if (company == null) return;

    final roleController = TextEditingController();
    final taskController = TextEditingController();
    final existing = context
        .read<CompanyProvider>()
        .staff
        .where((item) => item.userId == employee.id)
        .toList();
    if (existing.isNotEmpty) {
      roleController.text = existing.first.jobRole;
      taskController.text = existing.first.tasks.join(', ');
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Assign ${employee.username}'),
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
            userId: employee.id,
            username: employee.username,
            email: employee.email,
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
    final employees = companies.users
        .where((user) => user.role == UserRole.employee)
        .toList();

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
            'Assign employees a specific role and task for this company.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (employees.isEmpty)
            const Text('No employees found. Ask Super Admin to set a user as Employee.')
          else
            ...employees.map((employee) {
              final assignment = companies.staff
                  .where((item) => item.userId == employee.id)
                  .toList();
              final current = assignment.isEmpty ? null : assignment.first;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(employee.username),
                subtitle: Text(
                  current == null
                      ? employee.email
                      : '${current.jobRole} • ${current.tasks.join(', ')}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _assign(employee),
              );
            }),
        ],
      ),
    );
  }
}
