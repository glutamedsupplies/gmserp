import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final companies = context.read<CompanyProvider>();
      final company = companies.selectedCompany;
      final user = auth.user;
      if (company == null || user == null) {
        return;
      }
      companies.loadMyAssignment(companyId: company.id, userId: user.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final company = companies.selectedCompany;
    final assignment = companies.myAssignment;

    final density = CompactPageStyle.of(context);

    return DashboardScaffold(
      title: 'Employee Dashboard',
      currentRoute: AppRoutes.employeeDashboard,
      child: ListView(
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Welcome, ${user?.username ?? 'Employee'}',
            subtitle: 'Company: ${company?.name ?? '-'}',
          ),
          SizedBox(height: density.sectionGap + 8),
          Text(
            'Assigned by Admin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          SizedBox(height: density.cardGap),
          Text('Role: ${assignment?.jobRole.isNotEmpty == true ? assignment!.jobRole : 'Not assigned yet'}'),
          SizedBox(height: density.titleSubtitleGap),
          Text(
            assignment?.tasks.isNotEmpty == true
                ? 'Tasks: ${assignment!.tasks.join(', ')}'
                : 'Tasks: Not assigned yet',
          ),
        ],
      ),
    );
  }
}
