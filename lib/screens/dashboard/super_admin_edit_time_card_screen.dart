import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/time_card_schedule.dart';
import '../../providers/time_card_settings_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/primary_button.dart';

class SuperAdminEditTimeCardScreen extends StatefulWidget {
  const SuperAdminEditTimeCardScreen({super.key});

  @override
  State<SuperAdminEditTimeCardScreen> createState() =>
      _SuperAdminEditTimeCardScreenState();
}

class _SuperAdminEditTimeCardScreenState
    extends State<SuperAdminEditTimeCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _workdayHours = TextEditingController();
  final _breakMinutes = TextEditingController();
  final _overtimeAfter = TextEditingController();
  final _lateGrace = TextEditingController();
  WorkWeekPattern _workWeek = WorkWeekPattern.monFri;
  TimeOfDay _shiftStart = const TimeOfDay(hour: 9, minute: 0);
  bool _hydrated = false;

  @override
  void dispose() {
    _workdayHours.dispose();
    _breakMinutes.dispose();
    _overtimeAfter.dispose();
    _lateGrace.dispose();
    super.dispose();
  }

  void _hydrateFrom(TimeCardSchedule schedule) {
    _workdayHours.text = '${schedule.workdayHours}';
    _breakMinutes.text = '${schedule.breakMinutes}';
    _overtimeAfter.text = '${schedule.overtimeAfterHours}';
    _lateGrace.text = '${schedule.lateGraceMinutes}';
    _workWeek = schedule.workWeek;
    _shiftStart = TimeOfDay(
      hour: schedule.shiftStartHour,
      minute: schedule.shiftStartMinute,
    );
    _hydrated = true;
  }

  Future<void> _pickShiftStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _shiftStart,
    );
    if (picked == null || !mounted) return;
    setState(() => _shiftStart = picked);
  }

  String _formatTimeOfDay(TimeOfDay value) {
    final hour24 = value.hour;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final h = hour12.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final schedule = TimeCardSchedule(
      workdayHours: int.parse(_workdayHours.text.trim()),
      breakMinutes: int.parse(_breakMinutes.text.trim()),
      overtimeAfterHours: int.parse(_overtimeAfter.text.trim()),
      workWeek: _workWeek,
      shiftStartHour: _shiftStart.hour,
      shiftStartMinute: _shiftStart.minute,
      lateGraceMinutes: int.parse(_lateGrace.text.trim()),
    );

    final ok = await context.read<TimeCardSettingsProvider>().save(schedule);
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        'Time card schedule saved. Status uses Present, Late, Absent, and On Leave.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        context.read<TimeCardSettingsProvider>().errorMessage ??
            'Could not save schedule.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TimeCardSettingsProvider>();
    final colors = AppColors.of(context);

    if (!settings.isLoading && !_hydrated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hydrated) return;
        setState(() => _hydrateFrom(settings.schedule));
      });
    }

    return DashboardScaffold(
      title: 'Edit time card',
      currentRoute: AppRoutes.superAdminEditTimeCard,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Text(
                'Edit time card',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Set the work schedule used for Present, Late, Absent, and On Leave.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (settings.isLoading && !_hydrated)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: colors.header,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _pickShiftStart,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  color: AppColors.primaryDark,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Shift start time',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                      Text(
                                        _formatTimeOfDay(_shiftStart),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Change',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: AppColors.primaryDark,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        controller: _lateGrace,
                        label: 'Late grace (minutes)',
                        hint: 'e.g. 15',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final minutes = int.tryParse(value?.trim() ?? '');
                          if (minutes == null ||
                              minutes < 0 ||
                              minutes > 240) {
                            return 'Enter minutes between 0 and 240.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Clock-in after start + grace is marked Late. '
                        'No clock-in on a work day is Absent.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        controller: _workdayHours,
                        label: 'Standard workday (hours)',
                        hint: 'e.g. 8',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final hours = int.tryParse(value?.trim() ?? '');
                          if (hours == null || hours <= 0 || hours > 24) {
                            return 'Enter hours between 1 and 24.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        controller: _breakMinutes,
                        label: 'Break allowance (minutes)',
                        hint: 'e.g. 60',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final minutes = int.tryParse(value?.trim() ?? '');
                          if (minutes == null ||
                              minutes < 0 ||
                              minutes > 480) {
                            return 'Enter minutes between 0 and 480.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      CustomTextField(
                        controller: _overtimeAfter,
                        label: 'Overtime after (hours / day)',
                        hint: 'e.g. 8',
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final hours = int.tryParse(value?.trim() ?? '');
                          if (hours == null || hours <= 0 || hours > 24) {
                            return 'Enter hours between 1 and 24.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<WorkWeekPattern>(
                        initialValue: _workWeek,
                        decoration: const InputDecoration(
                          labelText: 'Work week',
                        ),
                        items: [
                          for (final pattern in WorkWeekPattern.values)
                            DropdownMenuItem(
                              value: pattern,
                              child: Text(pattern.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _workWeek = value);
                        },
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: 'Save time card',
                        isLoading: settings.isSaving,
                        onPressed: settings.isSaving ? null : _save,
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
