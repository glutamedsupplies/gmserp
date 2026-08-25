import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/company_id.dart';
import '../../core/utils/photo_crop_picker.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/editable_photo.dart';
import '../../widgets/password_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

enum SuperAdminCompanySection { create, list }

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({
    super.key,
    this.section,
  });

  final SuperAdminCompanySection? section;

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  var _formKey = GlobalKey<FormState>();
  final _companyId = TextEditingController();
  final _companyName = TextEditingController();
  final _companyPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _staffPassword = TextEditingController();
  final _confirmStaffPassword = TextEditingController();
  final _search = TextEditingController();
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _companyId.text = CompanyId.generate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyProvider>().loadCompanies();
    });
  }

  bool get _canCreate {
    return CompanyId.validate(_companyId.text) == null &&
        _companyName.text.trim().isNotEmpty &&
        _companyPassword.text.trim().length >= 4 &&
        _confirmPassword.text.isNotEmpty &&
        _confirmPassword.text == _companyPassword.text &&
        _staffPassword.text.trim().length >= 4 &&
        _confirmStaffPassword.text.isNotEmpty &&
        _confirmStaffPassword.text == _staffPassword.text;
  }

  List<CompanyModel> _filteredCompanies(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return companies.companies;
    return companies.companies.where((company) {
      return company.name.toLowerCase().contains(query) ||
          company.companyId.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _companyId.dispose();
    _companyName.dispose();
    _companyPassword.dispose();
    _confirmPassword.dispose();
    _staffPassword.dispose();
    _confirmStaffPassword.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _createCompany() async {
    FocusScope.of(context).unfocus();
    if (!_canCreate || !(_formKey.currentState?.validate() ?? false)) {
      SnackBarHelper.showError(
        context,
        'Fill in the company ID, name, company password, and company code first.',
      );
      return;
    }

    final user = context.read<AuthProvider>().user;
    final id = CompanyId.normalize(_companyId.text);
    final name = _companyName.text.trim();
    final ok = await context.read<CompanyProvider>().createCompany(
          companyId: id,
          name: name,
          password: _companyPassword.text,
          staffPassword: _staffPassword.text,
          createdBy: user?.id ?? '',
          logoBytes: _logoBytes,
        );
    if (!mounted) return;
    if (ok) {
      _companyName.clear();
      _companyPassword.clear();
      _confirmPassword.clear();
      _staffPassword.clear();
      _confirmStaffPassword.clear();
      _companyId.text = CompanyId.generate();
      setState(() {
        _formKey = GlobalKey<FormState>();
        _logoBytes = null;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => _CompanyCreatedDialog(companyName: name),
      );
    } else {
      SnackBarHelper.showError(
        context,
        context.read<CompanyProvider>().errorMessage ??
            'Could not create company.',
      );
    }
  }

  Future<void> _editCompany(CompanyModel company) async {
    final savedName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CompactPageStyle.read(context).radius),
        ),
      ),
      builder: (context) => _EditCompanySheet(company: company),
    );
    if (!mounted || savedName == null) return;
    if (savedName.startsWith('__deleted__:')) {
      final name = savedName.substring('__deleted__:'.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SnackBarHelper.showSuccess(
          context,
          name.isEmpty ? 'Company deleted.' : '$name was deleted.',
        );
      });
      return;
    }
    SnackBarHelper.showSuccess(context, '$savedName updated.');
  }

  void _openCompanyUsers(CompanyModel company) {
    Navigator.of(context).pushNamed(
      AppRoutes.superAdminCompanyUsers,
      arguments: company,
    );
  }

  Future<void> _deleteCompany(CompanyModel company) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteCompanyDialog(company: company),
    );
    if (!mounted || confirmed != true) return;
    SnackBarHelper.showSuccess(context, '${company.name} was deleted.');
  }

  Future<void> _pickCreateLogo() async {
    try {
      final cropped = await pickAndCropPhoto(context);
      if (cropped == null || !mounted) return;
      setState(() => _logoBytes = cropped);
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.showError(context, photoPickerErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final colors = AppColors.of(context);

    final isCreate =
        (widget.section ?? SuperAdminCompanySection.create) !=
            SuperAdminCompanySection.list;

    return DashboardScaffold(
      title: isCreate ? 'Create company' : 'Company lists',
      currentRoute: isCreate
          ? AppRoutes.superAdminCreate
          : AppRoutes.superAdminList,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          if (isCreate) ...[
          const CompactPageHeader(
            title: 'Create company',
            subtitle:
                'Company password is for the founder only. Company code is what employees enter to log in.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Form(
            key: _formKey,
            child: Column(
              children: [
                EditablePhoto(
                  bytes: _logoBytes,
                  name: _companyName.text.trim().isEmpty
                      ? 'Company'
                      : _companyName.text.trim(),
                  onTap: _pickCreateLogo,
                  onRemove: _logoBytes == null
                      ? null
                      : () => setState(() => _logoBytes = null),
                ),
                SizedBox(height: CompactPageStyle.of(context).sectionGap),
                CustomTextField(
                  controller: _companyId,
                  label: 'Company ID',
                  hint: '8 digits, e.g. 84729103',
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: CompanyId.inputFormatters,
                  validator: CompanyId.validate,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() => _companyId.text = CompanyId.generate());
                    },
                    child: const Text('Generate ID'),
                  ),
                ),
                CustomTextField(
                  controller: _companyName,
                  label: 'Company name',
                  hint: 'e.g. GMS Branch 1',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Company name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _AccessSection(
                  icon: Icons.lock_rounded,
                  title: 'Company password',
                  badge: 'Founder only',
                  description:
                      'Keep this private. Use it to edit or delete the company. Do not share it with employees.',
                  children: [
                    PasswordField(
                      controller: _companyPassword,
                      label: 'Company password',
                      hint: 'Founder password',
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Company password is required.';
                        }
                        if (value.trim().length < 4) {
                          return 'Use at least 4 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _confirmPassword,
                      label: 'Re-enter company password',
                      hint: 'Type the same company password again',
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Re-enter the company password.';
                        }
                        if (value != _companyPassword.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _AccessSection(
                  icon: Icons.pin_rounded,
                  title: 'Company code',
                  badge: 'For employees',
                  highlighted: true,
                  description:
                      'Share this with employees. They enter it with the company ID to log in.',
                  children: [
                    PasswordField(
                      controller: _staffPassword,
                      label: 'Company code',
                      hint: 'Code employees use to log in',
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Company code is required.';
                        }
                        if (value.trim().length < 4) {
                          return 'Use at least 4 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _confirmStaffPassword,
                      label: 'Re-enter company code',
                      hint: 'Type the same company code again',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Re-enter the company code.';
                        }
                        if (value != _staffPassword.text) {
                          return 'Codes do not match.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Create company',
                  isLoading: companies.isLoading,
                  onPressed: _createCompany,
                ),
              ],
            ),
          ),
          ] else ...[
          const CompactPageHeader(
            title: 'Company lists',
            subtitle:
                'Tap a company to view its roles and tasks. Edit them under Role lists and Task lists. Use Employee lists to add people.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          CompactSearchField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            hintText: 'Search by company name or ID',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (companies.companies.isEmpty)
            const Text('No companies yet.')
          else if (_filteredCompanies(companies).isEmpty)
            const Text('No companies match that search.')
          else
            ..._filteredCompanies(companies).map(
              (company) => Padding(
                padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
                child: Material(
                  color: colors.inputFill,
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(CompactPageStyle.of(context).radius),
                    onTap: () => _openCompanyUsers(company),
                    child: Padding(
                      padding: CompactPageStyle.of(context).cardPadding,
                      child: Row(
                        children: [
                          UserAvatar(
                            key: ValueKey(
                              '${company.id}-${companies.logoRevision}',
                            ),
                            bytes: companies.logoFor(company.id),
                            name: company.name,
                            size: 40,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  company.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'ID: ${company.companyId}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _editCompany(company),
                            icon: Icon(
                              Icons.edit_rounded,
                              color: colors.textPrimary,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteCompany(company),
                            icon: const Icon(
                              Icons.delete_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditCompanySheet extends StatefulWidget {
  const _EditCompanySheet({required this.company});

  final CompanyModel company;

  @override
  State<_EditCompanySheet> createState() => _EditCompanySheetState();
}

class _EditCompanySheetState extends State<_EditCompanySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _staffPassword = TextEditingController();
  final _confirmStaffPassword = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController(text: widget.company.companyId);
    _name = TextEditingController(text: widget.company.name);
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _staffPassword.dispose();
    _confirmStaffPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final nextName = _name.text.trim();
    final nextPassword = _password.text;
    final nextStaffPassword = _staffPassword.text;
    final ok = await context.read<CompanyProvider>().updateCompany(
          id: widget.company.id,
          name: nextName,
          newPassword: nextPassword.isEmpty ? null : nextPassword,
          newStaffPassword:
              nextStaffPassword.isEmpty ? null : nextStaffPassword,
        );
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop(nextName);
      return;
    }

    SnackBarHelper.showError(
      context,
      context.read<CompanyProvider>().errorMessage ??
          'Could not update the company.',
    );
  }

  Future<void> _pickEditLogo() async {
    try {
      final cropped = await pickAndCropPhoto(context);
      if (cropped == null || !mounted) return;
      final ok = await context.read<CompanyProvider>().saveCompanyLogo(
            widget.company.id,
            cropped,
          );
      if (!mounted) return;
      if (!ok) {
        SnackBarHelper.showError(
          context,
          context.read<CompanyProvider>().errorMessage ??
              'Could not save the company photo.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.showError(context, photoPickerErrorMessage(error));
    }
  }

  Future<void> _removeEditLogo() async {
    final ok = await context.read<CompanyProvider>().removeCompanyLogo(
          widget.company.id,
        );
    if (!mounted) return;
    if (!ok) {
      SnackBarHelper.showError(
        context,
        context.read<CompanyProvider>().errorMessage ??
            'Could not remove the company photo.',
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _DeleteCompanyDialog(
        company: widget.company,
      ),
    );
    if (!mounted || confirmed != true) return;
    Navigator.of(context).pop('__deleted__:${widget.company.name}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              SizedBox(height: CompactPageStyle.of(context).sectionGap),
              Text(
                'Edit company',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              SizedBox(height: CompactPageStyle.of(context).sectionGap),
              Consumer<CompanyProvider>(
                builder: (context, companies, _) {
                  return EditablePhoto(
                    key: ValueKey(
                      '${widget.company.id}-${companies.logoRevision}',
                    ),
                    bytes: companies.logoFor(widget.company.id),
                    name: _name.text.trim().isEmpty
                        ? widget.company.name
                        : _name.text.trim(),
                    onTap: _saving ? () {} : _pickEditLogo,
                    onRemove: companies.logoFor(widget.company.id) == null
                        ? null
                        : (_saving ? null : _removeEditLogo),
                  );
                },
              ),
              SizedBox(height: CompactPageStyle.of(context).sectionGap),
              CustomTextField(
                controller: _id,
                label: 'Company ID',
                enabled: false,
              ),
              const SizedBox(height: 4),
              Text(
                'Company ID cannot be changed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _name,
                label: 'Company name',
                hint: 'e.g. GMS Branch 1',
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Company name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _AccessSection(
                icon: Icons.lock_rounded,
                title: 'Company password',
                badge: 'Founder only',
                description:
                    'Keep this private. Leave blank to keep the current founder password.',
                children: [
                  PasswordField(
                    controller: _password,
                    label: 'New company password',
                    hint: 'Leave blank to keep the current password',
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null;
                      if (value.trim().length < 4) {
                        return 'Use at least 4 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirmPassword,
                    label: 'Re-enter company password',
                    hint: 'Required only if you change the password',
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (_password.text.isEmpty) return null;
                      if (value == null || value.isEmpty) {
                        return 'Re-enter the new company password.';
                      }
                      if (value != _password.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AccessSection(
                icon: Icons.pin_rounded,
                title: 'Company code',
                badge: 'For employees',
                highlighted: true,
                description:
                    'Share this with employees. Leave blank to keep the current company code.',
                children: [
                  PasswordField(
                    controller: _staffPassword,
                    label: 'New company code',
                    hint: 'Leave blank to keep the current code',
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) return null;
                      if (value.trim().length < 4) {
                        return 'Use at least 4 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirmStaffPassword,
                    label: 'Re-enter company code',
                    hint: 'Required only if you change the code',
                    validator: (value) {
                      if (_staffPassword.text.isEmpty) return null;
                      if (value == null || value.isEmpty) {
                        return 'Re-enter the new company code.';
                      }
                      if (value != _staffPassword.text) {
                        return 'Codes do not match.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Save changes',
                isLoading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _confirmDelete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.error.withValues(
                      alpha: 0.45,
                    ),
                    disabledForegroundColor: Colors.white70,
                  ),
                  child: const Text(
                    'Delete company',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteCompanyDialog extends StatefulWidget {
  const _DeleteCompanyDialog({required this.company});

  final CompanyModel company;

  @override
  State<_DeleteCompanyDialog> createState() => _DeleteCompanyDialogState();
}

class _DeleteCompanyDialogState extends State<_DeleteCompanyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    final ok = await context.read<CompanyProvider>().deleteCompany(
          company: widget.company,
          password: _password.text,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _deleting = false;
      _error = context.read<CompanyProvider>().errorMessage ??
          'Incorrect company password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete company'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the company password for ${widget.company.name} to delete it. This is the founder password, not the company code.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'Company password',
              hint: 'Founder company password, not the company code',
              autofocus: true,
              enabled: !_deleting,
              onFieldSubmitted: (_) {
                if (!_deleting) _delete();
              },
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Company password is required.';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _deleting ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _deleting ? null : _delete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _deleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Delete'),
              ),
            ),
          ],
        ),
        ),
      ],
    );
  }
}

class _CompanyCreatedDialog extends StatelessWidget {
  const _CompanyCreatedDialog({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final width = MediaQuery.sizeOf(context).width;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          minWidth: width < 600 ? width - 48 : 440,
        ),
        child: Material(
          color: colors.card,
          elevation: 0,
          borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 36,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Company created',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: CompactPageStyle.of(context).summaryPadding,
                  decoration: BoxDecoration(
                    color: colors.inputFill,
                    borderRadius:
                        BorderRadius.circular(CompactPageStyle.of(context).radius),
                  ),
                  child: Text(
                    companyName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                  ),
                ),
                SizedBox(height: CompactPageStyle.of(context).sectionGap),
                Text(
                  'Share the company ID and company code with employees. Keep the company password to yourself.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Done',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessSection extends StatelessWidget {
  const _AccessSection({
    required this.icon,
    required this.title,
    required this.badge,
    required this.description,
    required this.children,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String badge;
  final String description;
  final List<Widget> children;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = highlighted
        ? AppColors.primary.withValues(alpha: dark ? 0.16 : 0.18)
        : colors.card;
    final borderColor = highlighted
        ? AppColors.primary.withValues(alpha: dark ? 0.45 : 0.55)
        : colors.border;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                ),
                child: Icon(icon, color: colors.textPrimary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.chip,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          ...children,
        ],
      ),
    );
  }
}
