import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _companyName = TextEditingController();
  final _companyPassword = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanies();
    });
  }

  @override
  void dispose() {
    _companyName.dispose();
    _companyPassword.dispose();
    super.dispose();
  }

  Future<void> _createCompany() async {
    if (_companyName.text.trim().isEmpty || _companyPassword.text.isEmpty) {
      SnackBarHelper.showError(context, 'Company name and password are required.');
      return;
    }
    final user = context.read<AuthProvider>().user;
    final ok = await context.read<CompanyProvider>().createCompany(
          name: _companyName.text.trim(),
          password: _companyPassword.text,
          createdBy: user?.id ?? '',
        );
    if (!mounted) return;
    if (ok) {
      _companyName.clear();
      _companyPassword.clear();
      SnackBarHelper.showSuccess(context, 'Company created.');
    } else {
      SnackBarHelper.showError(
        context,
        context.read<CompanyProvider>().errorMessage ?? 'Could not create company.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();

    return DashboardScaffold(
      title: 'Companies',
      currentRoute: AppRoutes.superAdmin,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Create companies',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Admins and employees pick a company after login, then enter this password or access code.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _companyName,
            label: 'Company name',
            hint: 'e.g. GMS Branch 1',
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: _companyPassword,
            label: 'Password / access code',
            hint: 'Code staff will enter to open this company',
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Create company',
            isLoading: companies.isLoading,
            onPressed: _createCompany,
          ),
          const SizedBox(height: 32),
          Text('Companies', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (companies.companies.isEmpty)
            const Text('No companies yet.')
          else
            ...companies.companies.map(
              (company) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.apartment_rounded),
                title: Text(company.name),
                subtitle: const Text('Password protected'),
              ),
            ),
        ],
      ),
    );
  }
}
