import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/dashboard_scaffold.dart';

class SuperAdminUsersScreen extends StatefulWidget {
  const SuperAdminUsersScreen({super.key});

  @override
  State<SuperAdminUsersScreen> createState() => _SuperAdminUsersScreenState();
}

class _SuperAdminUsersScreenState extends State<SuperAdminUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadUsers();
    });
  }

  Future<void> _changeRole(String userId, String email, UserRole current) async {
    if (RolePolicy.isSuperAdminEmail(email)) return;

    final selected = await showDialog<UserRole>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Set user level'),
          children: [
            for (final role in [UserRole.user, UserRole.employee, UserRole.admin])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, role),
                child: Text(
                  role.label + (role == current ? ' (current)' : ''),
                ),
              ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    final ok = await context.read<CompanyProvider>().updateUserRole(
          userId: userId,
          role: selected,
        );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(context, 'User level updated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();

    return DashboardScaffold(
      title: 'User levels',
      currentRoute: AppRoutes.superAdminUsers,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'User levels',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Set each account as User, Employee, or Admin. Super Admin is reserved.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (companies.users.isEmpty)
            const Text('No users found.')
          else
            ...companies.users.map((user) {
              final locked = RolePolicy.isSuperAdminEmail(user.email);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(user.username),
                subtitle: Text('${user.email} • ${user.role.label}'),
                trailing: locked
                    ? const Icon(Icons.verified, color: AppColors.primary)
                    : const Icon(Icons.manage_accounts_outlined),
                onTap: locked
                    ? null
                    : () => _changeRole(user.id, user.email, user.role),
              );
            }),
        ],
      ),
    );
  }
}
