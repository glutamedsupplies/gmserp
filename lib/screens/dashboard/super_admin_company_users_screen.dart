import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../models/company_model.dart';
import '../../models/time_entry.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
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
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          CompactPageHeader(
            title: company.name,
            subtitle: 'COMPANY ID: ${company.companyId}',
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            'Roles and tasks are view only here. Edit them under Companies → Role lists and Task lists. Assign people under Employee lists.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Row(
            children: [
              Expanded(
                child: _CompanyDateCard(
                  label: 'Created',
                  value: _formatCompanyDate(company.createdAt),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompanyDateCard(
                  label: 'Last updated',
                  value: _formatCompanyDate(company.lastUpdatedAt),
                ),
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
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
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Text(
            'Roles',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            'Job roles set up for this company.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (companies.isLoading && companies.roles.isEmpty)
            const AppLoadingView(
              title: 'Loading roles',
              message: 'Fetching company roles…',
            )
          else if (companies.roles.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
              child: Text('No roles yet. Add them from Role lists.'),
            )
          else
            ...companies.roles.map((role) {
              final taskCount = companies.tasks
                  .where((task) => task.roleId == role.id)
                  .length;
              return Padding(
                padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
                child: Material(
                  color: colors.inputFill,
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  child: ListTile(
                    dense: true,
                    contentPadding: CompactPageStyle.of(context).cardPadding,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(CompactPageStyle.of(context).radius),
                    ),
                    leading: Icon(
                      Icons.badge_outlined,
                      color: colors.textPrimary,
                      size: 20,
                    ),
                    title: Text(
                      role.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      [
                        if (role.description.isNotEmpty) role.description,
                        '$taskCount ${taskCount == 1 ? 'task' : 'tasks'}',
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
              );
            }),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Text(
            'Tasks',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            'Tasks linked to roles for this company.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (companies.tasks.isEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
              child: Text('No tasks yet. Add them from Task lists.'),
            )
          else
            ...companies.tasks.map((task) {
              final subtitle = [
                if (task.roleName.isNotEmpty) task.roleName,
                if (task.description.isNotEmpty) task.description,
              ].join(' • ');
              return Padding(
                padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
                child: Material(
                  color: colors.inputFill,
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  child: ListTile(
                    dense: true,
                    contentPadding: CompactPageStyle.of(context).cardPadding,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(CompactPageStyle.of(context).radius),
                    ),
                    leading: Icon(
                      Icons.task_alt_rounded,
                      color: colors.textPrimary,
                      size: 20,
                    ),
                    title: Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: subtitle.isEmpty
                        ? null
                        : Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
  return '${months[local.month - 1]} ${local.day}, ${local.year}  '
      '${formatHourMinute12h(local.hour, local.minute)}';
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
      padding: CompactPageStyle.of(context).summaryPadding,
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
