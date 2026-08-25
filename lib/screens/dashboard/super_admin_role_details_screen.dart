import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';

class SuperAdminRoleDetailsScreen extends StatefulWidget {
  const SuperAdminRoleDetailsScreen({
    super.key,
    required this.listing,
  });

  final CompanyRoleListing listing;

  @override
  State<SuperAdminRoleDetailsScreen> createState() =>
      _SuperAdminRoleDetailsScreenState();
}

class _SuperAdminRoleDetailsScreenState
    extends State<SuperAdminRoleDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late CompanyJobRole _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.listing.role;
    _name = TextEditingController(text: _role.name);
    _description = TextEditingController(text: _role.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  int _taskCount(CompanyProvider companies) {
    return companies.allTasks
        .where(
          (item) =>
              item.company.id == widget.listing.company.id &&
              item.task.roleId == _role.id,
        )
        .length;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final companies = context.read<CompanyProvider>();
    final ok = await companies.updateCompanyRole(
      companyId: widget.listing.company.id,
      role: _role,
      name: _name.text,
      description: _description.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      CompanyJobRole? updated;
      for (final item in companies.allRoles) {
        if (item.role.id == _role.id &&
            item.company.id == widget.listing.company.id) {
          updated = item.role;
          break;
        }
      }
      setState(() {
        _role = updated ??
            _role.copyWith(
              name: _name.text.trim(),
              description: _description.text.trim(),
            );
      });
      SnackBarHelper.showSuccess(context, 'Role updated.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not update the role.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final colors = AppColors.of(context);
    final company = widget.listing.company;
    final taskCount = _taskCount(companies);

    return DashboardScaffold(
      title: _role.name.isEmpty ? 'Role details' : _role.name,
      currentRoute: AppRoutes.superAdminRoleDetails,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          CompactPageHeader(
            title: _role.name.isEmpty ? 'Role details' : _role.name,
            subtitle: '${company.name}  •  ID: ${company.companyId}',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Container(
            padding: CompactPageStyle.of(context).summaryPadding,
            decoration: BoxDecoration(
              color: colors.header,
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    borderRadius:
                        BorderRadius.circular(CompactPageStyle.of(context).radius),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: AppColors.primaryDark,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$taskCount ${taskCount == 1 ? 'task' : 'tasks'} linked to this role',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Text(
            'Edit role',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            'Change the role name or details, then save.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Form(
            key: _formKey,
            child: Column(
              children: [
                CustomTextField(
                  controller: _name,
                  label: 'Role name',
                  hint: 'e.g. Cashier',
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Role name is required.';
                    }
                    return null;
                  },
                ),
                SizedBox(height: CompactPageStyle.of(context).sectionGap),
                CustomTextField(
                  controller: _description,
                  label: 'Description',
                  hint: 'Details for this role',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Save changes',
                  loadingLabel: 'Saving...',
                  isLoading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
