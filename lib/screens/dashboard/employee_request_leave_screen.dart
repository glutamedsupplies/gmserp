import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/leave_request.dart';
import '../../models/time_card_salary.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../services/leave_request_repository.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/compact_page.dart';
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
  var _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _repository = LeaveRequestRepository();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _submitting = false;
  bool _loadingTaken = false;
  String? _takenCompanyKey;
  List<LeaveRequest> _activeLeaves = [];
  Set<String> _takenDates = {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _ensureTakenDatesLoaded() async {
    final user = context.read<AuthProvider>().user;
    final company = context.read<CompanyProvider>().selectedCompany;
    if (user == null || company == null) {
      if (_activeLeaves.isNotEmpty || _takenDates.isNotEmpty) {
        setState(() {
          _activeLeaves = [];
          _takenDates = {};
          _takenCompanyKey = null;
        });
      }
      return;
    }

    final key = '${user.id}|${company.id}|${company.firestoreId}';
    if (_takenCompanyKey == key || _loadingTaken) return;

    setState(() => _loadingTaken = true);
    try {
      final leaves = await _repository.listForUserCompany(
        userId: user.id,
        companyId: company.id,
      );
      // Also match by firestore doc id if companyId stored differently.
      final byDoc = company.firestoreId.trim().isEmpty
          ? const <LeaveRequest>[]
          : await _repository.listForUserCompany(
              userId: user.id,
              companyId: company.firestoreId,
            );
      final merged = <String, LeaveRequest>{
        for (final leave in [...leaves, ...byDoc]) leave.id: leave,
      };
      final active =
          merged.values.where((leave) => leave.isActiveLeave).toList()
            ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final taken = <String>{};
      for (final leave in active) {
        taken.addAll(_datesInLeave(leave));
      }
      if (!mounted) return;
      setState(() {
        _activeLeaves = active;
        _takenDates = taken;
        _takenCompanyKey = key;
        _loadingTaken = false;
        // Clear picks that are no longer valid.
        if (_startDate != null && _isTakenDay(_startDate!)) {
          _startDate = null;
        }
        if (_endDate != null && _isTakenDay(_endDate!)) {
          _endDate = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTaken = false);
    }
  }

  Iterable<String> _datesInLeave(LeaveRequest leave) sync* {
    final start = parseWorkDateString(leave.startDate);
    if (start == null) return;
    final end = parseWorkDateString(leave.endDate) ?? start;
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      yield formatWorkDate(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
  }

  bool _isTakenDay(DateTime day) {
    return _takenDates.contains(formatWorkDate(day));
  }

  bool _rangeContainsTaken(DateTime start, DateTime end) {
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!cursor.isAfter(last)) {
      if (_isTakenDay(cursor)) return true;
      cursor = cursor.add(const Duration(days: 1));
    }
    return false;
  }

  DateTime? _firstSelectableOnOrAfter(DateTime from, DateTime lastDate) {
    var cursor = DateTime(from.year, from.month, from.day);
    final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
    while (!cursor.isAfter(last)) {
      if (!_isTakenDay(cursor)) return cursor;
      cursor = cursor.add(const Duration(days: 1));
    }
    return null;
  }

  void _resetForm() {
    _reason.clear();
    setState(() {
      _startDate = null;
      _endDate = null;
      _formKey = GlobalKey<FormState>();
    });
    _takenCompanyKey = null;
    _ensureTakenDatesLoaded();
  }

  Future<void> _pickDate({required bool isStart}) async {
    await _ensureTakenDatesLoaded();
    if (!mounted) return;

    final firstDate = DateTime.now().subtract(const Duration(days: 1));
    final lastDate = DateTime.now().add(const Duration(days: 365));
    final preferred = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final initial =
        _firstSelectableOnOrAfter(preferred, lastDate) ??
            _firstSelectableOnOrAfter(firstDate, lastDate);
    if (initial == null) {
      SnackBarHelper.showInfo(
        context,
        'No available dates left in the selectable range.',
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      selectableDayPredicate: (day) => !_isTakenDay(day),
      helpText: isStart ? 'Select start date' : 'Select end date',
    );
    if (picked == null || !mounted) return;

    if (_isTakenDay(picked)) {
      SnackBarHelper.showInfo(
        context,
        'That date is already taken by an approved or pending leave.',
      );
      return;
    }

    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
        if (_endDate != null &&
            _rangeContainsTaken(_startDate!, _endDate!)) {
          _endDate = null;
          SnackBarHelper.showInfo(
            context,
            'End date cleared — the range crossed a taken leave day.',
          );
        }
      } else {
        if (_startDate != null &&
            _rangeContainsTaken(_startDate!, picked)) {
          SnackBarHelper.showInfo(
            context,
            'That range includes a date already on leave. Pick another end date.',
          );
          return;
        }
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    return formatWorkDate(date);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate == null || _endDate == null) {
      SnackBarHelper.showInfo(context, 'Select start and end dates.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      SnackBarHelper.showInfo(context, 'End date cannot be before start date.');
      return;
    }
    if (_rangeContainsTaken(_startDate!, _endDate!)) {
      SnackBarHelper.showInfo(
        context,
        'Your selection includes a date already taken by leave.',
      );
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
      _resetForm();
      SnackBarHelper.showSuccess(
        context,
        'Leave request submitted. Those days show as On Leave on your time card.',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        e is StateError ? e.message : 'Could not submit leave request.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final company = context.watch<CompanyProvider>().selectedCompany;
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    final takenKey = user == null || company == null
        ? null
        : '${user.id}|${company.id}|${company.firestoreId}';
    if (takenKey != _takenCompanyKey && !_loadingTaken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureTakenDatesLoaded();
      });
    }

    return DashboardScaffold(
      title: 'Request leave',
      currentRoute: AppRoutes.employeeRequestLeave,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: density.pagePadding,
            children: [
              CompactPageHeader(
                title: 'Request leave',
                subtitle: company == null
                    ? 'Select a company first, then submit a leave request.'
                    : 'Leave for ${company.name} appears as On Leave on your time card. '
                        'Dates already approved or pending are marked Taken and cannot be reused.',
              ),
              SizedBox(height: density.sectionGap + 6),
              if (company != null) ...[
                Container(
                  padding: density.cardPadding,
                  decoration: compactCardDecoration(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Taken leave dates',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          if (_loadingTaken)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (!_loadingTaken && _activeLeaves.isEmpty)
                        Text(
                          'No approved or pending leave yet. All dates are available.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        )
                      else
                        for (final leave in _activeLeaves) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: leave.status.toLowerCase() ==
                                            'approved'
                                        ? AppColors.success
                                            .withValues(alpha: 0.14)
                                        : AppColors.primaryDark
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    leave.status.toLowerCase() == 'approved'
                                        ? 'Approved'
                                        : 'Pending',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: leave.status.toLowerCase() ==
                                                  'approved'
                                              ? AppColors.success
                                              : AppColors.primaryDark,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    leave.startDate == leave.endDate
                                        ? leave.startDate
                                        : '${leave.startDate} → ${leave.endDate}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                    ],
                  ),
                ),
                SizedBox(height: density.sectionGap),
              ],
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
                      key: ValueKey(_formKey),
                      controller: _reason,
                      label: 'Reason',
                      hint: 'Any short reason is fine (e.g. Medical)',
                      textInputAction: TextInputAction.done,
                      autovalidateMode: AutovalidateMode.disabled,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a reason.';
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
