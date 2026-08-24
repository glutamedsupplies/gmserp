import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../services/leave_request_repository.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';

class EmployeeRequestLeaveScreen extends StatefulWidget {
  const EmployeeRequestLeaveScreen({super.key});

  @override
  State<EmployeeRequestLeaveScreen> createState() =>
      _EmployeeRequestLeaveScreenState();
}

class _EmployeeRequestLeaveScreenState
    extends State<EmployeeRequestLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _repository = LeaveRequestRepository();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate == null || _endDate == null) {
      SnackBarHelper.showInfo(context, 'Select start and end dates.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      SnackBarHelper.showInfo(context, 'End date cannot be before start date.');
      return;
    }

    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null) {
      SnackBarHelper.showError(context, 'Sign in to request leave.');
      return;
    }
    if (company == null) {
      SnackBarHelper.showError(
        context,
        'Select a company before requesting leave.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _repository.submit(
        user: user,
        company: company,
        reason: _reason.text,
        startDate: _startDate!,
        endDate: _endDate!,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        'Leave request submitted. Those days show as On Leave on your time card.',
      );
      _reason.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });
    } catch (_) {
      if (!mounted) return;
      SnackBarHelper.showError(context, 'Could not submit leave request.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = context.watch<CompanyProvider>().selectedCompany;

    return DashboardScaffold(
      title: 'Request leave',
      currentRoute: AppRoutes.employeeRequestLeave,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Text(
                'Request leave',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                company == null
                    ? 'Select a company first, then submit a leave request.'
                    : 'Leave for ${company.name} appears as On Leave on your time card.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DateField(
                      label: 'Start date',
                      value: _formatDate(_startDate),
                      onTap: () => _pickDate(isStart: true),
                    ),
                    const SizedBox(height: 14),
                    _DateField(
                      label: 'End date',
                      value: _formatDate(_endDate),
                      onTap: () => _pickDate(isStart: false),
                    ),
                    const SizedBox(height: 14),
                    CustomTextField(
                      controller: _reason,
                      label: 'Reason',
                      hint: 'Brief reason for leave',
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Reason is required.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Submit request',
                      isLoading: _submitting,
                      onPressed:
                          _submitting || company == null ? null : _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(value),
      ),
    );
  }
}
