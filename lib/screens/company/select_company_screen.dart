import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/navigation/post_login.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';

class SelectCompanyScreen extends StatefulWidget {
  const SelectCompanyScreen({super.key});

  @override
  State<SelectCompanyScreen> createState() => _SelectCompanyScreenState();
}

class _SelectCompanyScreenState extends State<SelectCompanyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().clearSelection();
      context.read<CompanyProvider>().loadCompanies();
    });
  }

  Future<void> _openCompany(CompanyModel company) async {
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  company.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the company password or access code to open this company.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                PasswordField(
                  controller: codeController,
                  label: 'Password / code',
                  hint: 'Company password or code',
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(context, codeController.text);
                    }
                  },
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Password or code is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Open company',
                  onPressed: () {
                    if (formKey.currentState?.validate() ?? false) {
                      Navigator.pop(context, codeController.text);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (code == null || !mounted) {
      codeController.dispose();
      return;
    }

    final companies = context.read<CompanyProvider>();
    final ok = companies.unlockCompany(
      company: company,
      password: code.trim(),
    );
    codeController.dispose();

    if (!ok) {
      SnackBarHelper.showError(context, 'Incorrect company password or code.');
      return;
    }

    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    SnackBarHelper.showSuccess(context, 'Opened ${company.name}.');
    Navigator.of(context).pushReplacementNamed(
      PostLoginNavigation.dashboardFor(user.role),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final role = context.watch<AuthProvider>().user?.role.label ?? '';

    return DashboardScaffold(
      title: 'Select company',
      currentRoute: AppRoutes.selectCompany,
      child: companies.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Choose a company to log in',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'You are signed in as $role. Select a company, then enter its password or access code to continue to your dashboard.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (companies.companies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text(
                      'No companies yet. Ask a Super Admin to create one.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...companies.companies.map((company) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Material(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openCompany(company),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                const Icon(Icons.apartment_rounded, size: 32),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        company.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap to enter password / code',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.lock_outline),
                              ],
                            ),
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
