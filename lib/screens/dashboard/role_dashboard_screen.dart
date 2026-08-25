import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({super.key});

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();
    if (user == null) return;

    switch (user.role) {
      case UserRole.employee:
        final company = companies.selectedCompany;
        if (company == null) {
          return;
        }
        await companies.loadMyAssignment(
          companyId: company.id,
          userId: user.id,
        );
        break;
      case UserRole.admin:
        final company = companies.selectedCompany;
        if (company == null) {
          return;
        }
        await companies.loadUsers();
        await companies.loadStaff(company.id);
        break;
      case UserRole.superAdmin:
        await companies.loadCompanies();
        await companies.loadUsers();
        break;
      case UserRole.user:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final role = user?.role;

    final density = CompactPageStyle.of(context);

    return DashboardScaffold(
      title: 'Dashboard',
      currentRoute: AppRoutes.dashboard,
      child: ListView(
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Welcome, ${user?.username ?? 'Guest'}',
            subtitle: _subtitle(role, companies.selectedCompany?.name),
          ),
          SizedBox(height: density.sectionGap + 8),
          if (role == UserRole.user) ...[
            _Info(label: 'Email', value: user?.email ?? ''),
            _Info(label: 'Phone', value: user?.phoneNumber ?? ''),
            _Info(label: 'Level', value: user?.role.label ?? 'User'),
          ] else if (role == UserRole.employee) ...[
            _StatCard(
              icon: Icons.badge_outlined,
              label: 'Assigned role',
              value: companies.myAssignment?.jobRole.isNotEmpty == true
                  ? companies.myAssignment!.jobRole
                  : 'Not assigned yet',
            ),
            const SizedBox(height: 12),
            _StatCard(
              icon: Icons.task_alt_rounded,
              label: 'Assigned tasks',
              value: companies.myAssignment?.tasks.isNotEmpty == true
                  ? companies.myAssignment!.tasks.join(', ')
                  : 'Not assigned yet',
            ),
          ] else if (role == UserRole.admin) ...[
            _StatCard(
              icon: Icons.groups_rounded,
              label: 'Employees',
              value: '${companies.users.where((item) => item.role == UserRole.employee).length}',
            ),
            const SizedBox(height: 12),
            _StatCard(
              icon: Icons.assignment_ind_rounded,
              label: 'Staff assignments',
              value: '${companies.staff.length}',
            ),
            const SizedBox(height: 20),
            Text(
              'Use Staff in the sidebar to assign roles and tasks.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ] else if (role == UserRole.superAdmin) ...[
            _StatCard(
              icon: Icons.business_rounded,
              label: 'Companies',
              value: '${companies.companies.length}',
            ),
            const SizedBox(height: 12),
            _StatCard(
              icon: Icons.people_alt_rounded,
              label: 'Users',
              value: '${companies.users.length}',
            ),
            const SizedBox(height: 20),
            Text(
              'Use Companies and User levels in the sidebar to manage the system.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(UserRole? role, String? companyName) {
    switch (role) {
      case UserRole.user:
        return 'You are signed in as a User. This dashboard is for standard account access.';
      case UserRole.employee:
        return 'You are signed in as an Employee${companyName == null ? '' : ' at $companyName'}.';
      case UserRole.admin:
        return 'You are signed in as an Admin${companyName == null ? '' : ' for $companyName'}.';
      case UserRole.superAdmin:
        return 'You are signed in as Super Admin. Overview of companies and users.';
      case null:
        return '';
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    return Container(
      padding: density.cardPadding.add(const EdgeInsets.all(4)),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(density.settingsCardRadius),
      ),
      child: Row(
        children: [
          Container(
            width: density.settingsIconSize,
            height: density.settingsIconSize,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(density.radius),
            ),
            child: Icon(icon, color: colors.textPrimary),
          ),
          SizedBox(width: density.compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: density.compact ? 12 : 14,
                  ),
                ),
                SizedBox(height: density.titleSubtitleGap),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: density.compact ? 14 : 16,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
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

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text('$label: $value'),
    );
  }
}
