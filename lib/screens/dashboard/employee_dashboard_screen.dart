import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
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
        Navigator.of(context).pushReplacementNamed(AppRoutes.selectCompany);
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

    return DashboardScaffold(
      title: 'Employee Dashboard',
      currentRoute: AppRoutes.employeeDashboard,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Welcome, ${user?.username ?? 'Employee'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Company: ${company?.name ?? '-'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text(
            'Assigned by Admin',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text('Role: ${assignment?.jobRole.isNotEmpty == true ? assignment!.jobRole : 'Not assigned yet'}'),
          const SizedBox(height: 8),
          Text('Task: ${assignment?.task.isNotEmpty == true ? assignment!.task : 'Not assigned yet'}'),
        ],
      ),
    );
  }
}
