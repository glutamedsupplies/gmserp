import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../models/company_model.dart';
import '../../models/company_task.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SuperAdminEmployeeListsScreen extends StatefulWidget {
  const SuperAdminEmployeeListsScreen({super.key});

  @override
  State<SuperAdminEmployeeListsScreen> createState() =>
      _SuperAdminEmployeeListsScreenState();
}

enum _MemberRoleFilter { all, admin, employee }

class _SuperAdminEmployeeListsScreenState
    extends State<SuperAdminEmployeeListsScreen> {
  final _search = TextEditingController();
  late final LazyListPager _pager;
  String? _companyId;
  _MemberRoleFilter _roleFilter = _MemberRoleFilter.all;

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final companies = context.read<CompanyProvider>();
      await companies.loadCompanies();
      if (!mounted) return;
      if (companies.companies.isNotEmpty) {
        await _selectCompany(companies.companies.first.id);
      }
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _selectCompany(String companyId) async {
    setState(() {
      _companyId = companyId;
      _search.clear();
      _roleFilter = _MemberRoleFilter.all;
      _pager.reset();
    });
    await context.read<CompanyProvider>().loadCompanyUsers(companyId);
  }

  UserRole? _roleFilterValue(_MemberRoleFilter filter) {
    switch (filter) {
      case _MemberRoleFilter.all:
        return null;
      case _MemberRoleFilter.admin:
        return UserRole.admin;
      case _MemberRoleFilter.employee:
        return UserRole.employee;
    }
  }

  bool _matchesRoleFilter(CompanyProvider companies, StaffAssignment member) {
    final filterRole = _roleFilterValue(_roleFilter);
    if (filterRole == null) return true;
    return companies.memberAccessRole(member) == filterRole;
  }

  int _countByRole(CompanyProvider companies, UserRole role) {
    return companies.staff
        .where((member) => companies.memberAccessRole(member) == role)
        .length;
  }

  CompanyModel? _selectedCompany(CompanyProvider companies) {
    final id = _companyId;
    if (id == null) return null;
    for (final company in companies.companies) {
      if (company.id == id) return company;
    }
    return null;
  }

  List<StaffAssignment> _filteredStaff(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    final staff = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return staff.where((member) {
      if (!_matchesRoleFilter(companies, member)) return false;
      if (query.isEmpty) return true;
      final level =
          companies.memberAccessRole(member).label.toLowerCase();
      return member.username.toLowerCase().contains(query) ||
          member.email.toLowerCase().contains(query) ||
          member.userId.toLowerCase().contains(query) ||
          member.tasks.any((task) => task.toLowerCase().contains(query)) ||
          member.jobRole.toLowerCase().contains(query) ||
          level.contains(query);
    }).toList();
  }

  Future<void> _addEmployee() async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) {
      SnackBarHelper.showInfo(context, 'Select a company first.');
      return;
    }

    final companies = context.read<CompanyProvider>();
    final available = companies.usersNotInCompany();
    if (available.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        'Every user is already in this company, or there are no users to add.',
      );
      return;
    }

    final selected = await showModalBottomSheet<_AddMemberPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CompactPageStyle.read(context).radius),
        ),
      ),
      builder: (context) => _AddEmployeeSheet(users: available),
    );
    if (selected == null || !mounted) return;

    final ok = await companies.addCompanyMember(
      companyId: company.id,
      user: selected.user,
      accessLevel: selected.accessLevel,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        '${selected.user.username} was added to ${company.name} as ${selected.accessLevel.label}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not add the employee.',
      );
    }
  }

  Future<void> _removeEmployee(StaffAssignment member) async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove employee'),
        content: Text(
          'Remove ${member.username} from ${company.name}? Their account stays in the system.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final companies = context.read<CompanyProvider>();
    final ok = await companies.removeCompanyMember(
      companyId: company.id,
      userId: member.userId,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(context, '${member.username} was removed.');
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not remove the employee.',
      );
    }
  }

  Future<void> _changeAccess(StaffAssignment member) async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) return;

    final companies = context.read<CompanyProvider>();
    final current = companies.memberAccessRole(member);
    final selected = await showModalBottomSheet<UserRole>(
      context: context,
      backgroundColor: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CompactPageStyle.read(context).radius),
        ),
      ),
      builder: (context) {
        final colors = AppColors.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Access in ${company.name}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This only affects ${member.username} in this company — not their access in other companies.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
                const SizedBox(height: 14),
                for (final level in [UserRole.employee, UserRole.admin])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: current == level
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : colors.inputFill,
                      borderRadius: BorderRadius.circular(
                        CompactPageStyle.of(context).radius,
                      ),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CompactPageStyle.of(context).radius,
                          ),
                          side: BorderSide(
                            color: current == level
                                ? AppColors.primary
                                : colors.border,
                          ),
                        ),
                        title: Text(level.label),
                        trailing: current == level
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, level),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || selected == current || !mounted) return;

    final ok = await companies.setCompanyMemberAccess(
      companyId: company.id,
      userId: member.userId,
      accessLevel: selected,
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        '${member.username} is now ${selected.label} in ${company.name}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not update access.',
      );
    }
  }

  Future<void> _assignRoleAndTasks(StaffAssignment member) async {
    final company = _selectedCompany(context.read<CompanyProvider>());
    if (company == null) return;

    final companies = context.read<CompanyProvider>();
    if (companies.roles.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        'Add roles under Role lists first, then assign them here.',
      );
      return;
    }

    final selected = await showModalBottomSheet<_StaffRoleTaskPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CompactPageStyle.read(context).radius),
        ),
      ),
      builder: (context) => _AssignEmployeeSheet(
        member: member,
        roles: companies.roles,
        tasks: companies.tasks,
      ),
    );
    if (selected == null || !mounted) return;

    final ok = await companies.assignStaff(
      companyId: company.id,
      assignment: StaffAssignment(
        userId: member.userId,
        username: member.username,
        email: member.email,
        roleId: selected.roleId,
        jobRole: selected.roleName,
        tasks: selected.tasks,
        accessLevel: companies.memberAccessRole(member).storageValue,
        timeCardProfile: member.timeCardProfile,
      ),
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.showSuccess(
        context,
        selected.tasks.isEmpty
            ? '${member.username} has no role or tasks assigned.'
            : '${member.username} was assigned ${selected.roleName} • ${selected.tasks.join(', ')}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not save the assignment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final company = _selectedCompany(companies);
    final members = _filteredStaff(companies);
    final visible = _pager.takeVisible(members);
    final hasMore = _pager.hasMore(members.length);
    final total = companies.staff.length;
    final adminCount = _countByRole(companies, UserRole.admin);
    final employeeCount = _countByRole(companies, UserRole.employee);
    final assigned = companies.staff
        .where((member) => member.jobRole.isNotEmpty || member.tasks.isNotEmpty)
        .length;
    final hasFilters =
        _search.text.trim().isNotEmpty || _roleFilter != _MemberRoleFilter.all;

    return DashboardScaffold(
      title: 'Employee lists',
      currentRoute: AppRoutes.superAdminEmployees,
      child: ListView(
        controller: _pager.scrollController,
        padding: CompactPageStyle.of(context).pagePadding,
        children: [
          const CompactPageHeader(
            title: 'Employee lists',
            subtitle:
                'Select a company, add admins and employees, then tap to assign role and tasks.',
          ),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          if (companies.companies.isEmpty)
            _EmptyState(
              icon: Icons.business_rounded,
              title: 'No companies yet',
              message: 'Create a company first, then add employees here.',
            )
          else ...[
            _SummaryCard(
              companyName: company?.name ?? 'Select company',
              total: total,
              adminCount: adminCount,
              employeeCount: employeeCount,
              assigned: assigned,
              showing: members.length,
              hasFilters: hasFilters,
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            _CompanySearchDropdown(
              companies: companies.companies,
              selectedId: _companyId,
              logoFor: companies.logoFor,
              onSelected: _selectCompany,
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            Text(
              'Role',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.of(context).textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _RoleFilterChip(
                    label: 'All',
                    selected: _roleFilter == _MemberRoleFilter.all,
                    onSelected: () => setState(() {
                      _roleFilter = _MemberRoleFilter.all;
                      _pager.reset();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _RoleFilterChip(
                    label: 'Admin',
                    selected: _roleFilter == _MemberRoleFilter.admin,
                    onSelected: () => setState(() {
                      _roleFilter = _MemberRoleFilter.admin;
                      _pager.reset();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _RoleFilterChip(
                    label: 'Employee',
                    selected: _roleFilter == _MemberRoleFilter.employee,
                    onSelected: () => setState(() {
                      _roleFilter = _MemberRoleFilter.employee;
                      _pager.reset();
                    }),
                  ),
                ],
              ),
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            Row(
              children: [
                Expanded(
                  child: CompactSearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {
                      _pager.reset();
                    }),
                    hintText: 'Search name, email, role, or task',
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed:
                      companies.isLoading || company == null ? null : _addEmployee,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            if (companies.isLoading)
              const AppLoadingView(
                title: 'Loading employees',
                message: 'Fetching company members…',
              )
            else if (companies.staff.isEmpty)
              _EmptyState(
                icon: Icons.groups_outlined,
                title: 'No members yet',
                message: 'Add an admin or employee to this company to get started.',
                actionLabel: 'Add member',
                onAction: company == null ? null : _addEmployee,
              )
            else if (members.isEmpty)
              _EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'No matches',
                message: 'Try another role filter or search term.',
                actionLabel: 'Clear filters',
                onAction: () {
                  _search.clear();
                  setState(() {
                    _roleFilter = _MemberRoleFilter.all;
                    _pager.reset();
                  });
                },
              )
            else ...[
              ...visible.map((member) {
                final level = companies.memberAccessRole(member);
                return _EmployeeCard(
                  member: member,
                  levelLabel: level.label,
                  onTap: () => _assignRoleAndTasks(member),
                  onChangeAccess: () => _changeAccess(member),
                  onRemove: () => _removeEmployee(member),
                );
              }),
              LazyListFooter(
                hasMore: hasMore,
                remaining: members.length - visible.length,
                loadingMore: _pager.loadingMore,
                onLoadMore: () => _pager.loadMore(members.length),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.companyName,
    required this.total,
    required this.adminCount,
    required this.employeeCount,
    required this.assigned,
    required this.showing,
    required this.hasFilters,
  });

  final String companyName;
  final int total;
  final int adminCount;
  final int employeeCount;
  final int assigned;
  final int showing;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final countLabel = hasFilters
        ? 'Showing $showing of $total'
        : '$total members ($adminCount admin, $employeeCount employee)';

    return Container(
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
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
            ),
            child: const Icon(
              Icons.badge_outlined,
              color: AppColors.primaryDark,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companyName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$countLabel  •  $assigned assigned',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySearchDropdown extends StatelessWidget {
  const _CompanySearchDropdown({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
    required this.onSelected,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;
  final ValueChanged<String> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(CompactPageStyle.read(context).radius),
        ),
      ),
      builder: (context) => _CompanyPickerSheet(
        companies: companies,
        selectedId: selectedId,
        logoFor: logoFor,
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    CompanyModel? selected;
    for (final company in companies) {
      if (company.id == selectedId) {
        selected = company;
        break;
      }
    }

    return Material(
      color: colors.inputFill,
      borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        onTap: () => _openPicker(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Company',
            isDense: true,
            filled: true,
            fillColor: colors.inputFill,
            contentPadding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              borderSide: BorderSide(color: colors.border),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colors.textSecondary,
            ),
          ),
          child: Row(
            children: [
              if (selected != null) ...[
                UserAvatar(
                  bytes: logoFor(selected.id),
                  name: selected.name,
                  size: 24,
                ),
                const SizedBox(width: 8),
              ] else
                Icon(
                  Icons.business_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
              if (selected == null) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected == null
                      ? 'Search and select a company'
                      : '${selected.name}  •  ${selected.companyId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected == null
                            ? colors.textHint
                            : colors.textPrimary,
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

class _CompanyPickerSheet extends StatefulWidget {
  const _CompanyPickerSheet({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;

  @override
  State<_CompanyPickerSheet> createState() => _CompanyPickerSheetState();
}

class _CompanyPickerSheetState extends State<_CompanyPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CompanyModel> get _filtered {
    final needle = _query.text.trim().toLowerCase();
    if (needle.isEmpty) return widget.companies;
    return widget.companies.where((company) {
      return company.name.toLowerCase().contains(needle) ||
          company.companyId.toLowerCase().contains(needle) ||
          company.id.toLowerCase().contains(needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
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
              'Select company',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
            Text(
              'Search by company name or ID.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: Theme.of(context).textTheme.bodySmall,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                hintText: 'Search companies...',
                hintStyle: TextStyle(fontSize: 12, color: colors.textHint),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: colors.textHint,
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 32),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                filled: true,
                fillColor: colors.card,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No companies match that search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          SizedBox(height: CompactPageStyle.of(context).cardGap),
                      itemBuilder: (context, index) {
                        final company = items[index];
                        final selected = company.id == widget.selectedId;
                        return Material(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.16)
                              : colors.inputFill,
                          borderRadius:
                              BorderRadius.circular(CompactPageStyle.of(context).radius),
                          child: ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                CompactPageStyle.of(context).radius,
                              ),
                              side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : colors.border,
                              ),
                            ),
                            leading: UserAvatar(
                              bytes: widget.logoFor(company.id),
                              name: company.name,
                              size: 32,
                            ),
                            title: Text(
                              company.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            subtitle: Text(
                              'ID: ${company.companyId}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primaryDark,
                                    size: 20,
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, company.id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.member,
    required this.levelLabel,
    required this.onTap,
    required this.onChangeAccess,
    required this.onRemove,
  });

  final StaffAssignment member;
  final String levelLabel;
  final VoidCallback onTap;
  final VoidCallback onChangeAccess;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final name =
        member.username.isEmpty ? 'Unnamed employee' : member.username;

    return Padding(
      padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
      child: Material(
        color: colors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: CompactPageStyle.of(context).cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  name: name,
                  bytes: null,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _MiniChip(
                            label: levelLabel,
                            fill: colors.chip,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member.email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: CompactPageStyle.of(context).sectionGap),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniChip(
                            label: member.jobRole.isEmpty
                                ? 'No role'
                                : member.jobRole,
                            fill: member.jobRole.isEmpty
                                ? colors.inputFill
                                : AppColors.primary.withValues(alpha: 0.16),
                            bold: member.jobRole.isNotEmpty,
                          ),
                          if (member.tasks.isEmpty)
                            _MiniChip(
                              label: 'No tasks',
                              fill: colors.inputFill,
                            )
                          else
                            ...member.tasks.take(3).map(
                                  (task) => _MiniChip(
                                    label: task,
                                    fill: colors.inputFill,
                                  ),
                                ),
                          if (member.tasks.length > 3)
                            _MiniChip(
                              label: '+${member.tasks.length - 3}',
                              fill: colors.inputFill,
                              bold: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Assign role & tasks',
                  visualDensity: VisualDensity.compact,
                  onPressed: onTap,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Company access level',
                  visualDensity: VisualDensity.compact,
                  onPressed: onChangeAccess,
                  icon: Icon(
                    Icons.manage_accounts_outlined,
                    color: colors.textPrimary,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.person_remove_outlined,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.28),
      backgroundColor: colors.inputFill,
      side: BorderSide(
        color: selected ? AppColors.primary : colors.border,
      ),
      labelStyle: TextStyle(
        color: colors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.fill,
    this.bold = false,
  });

  final String label;
  final Color fill;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.textSecondary),
          SizedBox(height: CompactPageStyle.of(context).sectionGap),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          if (onAction != null && actionLabel != null) ...[
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _AddMemberPick {
  const _AddMemberPick({required this.user, required this.accessLevel});

  final UserModel user;
  final UserRole accessLevel;
}

class _AddEmployeeSheet extends StatefulWidget {
  const _AddEmployeeSheet({required this.users});

  final List<UserModel> users;

  @override
  State<_AddEmployeeSheet> createState() => _AddEmployeeSheetState();
}

class _AddEmployeeSheetState extends State<_AddEmployeeSheet> {
  UserModel? _selected;
  UserRole _accessLevel = UserRole.employee;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
            SizedBox(height: density.sectionGap),
            Text(
              _selected == null ? 'Add member' : 'Access for this company',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            SizedBox(height: density.titleSubtitleGap),
            Text(
              _selected == null
                  ? 'Choose an account, then set Admin or Employee for this company only.'
                  : 'Account role elsewhere does not carry over — pick access for this company.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            SizedBox(height: density.sectionGap),
            if (_selected == null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.users.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: density.cardGap),
                  itemBuilder: (context, index) {
                    final user = widget.users[index];
                    return Material(
                      color: colors.inputFill,
                      borderRadius: BorderRadius.circular(density.radius),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(density.radius),
                        ),
                        leading: UserAvatar(
                          name: user.username,
                          bytes: null,
                          size: 32,
                        ),
                        title: Text(
                          user.username,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${user.email} · account: ${user.role.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => setState(() {
                          _selected = user;
                          _accessLevel = UserRole.employee;
                        }),
                      ),
                    );
                  },
                ),
              )
            else ...[
              Material(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(density.radius),
                child: ListTile(
                  dense: true,
                  leading: UserAvatar(
                    name: _selected!.username,
                    bytes: null,
                    size: 32,
                  ),
                  title: Text(_selected!.username),
                  subtitle: Text(_selected!.email),
                  trailing: TextButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('Change'),
                  ),
                ),
              ),
              SizedBox(height: density.sectionGap),
              for (final level in [UserRole.employee, UserRole.admin])
                Padding(
                  padding: EdgeInsets.only(bottom: density.cardGap),
                  child: Material(
                    color: _accessLevel == level
                        ? AppColors.primary.withValues(alpha: 0.16)
                        : colors.inputFill,
                    borderRadius: BorderRadius.circular(density.radius),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(density.radius),
                        side: BorderSide(
                          color: _accessLevel == level
                              ? AppColors.primary
                              : colors.border,
                        ),
                      ),
                      title: Text(level.label),
                      subtitle: Text(
                        level == UserRole.admin
                            ? 'Can manage this company'
                            : 'Regular staff in this company',
                      ),
                      trailing: _accessLevel == level
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => setState(() => _accessLevel = level),
                    ),
                  ),
                ),
              SizedBox(height: density.sectionGap),
              PrimaryButton(
                label: 'Add as ${_accessLevel.label}',
                onPressed: () => Navigator.pop(
                  context,
                  _AddMemberPick(
                    user: _selected!,
                    accessLevel: _accessLevel,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaffRoleTaskPick {
  const _StaffRoleTaskPick({
    required this.roleId,
    required this.roleName,
    required this.tasks,
  });

  final String roleId;
  final String roleName;
  final List<String> tasks;
}

class _AssignEmployeeSheet extends StatefulWidget {
  const _AssignEmployeeSheet({
    required this.member,
    required this.roles,
    required this.tasks,
  });

  final StaffAssignment member;
  final List<CompanyJobRole> roles;
  final List<CompanyTask> tasks;

  @override
  State<_AssignEmployeeSheet> createState() => _AssignEmployeeSheetState();
}

class _AssignEmployeeSheetState extends State<_AssignEmployeeSheet> {
  late String _roleId;
  late Set<String> _selectedTasks;

  @override
  void initState() {
    super.initState();
    final existingRole =
        widget.roles.any((role) => role.id == widget.member.roleId)
            ? widget.member.roleId
            : widget.roles.first.id;
    _roleId = existingRole;
    final matching = _tasksForRole(_roleId);
    final allowed = matching.map((task) => task.title).toSet();
    _selectedTasks = widget.member.tasks.where(allowed.contains).toSet();
  }

  List<CompanyTask> _tasksForRole(String roleId) {
    return widget.tasks.where((task) => task.roleId == roleId).toList();
  }

  CompanyJobRole? _roleById(String roleId) {
    for (final role in widget.roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  void _toggleTask(String title) {
    setState(() {
      if (_selectedTasks.contains(title)) {
        _selectedTasks.remove(title);
      } else {
        _selectedTasks.add(title);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final name = widget.member.username.isEmpty
        ? widget.member.email
        : widget.member.username;
    final filtered = _tasksForRole(_roleId);
    final role = _roleById(_roleId);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
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
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            SizedBox(height: CompactPageStyle.of(context).titleSubtitleGap),
            Text(
              'Pick a role, then select tasks.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            DropdownButtonFormField<String>(
              isDense: true,
              initialValue: widget.roles.any((item) => item.id == _roleId)
                  ? _roleId
                  : widget.roles.first.id,
              decoration: InputDecoration(
                labelText: 'Role',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall,
              items: [
                for (final item in widget.roles)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _roleId = value;
                  final allowed =
                      _tasksForRole(value).map((task) => task.title).toSet();
                  _selectedTasks =
                      _selectedTasks.where(allowed.contains).toSet();
                });
              },
            ),
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            if (filtered.isEmpty)
              Container(
                padding: CompactPageStyle.of(context).cardPadding,
                decoration: BoxDecoration(
                  color: colors.inputFill,
                  borderRadius:
                      BorderRadius.circular(CompactPageStyle.of(context).radius),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  'No tasks for this role yet. Add them under Task lists.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(height: CompactPageStyle.of(context).cardGap),
                  itemBuilder: (context, index) {
                    final task = filtered[index];
                    final selected = _selectedTasks.contains(task.title);
                    return Material(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : colors.inputFill,
                      borderRadius:
                          BorderRadius.circular(CompactPageStyle.of(context).radius),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            CompactPageStyle.of(context).radius,
                          ),
                          side: BorderSide(
                            color: selected ? AppColors.primary : colors.border,
                          ),
                        ),
                        leading: Icon(
                          selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: colors.textPrimary,
                          size: 20,
                        ),
                        title: Text(
                          task.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: task.description.isEmpty
                            ? null
                            : Text(
                                task.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                        onTap: () => _toggleTask(task.title),
                      ),
                    );
                  },
                ),
              ),
            if (_selectedTasks.isNotEmpty) ...[
              SizedBox(height: CompactPageStyle.of(context).sectionGap),
              Text(
                '${_selectedTasks.length} selected',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
            SizedBox(height: CompactPageStyle.of(context).sectionGap),
            PrimaryButton(
              label: 'Save assignment',
              onPressed: role == null
                  ? null
                  : () => Navigator.pop(
                        context,
                        _StaffRoleTaskPick(
                          roleId: role.id,
                          roleName: role.name,
                          tasks: _selectedTasks.toList()..sort(),
                        ),
                      ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const _StaffRoleTaskPick(
                        roleId: '',
                        roleName: '',
                        tasks: [],
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
