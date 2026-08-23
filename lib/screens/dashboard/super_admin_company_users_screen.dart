import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/company_model.dart';
import '../../providers/company_provider.dart';
import '../../widgets/dashboard_scaffold.dart';

class SuperAdminCompanyUsersScreen extends StatefulWidget {
  const SuperAdminCompanyUsersScreen({
    super.key,
    required this.company,
  });

  final CompanyModel company;

  @override
  State<SuperAdminCompanyUsersScreen> createState() =>
      _SuperAdminCompanyUsersScreenState();
}

class _SuperAdminCompanyUsersScreenState
    extends State<SuperAdminCompanyUsersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanyUsers(widget.company.id);
    });
  }

  CompanyModel _resolvedCompany(CompanyProvider companies) {
    for (final item in companies.companies) {
      if (item.id == widget.company.id) return item;
    }
    return widget.company;
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final colors = AppColors.of(context);
    final company = _resolvedCompany(companies);

    return DashboardScaffold(
      title: company.name,
      currentRoute: AppRoutes.superAdminCompanyUsers,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            company.name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'COMPANY ID: ${company.companyId}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Roles and tasks are view only here. Edit them under Companies → Role lists and Task lists. Assign people under Employee lists.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CompanyDateCard(
                  label: 'Created',
                  value: _formatCompanyDate(company.createdAt),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompanyDateCard(
                  label: 'Last updated',
                  value: _formatCompanyDate(company.lastUpdatedAt),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.superAdminRoles);
                },
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: const Text('Role lists'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.superAdminTasks);
                },
                icon: const Icon(Icons.task_alt_rounded, size: 18),
                label: const Text('Task lists'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .pushNamed(AppRoutes.superAdminEmployees);
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Employee lists'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Roles',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Job roles set up for this company.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (companies.isLoading && companies.roles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (companies.roles.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No roles yet. Add them from Role lists.'),
            )
          else
            ...companies.roles.map((role) {
              final taskCount = companies.tasks
                  .where((task) => task.roleId == role.id)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: Icon(
                      Icons.badge_outlined,
                      color: colors.textPrimary,
                    ),
                    title: Text(role.name),
                    subtitle: Text(
                      [
                        if (role.description.isNotEmpty) role.description,
                        '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                      ].join(' • '),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Text(
            'Tasks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tasks linked to roles for this company.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (companies.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No tasks yet. Add them from Task lists.'),
            )
          else
            ...companies.tasks.map((task) {
              final subtitle = [
                if (task.roleName.isNotEmpty) task.roleName,
                if (task.description.isNotEmpty) task.description,
              ].join(' • ');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: Icon(
                      Icons.task_alt_rounded,
                      color: colors.textPrimary,
                    ),
                    title: Text(task.title),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

String _formatCompanyDate(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${months[local.month - 1]} ${local.day}, ${local.year}  $hour:$minute $period';
}

class _CompanyDateCard extends StatelessWidget {
  const _CompanyDateCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
