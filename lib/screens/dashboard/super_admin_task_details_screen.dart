import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_task.dart';
import '../../providers/company_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';

class SuperAdminTaskDetailsScreen extends StatefulWidget {
  const SuperAdminTaskDetailsScreen({
    super.key,
    required this.listing,
  });

  final CompanyTaskListing listing;

  @override
  State<SuperAdminTaskDetailsScreen> createState() =>
      _SuperAdminTaskDetailsScreenState();
}

class _SuperAdminTaskDetailsScreenState
    extends State<SuperAdminTaskDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late CompanyTask _task;
  late String _roleId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _task = widget.listing.task;
    _roleId = _task.roleId;
    _title = TextEditingController(text: _task.title);
    _description = TextEditingController(text: _task.description);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanyRoles(widget.listing.company.id);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final companies = context.read<CompanyProvider>();
    if (companies.roles.isNotEmpty && _roleId.isEmpty) {
      SnackBarHelper.showError(context, 'Select a role for this task.');
      return;
    }
    final role = companies.roleById(_roleId);

    setState(() => _saving = true);
    final ok = await companies.updateCompanyTask(
      companyId: widget.listing.company.id,
      task: _task,
      title: _title.text,
      description: _description.text,
      roleId: _roleId,
      roleName: role?.name ?? _task.roleName,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      CompanyTask? updated;
      for (final item in companies.allTasks) {
        if (item.task.id == _task.id &&
            item.company.id == widget.listing.company.id) {
          updated = item.task;
          break;
        }
      }
      setState(() {
        _task = updated ??
            _task.copyWith(
              title: _title.text.trim(),
              description: _description.text.trim(),
              roleId: _roleId,
              roleName: role?.name ?? _task.roleName,
              updatedAt: DateTime.now(),
            );
      });
      SnackBarHelper.showSuccess(context, 'Task updated.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not update the task.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final colors = AppColors.of(context);
    final company = widget.listing.company;
    final roleIds = {for (final role in companies.roles) role.id};

    return DashboardScaffold(
      title: _task.title.isEmpty ? 'Task details' : _task.title,
      currentRoute: AppRoutes.superAdminTaskDetails,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          CompactPageHeader(
            title: _task.title.isEmpty ? 'Task details' : _task.title,
            subtitle: '${company.name}  •  ID: ${company.companyId}',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Row(
            children: [
              Expanded(
                child: _DateCard(
                  label: 'Created',
                  value: _formatTaskDate(_task.createdAt),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateCard(
                  label: 'Last updated',
                  value: _formatTaskDate(_task.updatedAt ?? _task.createdAt),
                ),
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Text(
            'Edit task',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            'Change the role, name, or details, then save.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Form(
            key: _formKey,
            child: Column(
              children: [
                if (companies.roles.isNotEmpty || _roleId.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    isDense: true,
                    initialValue: _roleId.isEmpty ? null : _roleId,
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(CompactPageStyle.of(context).radius),
                      ),
                    ),
                    items: [
                      if (companies.roles.isNotEmpty)
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Select role'),
                        ),
                      if (_roleId.isNotEmpty && !roleIds.contains(_roleId))
                        DropdownMenuItem<String?>(
                          value: _roleId,
                          child: Text(
                            _task.roleName.isEmpty
                                ? 'Current role'
                                : _task.roleName,
                          ),
                        ),
                      for (final role in companies.roles)
                        DropdownMenuItem<String?>(
                          value: role.id,
                          child: Text(role.name),
                        ),
                    ],
                    validator: (value) {
                      if ((value == null || value.isEmpty) &&
                          companies.roles.isNotEmpty) {
                        return 'Role is required.';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _roleId = value);
                    },
                  ),
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                ],
                CustomTextField(
                  controller: _title,
                  label: 'Task name',
                  hint: 'e.g. Packing',
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Task name is required.';
                    }
                    return null;
                  },
                ),
                SizedBox(height: CompactPageStyle.of(context).sectionGap),
                CustomTextField(
                  controller: _description,
                  label: 'Description',
                  hint: 'Details for this task',
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
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

String _formatTaskDate(DateTime? date) {
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

class _DateCard extends StatelessWidget {
  const _DateCard({
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
