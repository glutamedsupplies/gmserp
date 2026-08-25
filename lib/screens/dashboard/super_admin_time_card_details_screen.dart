import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/leave_request.dart';
import '../../models/company_model.dart';
import '../../models/staff_assignment.dart';
import '../../models/time_card_table.dart';
import '../../models/time_card_salary.dart';
import '../../models/time_entry.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/time_card_settings_provider.dart';
import '../../services/leave_request_repository.dart';
import '../../services/time_card_change_request_repository.dart';
import '../../services/time_entry_repository.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/time_card_month_filter.dart';
import '../../widgets/time_card_report_table.dart';
import 'time_card_png_preview_screen.dart';

class SuperAdminTimeCardDetailsScreen extends StatefulWidget {
  const SuperAdminTimeCardDetailsScreen({super.key});

  @override
  State<SuperAdminTimeCardDetailsScreen> createState() =>
      _SuperAdminTimeCardDetailsScreenState();
}

class _SuperAdminTimeCardDetailsScreenState
    extends State<SuperAdminTimeCardDetailsScreen> {
  final _timeEntriesRepo = TimeEntryRepository();
  final _leaveRepo = LeaveRequestRepository();
  final _changeRequestRepo = TimeCardChangeRequestRepository();

  String? _loadedCompanyId;
  String? _companyId;
  bool _bootstrapped = false;
  bool _loading = false;
  String? _error;
  List<TimeEntry> _companyEntries = [];
  List<LeaveRequest> _companyLeaves = [];

  TimeCardPeriodFilter _periodFilter = TimeCardPeriodFilter.wholeMonth;
  DateTime _viewDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  String? _employeeFilterId; // null = all employees
  String _statusFilter = 'All';
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSuperAdmin(UserRole? role) => role == UserRole.superAdmin;

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    context.read<TimeCardSettingsProvider>().ensureLoaded();
    final auth = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();

    if (_isSuperAdmin(auth?.role)) {
      await companies.loadCompanies();
      if (!mounted) return;
      final initial = companies.selectedCompany?.id ??
          (companies.companies.isNotEmpty ? companies.companies.first.id : null);
      if (initial != null) {
        await _selectCompany(initial, resetFilters: false);
      }
      return;
    }

    final company = companies.selectedCompany;
    if (company == null) return;
    companies.loadUsers();
    await companies.loadStaff(company.id);
    await _loadCompanyData(
      company.id,
      companyDocumentId: company.firestoreId,
    );
  }

  Future<void> _selectCompany(
    String companyId, {
    bool resetFilters = true,
  }) async {
    CompanyModel? company;
    for (final item in context.read<CompanyProvider>().companies) {
      if (item.id == companyId) {
        company = item;
        break;
      }
    }

    setState(() {
      _companyId = companyId;
      if (resetFilters) {
        _employeeFilterId = null;
        _statusFilter = 'All';
        _search = '';
        _searchController.clear();
      }
      _loadedCompanyId = null;
    });

    final companies = context.read<CompanyProvider>();
    companies.loadUsers();
    await companies.loadStaff(companyId);
    await _loadCompanyData(
      companyId,
      companyDocumentId: company?.firestoreId,
    );
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

  Future<void> _loadCompanyData(
    String companyId, {
    String? companyDocumentId,
  }) async {
    if (_loadedCompanyId == companyId && _companyEntries.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadedCompanyId = companyId;
    });

    try {
      final results = await Future.wait([
        _timeEntriesRepo.listByCompanyId(
          companyId,
          companyDocumentId: companyDocumentId,
        ),
        _leaveRepo.listByCompanyId(companyId),
      ]);
      if (!mounted || _loadedCompanyId != companyId) return;
      setState(() {
        _companyEntries = results[0] as List<TimeEntry>;
        _companyLeaves = results[1] as List<LeaveRequest>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || _loadedCompanyId != companyId) return;
      setState(() {
        _companyEntries = [];
        _companyLeaves = [];
        _loading = false;
        _error = 'Unable to load employee time cards for this company.';
      });
    }
  }

  List<StaffAssignment> _staffMembers(CompanyProvider companies) {
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final role = companies.userById(member.userId)?.role;
      return role == UserRole.employee;
    }).toList();
  }

  List<StaffTimeCardSource> _sourcesForFilter(List<StaffAssignment> staff) {
    final selected = _employeeFilterId == null
        ? staff
        : staff.where((m) => m.userId == _employeeFilterId).toList();

    final query = _search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? selected
        : selected.where((m) {
            return m.username.toLowerCase().contains(query) ||
                m.email.toLowerCase().contains(query);
          }).toList();

    return filtered.map((member) {
      return StaffTimeCardSource(
        userId: member.userId,
        username: member.username,
        entries: _companyEntries
            .where((entry) => entry.userId == member.userId)
            .toList(),
        leaves: _companyLeaves
            .where((leave) => leave.userId == member.userId)
            .toList(),
        weeklySchedule: member.timeCardProfile.weeklySchedule,
      );
    }).toList();
  }

  List<TimeCardTableRow> _filteredRows(List<TimeCardTableRow> rows) {
    if (_statusFilter == 'All') return rows;
    return rows.where((row) => row.status == _statusFilter).toList();
  }

  void _openPngPreview({
    required CompanyModel company,
    required List<StaffAssignment> staff,
    required List<StaffTimeCardSource> sources,
    required List<TimeCardTableRow> rows,
    required String totalHours,
    required DateTime now,
    required TimeCardSchedule globalSchedule,
  }) {
    String employeeName = 'All employees';
    String employeeEmail = '${sources.length} staff';

    if (_employeeFilterId != null) {
      for (final member in staff) {
        if (member.userId == _employeeFilterId) {
          employeeName = member.username;
          employeeEmail = member.email;
          break;
        }
      }
    }

    final rates = {
      for (final member in staff) member.userId: member.timeCardProfile.dailyRate,
    };
    final names = {
      for (final member in staff) member.userId: member.username,
    };
    final entriesByUser = <String, List<TimeEntry>>{};
    for (final entry in _companyEntries) {
      entriesByUser.putIfAbsent(entry.userId, () => []).add(entry);
    }
    final weeklySchedules = {
      for (final member in staff)
        member.userId: member.timeCardProfile.weeklySchedule,
    };
    final salaryBreakdowns = computeSalaryBreakdowns(
      rows: rows,
      dailyRatesByUserId: rates,
      namesByUserId: names,
      entriesByUserId: entriesByUser,
      weeklySchedulesByUserId: weeklySchedules,
      globalSchedule: globalSchedule,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimeCardPngPreviewScreen(
          employeeName: employeeName,
          employeeEmail: employeeEmail,
          companyName: company.name,
          companyId: company.companyId,
          filter: _periodFilter,
          rows: rows,
          totalHours: totalHours,
          generatedAt: now,
          periodDate: _viewDate,
          salaryBreakdowns: salaryBreakdowns,
        ),
      ),
    );
  }

  Future<void> _openEditEntryModal({
    required CompanyModel company,
    required TimeCardTableRow row,
    required List<StaffAssignment> staff,
  }) async {
    StaffAssignment? member;
    for (final m in staff) {
      if (m.userId == row.employeeId) {
        member = m;
        break;
      }
    }
    if (member == null) return;
    final selectedMember = member;

    final localCandidates = _companyEntries
        .where(
          (e) => e.userId == row.employeeId && e.workDate == row.workDate,
        )
        .toList()
      ..sort((a, b) => a.timeIn.compareTo(b.timeIn));
    final localExisting =
        localCandidates.isEmpty ? null : localCandidates.first;

    // Live Firestore lookup — don't rely only on the in-memory cache.
    TimeEntry? existing = await _timeEntriesRepo.findPriorEntry(
      userId: selectedMember.userId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: row.workDate,
      entryId: localExisting?.id,
    );
    existing ??= localExisting;

    if (!mounted) return;

    final authRole = context.read<AuthProvider>().user?.role;
    final asSuperAdmin = _isSuperAdmin(authRole);
    if (!asSuperAdmin) {
      final pending = await _changeRequestRepo.findPendingForWorkDate(
        employeeId: selectedMember.userId,
        companyId: company.id,
        companyDocumentId: company.firestoreId,
        workDate: row.workDate,
      );
      if (!mounted) return;
      if (pending != null) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Request already pending'),
              content: Text(
                'A time-change request for ${selectedMember.username} on '
                '${row.workDate} is already waiting for Super Admin review.\n\n'
                'You can submit again only after it is approved or rejected.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }
    }

    final workDate = parseWorkDateString(row.workDate) ?? _viewDate;
    final baselineTimeIn = existing?.timeIn ??
        parseClockTimeOnDate(workDate, row.timeIn);
    final baselineTimeOut = existing != null
        ? existing.timeOut
        : parseClockTimeOnDate(workDate, row.timeOut);

    TimeOfDay timeIn = baselineTimeIn == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(hour: baselineTimeIn.hour, minute: baselineTimeIn.minute);
    var isActive = baselineTimeIn != null && baselineTimeOut == null;
    TimeOfDay timeOut = baselineTimeOut == null
        ? const TimeOfDay(hour: 18, minute: 0)
        : TimeOfDay(
            hour: baselineTimeOut.hour,
            minute: baselineTimeOut.minute,
          );

    final currentSummary = baselineTimeIn == null
        ? 'No prior record on file'
        : '${formatClockTime(baselineTimeIn)} → '
            '${baselineTimeOut == null ? 'Open' : formatClockTime(baselineTimeOut)}';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var saving = false;

        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> pickTimeIn() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: timeIn,
              );
              if (picked == null) return;
              setStateDialog(() => timeIn = picked);
            }

            Future<void> pickTimeOut() async {
              final picked = await showTimePicker(
                context: dialogContext,
                initialTime: timeOut,
              );
              if (picked == null) return;
              setStateDialog(() => timeOut = picked);
            }

            return AlertDialog(
              title: Text(
                _isSuperAdmin(context.read<AuthProvider>().user?.role)
                    ? 'Edit time in / time out'
                    : 'Request time change',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isSuperAdmin(context.read<AuthProvider>().user?.role))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Changes are sent to Super Admin for approval before they are saved.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Current: $currentSummary',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Time in'),
                      trailing: Text(timeIn.format(context)),
                      onTap: saving ? null : pickTimeIn,
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Still on shift (no time out)'),
                      value: isActive,
                      onChanged: saving
                          ? null
                          : (v) => setStateDialog(() => isActive = v),
                    ),
                    if (!isActive)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Time out'),
                        trailing: Text(timeOut.format(context)),
                        onTap: saving ? null : pickTimeOut,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setStateDialog(() => saving = true);
                          try {
                            final newTimeIn = DateTime(
                              workDate.year,
                              workDate.month,
                              workDate.day,
                              timeIn.hour,
                              timeIn.minute,
                            );
                            final newTimeOut = isActive
                                ? null
                                : DateTime(
                                    workDate.year,
                                    workDate.month,
                                    workDate.day,
                                    timeOut.hour,
                                    timeOut.minute,
                                  );

                            final authUser =
                                context.read<AuthProvider>().user;
                            final asSuperAdmin = _isSuperAdmin(authUser?.role);

                            if (asSuperAdmin) {
                              await _timeEntriesRepo.adminSaveEntry(
                                entryId: existing?.id,
                                userId: selectedMember.userId,
                                userEmail: selectedMember.email,
                                username: selectedMember.username,
                                company: company,
                                timeIn: newTimeIn,
                                timeOut: newTimeOut,
                              );
                            } else {
                              if (authUser == null) {
                                throw StateError('Sign in to submit a request.');
                              }
                              await _changeRequestRepo.submit(
                                requester: authUser,
                                company: company,
                                employeeId: selectedMember.userId,
                                employeeName: selectedMember.username,
                                employeeEmail: selectedMember.email,
                                workDate: row.workDate,
                                proposedTimeIn: newTimeIn,
                                proposedTimeOut: newTimeOut,
                                currentTimeIn: baselineTimeIn,
                                currentTimeOut: baselineTimeOut,
                                existingEntryId: existing?.id,
                              );
                            }

                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (asSuperAdmin) {
                              _loadedCompanyId = null;
                              await _loadCompanyData(
                                company.id,
                                companyDocumentId: company.firestoreId,
                              );
                              if (!mounted) return;
                              SnackBarHelper.showSuccess(
                                context,
                                'Time entry updated.',
                              );
                            } else {
                              SnackBarHelper.showSuccess(
                                context,
                                'Change request sent to Super Admin.',
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            setStateDialog(() => saving = false);
                            SnackBarHelper.showError(
                              context,
                              e is StateError
                                  ? e.message
                                  : 'Could not submit time change.',
                            );
                          }
                        },
                  child: Text(
                    _isSuperAdmin(context.read<AuthProvider>().user?.role)
                        ? 'Save'
                        : 'Submit request',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final schedule = context.watch<TimeCardSettingsProvider>().schedule;
    final isSuperAdmin = _isSuperAdmin(auth?.role);
    final company = _activeCompany(companies, isSuperAdmin);

    if (!isSuperAdmin && company != null && _loadedCompanyId != company.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        companies.loadStaff(company.id);
        _loadCompanyData(
          company.id,
          companyDocumentId: company.firestoreId,
        );
      });
    }

    final staff = company == null ? <StaffAssignment>[] : _staffMembers(companies);
    final sources = _sourcesForFilter(staff);
    final now = DateTime.now();
    final tableRows = _filteredRows(
      buildStaffTimeCardTableRows(
        staff: sources,
        filter: _periodFilter,
        now: now,
        viewDate: _viewDate,
        schedule: schedule,
      ),
    );
    final entriesForTotal = _employeeFilterId == null
        ? _companyEntries
        : _companyEntries
            .where((entry) => entry.userId == _employeeFilterId)
            .toList();
    final periodTotal = formatDurationShort(
      totalDurationForRows(
        entriesForTotal,
        _periodFilter,
        now,
        viewDate: _viewDate,
      ),
    );

    return DashboardScaffold(
      title: 'Time card details',
      currentRoute: AppRoutes.superAdminTimeCardDetails,
      child: ListView(
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          CompactPageHeader(
            title: 'Time card details',
            subtitle: isSuperAdmin
                ? 'Review attendance by company, employee, and period.'
                : company == null
                    ? 'Select a company to review employee time cards.'
                    : 'Attendance for ${company.name} · '
                        '${staff.length} staff · shift ${schedule.shiftStartLabel}',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (!isSuperAdmin && company == null)
            const _MessageCard(
              icon: Icons.business_outlined,
              message:
                  'Open a company from Switch company to view all employee time cards.',
            )
          else if (isSuperAdmin && companies.companies.isEmpty)
            const _MessageCard(
              icon: Icons.business_outlined,
              message: 'No companies yet. Create a company first.',
            )
          else if (company == null)
            const _MessageCard(
              icon: Icons.business_outlined,
              message: 'Select a company to view employee time cards.',
            )
          else ...[
            _FilterBar(
              isSuperAdmin: isSuperAdmin,
              companies: isSuperAdmin ? companies.companies : const [],
              selectedCompanyId: _companyId,
              periodFilter: _periodFilter,
              viewDate: _viewDate,
              employeeFilterId: _employeeFilterId,
              statusFilter: _statusFilter,
              staff: staff,
              searchController: _searchController,
              onCompanyChanged: (companyId) {
                if (companyId != null) _selectCompany(companyId);
              },
              onPeriodChanged: (value) =>
                  setState(() => _periodFilter = value),
              onViewDateChanged: (value) => setState(() => _viewDate = value),
              onEmployeeChanged: (value) =>
                  setState(() => _employeeFilterId = value),
              onStatusChanged: (value) =>
                  setState(() => _statusFilter = value),
              onSearchChanged: (value) => setState(() => _search = value),
              onRefresh: () async {
                _loadedCompanyId = null;
                await companies.loadStaff(company.id);
                await _loadCompanyData(
                  company.id,
                  companyDocumentId: company.firestoreId,
                );
              },
              onViewPressed: tableRows.isEmpty
                  ? null
                  : () => _openPngPreview(
                        company: company,
                        staff: staff,
                        sources: sources,
                        rows: tableRows,
                        totalHours: periodTotal,
                        now: now,
                        globalSchedule: schedule,
                      ),
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            _SummaryStrip(
              staffCount: sources.length,
              rowCount: tableRows.length,
              present: tableRows.where((r) => r.status == 'Present').length,
              late: tableRows.where((r) => r.status == 'Late').length,
              absent: tableRows.where((r) => r.status == 'Absent').length,
              onLeave: tableRows.where((r) => r.status == 'On Leave').length,
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            if (_loading)
              const AppLoadingView(
                title: 'Loading time cards',
                message: 'Fetching staff clock entries…',
              )
            else if (_error != null)
              _MessageCard(icon: Icons.error_outline, message: _error!)
            else if (staff.isEmpty)
              const _MessageCard(
                icon: Icons.groups_outlined,
                message: 'No employees or admins are assigned to this company.',
              )
            else if (tableRows.isEmpty)
              const _MessageCard(
                icon: Icons.filter_alt_off_outlined,
                message: 'No time card rows match the current filters.',
              )
            else
              TimeCardReportTable(
                rows: tableRows,
                compact: true,
                onEditRow: (row) {
                  _openEditEntryModal(
                    company: company,
                    row: row,
                    staff: staff,
                  );
                },
              ),
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
    required this.periodFilter,
    required this.viewDate,
    required this.employeeFilterId,
    required this.statusFilter,
    required this.staff,
    required this.searchController,
    required this.onCompanyChanged,
    required this.onPeriodChanged,
    required this.onViewDateChanged,
    required this.onEmployeeChanged,
    required this.onStatusChanged,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onViewPressed,
  });

  final bool isSuperAdmin;
  final List<CompanyModel> companies;
  final String? selectedCompanyId;
  final TimeCardPeriodFilter periodFilter;
  final DateTime viewDate;
  final String? employeeFilterId;
  final String statusFilter;
  final List<StaffAssignment> staff;
  final TextEditingController searchController;
  final ValueChanged<String?> onCompanyChanged;
  final ValueChanged<TimeCardPeriodFilter> onPeriodChanged;
  final ValueChanged<DateTime> onViewDateChanged;
  final ValueChanged<String?> onEmployeeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback? onViewPressed;

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
          TimeCardMonthFilter(
            viewDate: viewDate,
            onViewDateChanged: onViewDateChanged,
          ),
          SizedBox(height: CompactPageStyle.of(context).cardGap),
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
          Row(
            children: [
              Expanded(
                child: _DropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TimeCardPeriodFilter>(
                      value: periodFilter,
                      isExpanded: true,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodySmall,
                      items: [
                        for (final option in TimeCardPeriodFilter.values)
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onPeriodChanged(value);
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: CompactPageStyle.of(context).cardGap),
              Expanded(
                child: _DropdownShell(
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
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).cardGap),
          Row(
            children: [
              Expanded(
                child: _DropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: statusFilter,
                      isExpanded: true,
                      isDense: true,
                      style: Theme.of(context).textTheme.bodySmall,
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All status')),
                        DropdownMenuItem(
                          value: 'Present',
                          child: Text('Present'),
                        ),
                        DropdownMenuItem(value: 'Late', child: Text('Late')),
                        DropdownMenuItem(
                          value: 'Absent',
                          child: Text('Absent'),
                        ),
                        DropdownMenuItem(
                          value: 'On Leave',
                          child: Text('On Leave'),
                        ),
                        DropdownMenuItem(value: 'Off', child: Text('Off')),
                      ],
                      onChanged: (value) {
                        if (value != null) onStatusChanged(value);
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(width: CompactPageStyle.of(context).cardGap),
              FilledButton.icon(
                onPressed: onViewPressed,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('View'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, CompactPageStyle.of(context).filterHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  textStyle: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: AppColors.primaryDark,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          SizedBox(height: CompactPageStyle.of(context).cardGap),
          CompactSearchField(
            controller: searchController,
            onChanged: onSearchChanged,
            hintText: 'Search employee name or email',
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

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.staffCount,
    required this.rowCount,
    required this.present,
    required this.late,
    required this.absent,
    required this.onLeave,
  });

  final int staffCount;
  final int rowCount;
  final int present;
  final int late;
  final int absent;
  final int onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final items = [
      ('Staff', '$staffCount', colors.textPrimary),
      ('Rows', '$rowCount', colors.textPrimary),
      ('Present', '$present', AppColors.success),
      ('Late', '$late', const Color(0xFFD97706)),
      ('Absent', '$absent', AppColors.error),
      ('Leave', '$onLeave', AppColors.primaryDark),
    ];

    return Container(
      padding: CompactPageStyle.of(context).summaryPadding,
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 24, color: colors.border),
            Expanded(
              child: Column(
                children: [
                  Text(
                    items[i].$2,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: items[i].$3,
                        ),
                  ),
                  Text(
                    items[i].$1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});

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
