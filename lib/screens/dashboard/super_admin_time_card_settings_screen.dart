import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_model.dart';
import '../../models/employee_time_card_profile.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';
import '../../widgets/primary_button.dart';

class SuperAdminTimeCardSettingsScreen extends StatefulWidget {
  const SuperAdminTimeCardSettingsScreen({super.key});

  @override
  State<SuperAdminTimeCardSettingsScreen> createState() =>
      _SuperAdminTimeCardSettingsScreenState();
}

class _SuperAdminTimeCardSettingsScreenState
    extends State<SuperAdminTimeCardSettingsScreen> {
  late final LazyListPager _pager;
  String? _companyId;
  String? _employeeFilterId;
  String? _expandedUserId;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  bool _isSuperAdmin(UserRole? role) => role == UserRole.superAdmin;

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final auth = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();

    if (_isSuperAdmin(auth?.role)) {
      await companies.loadCompanies();
      if (!mounted) return;
      final initial = companies.selectedCompany?.id ??
          (companies.companies.isNotEmpty ? companies.companies.first.id : null);
      if (initial != null) {
        await _selectCompany(initial, resetEmployeeFilter: false);
      }
      return;
    }

    final company = companies.selectedCompany;
    if (company != null) {
      companies.loadUsers();
      await companies.loadStaff(company.id);
    }
  }

  Future<void> _selectCompany(
    String companyId, {
    bool resetEmployeeFilter = true,
  }) async {
    setState(() {
      _companyId = companyId;
      if (resetEmployeeFilter) {
        _employeeFilterId = null;
        _expandedUserId = null;
      }
      _pager.reset();
    });
    final companies = context.read<CompanyProvider>();
    companies.loadUsers();
    await companies.loadStaff(companyId);
  }

  CompanyModel? _activeCompany(CompanyProvider companies, bool isSuperAdmin) {
    if (isSuperAdmin) {
      final id = _companyId;
      if (id == null) return null;
      for (final company in companies.companies) {
        if (company.id == id) return company;
      }
      return null;
    }
    return companies.selectedCompany;
  }

  List<StaffAssignment> _allStaff(CompanyProvider companies) {
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final role = companies.memberAccessRole(member);
      return role == UserRole.employee || role == UserRole.admin;
    }).toList();
  }

  List<StaffAssignment> _visibleStaff(CompanyProvider companies) {
    final staff = _allStaff(companies);
    if (_employeeFilterId == null) return staff;
    return staff.where((member) => member.userId == _employeeFilterId).toList();
  }

  Future<void> _saveProfile({
    required CompanyModel company,
    required StaffAssignment member,
    required EmployeeTimeCardProfile profile,
  }) async {
    final ok = await context.read<CompanyProvider>().saveStaffTimeCardProfile(
          companyId: company.id,
          userId: member.userId,
          profile: profile,
          company: company,
          member: member,
          actor: context.read<AuthProvider>().user,
        );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        'Saved ${member.username}\'s time card settings.',
      );
      setState(() => _expandedUserId = null);
    } else {
      SnackBarHelper.showError(
        context,
        context.read<CompanyProvider>().errorMessage ??
            'Could not save settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final isSuperAdmin = _isSuperAdmin(auth?.role);
    final company = _activeCompany(companies, isSuperAdmin);
    final allStaff = company == null ? <StaffAssignment>[] : _allStaff(companies);
    final staff = company == null ? <StaffAssignment>[] : _visibleStaff(companies);
    final visible = _pager.takeVisible(staff);
    final hasMore = _pager.hasMore(staff.length);

    return DashboardScaffold(
      title: 'Time card settings',
      currentRoute: AppRoutes.superAdminTimeCardSettings,
      child: ListView(
        controller: _pager.scrollController,
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          CompactPageHeader(
            title: 'Time card settings',
            subtitle: isSuperAdmin
                ? 'Choose a company and employee, then set daily rate and weekly schedule.'
                : company == null
                    ? 'Select a company to set employee rates and schedules.'
                    : 'Set daily rate and weekly time in / time out for ${company.name}.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (!isSuperAdmin && company == null)
            const _HintCard(
              icon: Icons.business_outlined,
              message:
                  'Open a company from Switch company to manage employee schedules.',
            )
          else if (isSuperAdmin && companies.companies.isEmpty)
            const _HintCard(
              icon: Icons.business_outlined,
              message: 'No companies yet. Create a company first.',
            )
          else ...[
            _FilterBar(
              isSuperAdmin: isSuperAdmin,
              companies: isSuperAdmin ? companies.companies : const [],
              selectedCompanyId: _companyId,
              employeeFilterId: _employeeFilterId,
              staff: allStaff,
              onCompanyChanged: (companyId) {
                if (companyId != null) _selectCompany(companyId);
              },
              onEmployeeChanged: (userId) {
                setState(() {
                  _employeeFilterId = userId;
                  _expandedUserId = userId;
                  _pager.reset();
                });
              },
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            if (company == null)
              const _HintCard(
                icon: Icons.business_outlined,
                message: 'Select a company to view employee settings.',
              )
            else if (companies.isLoading && staff.isEmpty)
              const AppLoadingView(
                title: 'Loading settings',
                message: 'Fetching employee time card settings…',
              )
            else if (allStaff.isEmpty)
              const _HintCard(
                icon: Icons.groups_outlined,
                message: 'No employees or admins found for this company.',
              )
            else if (staff.isEmpty)
              const _HintCard(
                icon: Icons.filter_alt_off_outlined,
                message: 'No employee matches the selected filter.',
              )
            else ...[
              for (final member in visible) ...[
                _EmployeeSettingsTile(
                  member: member,
                  expanded: _expandedUserId == member.userId,
                  onToggle: () {
                    setState(() {
                      _expandedUserId = _expandedUserId == member.userId
                          ? null
                          : member.userId;
                    });
                  },
                  onSave: (profile) => _saveProfile(
                    company: company,
                    member: member,
                    profile: profile,
                  ),
                ),
                SizedBox(height: CompactPageStyle.of(context).cardGap),
              ],
              LazyListFooter(
                hasMore: hasMore,
                remaining: staff.length - visible.length,
                loadingMore: _pager.loadingMore,
                onLoadMore: () => _pager.loadMore(staff.length),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.isSuperAdmin,
    required this.companies,
    required this.selectedCompanyId,
    required this.employeeFilterId,
    required this.staff,
    required this.onCompanyChanged,
    required this.onEmployeeChanged,
  });

  final bool isSuperAdmin;
  final List<CompanyModel> companies;
  final String? selectedCompanyId;
  final String? employeeFilterId;
  final List<StaffAssignment> staff;
  final ValueChanged<String?> onCompanyChanged;
  final ValueChanged<String?> onEmployeeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sortedCompanies = [...companies]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Container(
      padding: CompactPageStyle.of(context).summaryPadding,
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          if (isSuperAdmin) ...[
            _DropdownShell(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: selectedCompanyId,
                  isExpanded: true,
                  isDense: true,
                  style: Theme.of(context).textTheme.bodySmall,
                  hint: const Text('Select company'),
                  items: [
                    for (final company in sortedCompanies)
                      DropdownMenuItem<String?>(
                        value: company.id,
                        child: Text(
                          company.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onCompanyChanged,
                ),
              ),
            ),
            SizedBox(height: CompactPageStyle.of(context).cardGap),
          ],
          _DropdownShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: employeeFilterId,
                isExpanded: true,
                isDense: true,
                style: Theme.of(context).textTheme.bodySmall,
                hint: const Text('All employees'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All employees'),
                  ),
                  for (final member in staff)
                    DropdownMenuItem<String?>(
                      value: member.userId,
                      child: Text(
                        member.username,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onEmployeeChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownShell extends StatelessWidget {
  const _DropdownShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: CompactPageStyle.of(context).filterHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: CompactPageStyle.of(context).cardPadding,
      decoration: BoxDecoration(
        color: colors.header,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.textHint, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeSettingsTile extends StatefulWidget {
  const _EmployeeSettingsTile({
    required this.member,
    required this.expanded,
    required this.onToggle,
    required this.onSave,
  });

  final StaffAssignment member;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(EmployeeTimeCardProfile profile) onSave;

  @override
  State<_EmployeeSettingsTile> createState() => _EmployeeSettingsTileState();
}

class _EmployeeSettingsTileState extends State<_EmployeeSettingsTile> {
  late TextEditingController _rateController;
  late EmployeeWeeklySchedule _week;
  bool _saving = false;
  bool _synced = false;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.member.timeCardProfile);
  }

  @override
  void didUpdateWidget(covariant _EmployeeSettingsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.expanded) {
      _synced = false;
    } else if (!_synced ||
        oldWidget.member.userId != widget.member.userId ||
        (!oldWidget.expanded && widget.expanded)) {
      _hydrate(widget.member.timeCardProfile);
    }
  }

  void _hydrate(EmployeeTimeCardProfile profile) {
    _rateController = TextEditingController(
      text: profile.dailyRate > 0
          ? (profile.dailyRate == profile.dailyRate.roundToDouble()
              ? profile.dailyRate.toStringAsFixed(0)
              : profile.dailyRate.toStringAsFixed(2))
          : '',
    );
    _week = profile.weeklySchedule;
    _synced = true;
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({
    required int weekday,
    required bool isTimeIn,
  }) async {
    final current = _week.forWeekday(weekday);
    final initial = TimeOfDay(
      hour: isTimeIn ? current.timeInHour : current.timeOutHour,
      minute: isTimeIn ? current.timeInMinute : current.timeOutMinute,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final current = _week.forWeekday(weekday);
      _week = _week.copyWithDay(
        weekday,
        isTimeIn
            ? current.copyWith(
                isWorkDay: true,
                timeInHour: picked.hour,
                timeInMinute: picked.minute,
              )
            : current.copyWith(
                isWorkDay: true,
                timeOutHour: picked.hour,
                timeOutMinute: picked.minute,
              ),
      );
    });
  }

  void _applyPreset(DayShiftSchedule preset) {
    setState(() {
      _week = EmployeeWeeklySchedule({
        for (final day in EmployeeWeeklySchedule.weekdayLabels.keys)
          day: day <= DateTime.friday
              ? preset.copyWith(isWorkDay: true)
              : DayShiftSchedule.off,
      });
    });
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rateController.text.trim()) ?? 0;
    if (rate < 0) {
      SnackBarHelper.showError(context, 'Daily rate cannot be negative.');
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(
      EmployeeTimeCardProfile(
        dailyRate: rate,
        weeklySchedule: _week,
      ),
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final profile = widget.member.timeCardProfile;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(
          color: widget.expanded ? AppColors.primaryDark : colors.border,
          width: widget.expanded ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
            child: Padding(
              padding: CompactPageStyle.of(context).cardPadding,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: colors.header,
                    child: Text(
                      widget.member.username.isEmpty
                          ? '?'
                          : widget.member.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.member.username,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${profile.rateLabel} · ${profile.weeklySchedule.summaryLabel}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded) ...[
            Divider(height: 1, color: colors.border),
            Padding(
              padding: CompactPageStyle.of(context).cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Daily salary rate',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  SizedBox(height: CompactPageStyle.of(context).cardGap),
                  TextField(
                    controller: _rateController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.]'),
                      ),
                    ],
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      prefixText: '₱ ',
                      hintText: '0.00',
                      filled: true,
                      fillColor: colors.inputFill,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(CompactPageStyle.of(context).radius),
                      ),
                    ),
                  ),
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                  Row(
                    children: [
                      Text(
                        'Weekly schedule',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      _PresetChip(
                        label: '9–6',
                        onTap: () => _applyPreset(DayShiftSchedule.nineToSix),
                      ),
                      SizedBox(width: CompactPageStyle.of(context).cardGap),
                      _PresetChip(
                        label: '10–7',
                        onTap: () => _applyPreset(DayShiftSchedule.tenToSeven),
                      ),
                    ],
                  ),
                  SizedBox(height: CompactPageStyle.of(context).cardGap),
                  for (final day
                      in EmployeeWeeklySchedule.weekdayLabels.keys) ...[
                    _DayRow(
                      label: EmployeeWeeklySchedule.weekdayLabels[day]!,
                      shift: _week.forWeekday(day),
                      onToggle: (enabled) {
                        setState(() {
                          final current = _week.forWeekday(day);
                          _week = _week.copyWithDay(
                            day,
                            enabled
                                ? (current.isWorkDay
                                    ? current
                                    : DayShiftSchedule.nineToSix)
                                : DayShiftSchedule.off,
                          );
                        });
                      },
                      onPickIn: () => _pickTime(weekday: day, isTimeIn: true),
                      onPickOut: () => _pickTime(weekday: day, isTimeIn: false),
                    ),
                    if (day != DateTime.sunday)
                      SizedBox(height: CompactPageStyle.of(context).cardGap),
                  ],
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                  PrimaryButton(
                    label: _saving ? 'Saving…' : 'Save settings',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.header,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.shift,
    required this.onToggle,
    required this.onPickIn,
    required this.onPickOut,
  });

  final String label;
  final DayShiftSchedule shift;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickIn;
  final VoidCallback onPickOut;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: shift.isWorkDay
                        ? colors.textPrimary
                        : colors.textHint,
                  ),
            ),
          ),
          Switch.adaptive(
            value: shift.isWorkDay,
            onChanged: onToggle,
            activeThumbColor: AppColors.primaryDark,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          if (!shift.isWorkDay)
            Expanded(
              child: Text(
                'Off',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textHint,
                    ),
              ),
            )
          else ...[
            Expanded(
              child: _TimeChip(
                label: shift.timeInLabel,
                onTap: onPickIn,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '–',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: _TimeChip(
                label: shift.timeOutLabel,
                onTap: onPickOut,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
          ),
        ),
      ),
    );
  }
}
