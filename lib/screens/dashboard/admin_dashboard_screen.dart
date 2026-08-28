import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_job_role.dart';
import '../../models/company_task.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_role.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';
import '../../widgets/primary_button.dart';

enum _LevelFilter { all, admin, employee }

enum _AssignFilter { all, assigned, unassigned }

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _searchController = TextEditingController();
  late final LazyListPager _pager;
  String _search = '';
  _LevelFilter _levelFilter = _LevelFilter.all;
  _AssignFilter _assignFilter = _AssignFilter.all;
  String _roleFilter = 'All';
  String _taskFilter = 'All';

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(onChanged: () {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _pager.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final companies = context.read<CompanyProvider>();
    final company = companies.selectedCompany;
    if (company == null) return;
    _pager.reset();
    await companies.loadCompanyUsers(company.id);
    if (mounted) setState(() {});
  }

  UserRole? _levelRole(_LevelFilter filter) {
    switch (filter) {
      case _LevelFilter.all:
        return null;
      case _LevelFilter.admin:
        return UserRole.admin;
      case _LevelFilter.employee:
        return UserRole.employee;
    }
  }

  List<StaffAssignment> _companyMembers(CompanyProvider companies) {
    final members = [...companies.staff]
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
    return members.where((member) {
      final role = companies.memberAccessRole(member);
      return role == UserRole.admin || role == UserRole.employee;
    }).toList();
  }

  List<StaffAssignment> _filteredMembers(CompanyProvider companies) {
    final level = _levelRole(_levelFilter);
    final query = _search.trim().toLowerCase();
    final roleFilter = _effectiveRoleFilter(companies);
    final taskFilter = _effectiveTaskFilter(companies);
    final filteringAssignments = _assignFilter != _AssignFilter.all ||
        roleFilter != 'All' ||
        taskFilter != 'All';

    return _companyMembers(companies).where((member) {
      final role = companies.memberAccessRole(member);
      if (level != null && role != level) return false;

      final isEmployee = role == UserRole.employee;
      // Role/task assignment applies to employees only.
      if (!isEmployee && filteringAssignments) return false;

      if (isEmployee) {
        final assigned = member.jobRole.isNotEmpty || member.tasks.isNotEmpty;
        if (_assignFilter == _AssignFilter.assigned && !assigned) return false;
        if (_assignFilter == _AssignFilter.unassigned && assigned) {
          return false;
        }

        if (roleFilter != 'All') {
          final matchRole = member.jobRole == roleFilter ||
              companies.roleById(member.roleId)?.name == roleFilter;
          if (!matchRole) return false;
        }

        if (taskFilter != 'All' &&
            !member.tasks.any((task) => task == taskFilter)) {
          return false;
        }
      }

      if (query.isEmpty) return true;
      final haystack = [
        member.username,
        member.email,
        if (isEmployee) member.jobRole,
        if (isEmployee) ...member.tasks,
        role.label,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  String _effectiveRoleFilter(CompanyProvider companies) {
    final options = _roleFilterOptions(companies);
    return options.contains(_roleFilter) ? _roleFilter : 'All';
  }

  String _effectiveTaskFilter(CompanyProvider companies) {
    final options = _taskFilterOptions(companies);
    return options.contains(_taskFilter) ? _taskFilter : 'All';
  }

  List<String> _roleFilterOptions(CompanyProvider companies) {
    final names = <String>{
      for (final role in companies.roles)
        if (role.name.trim().isNotEmpty) role.name.trim(),
      for (final member in _companyMembers(companies))
        if (companies.memberAccessRole(member) == UserRole.employee &&
            member.jobRole.trim().isNotEmpty)
          member.jobRole.trim(),
    };

    // Task → Role: only roles that own the selected task (or have staff with it).
    if (_taskFilter != 'All') {
      final linked = <String>{};
      for (final task in companies.tasks) {
        if (task.title != _taskFilter) continue;
        final byId = companies.roleById(task.roleId)?.name.trim() ?? '';
        if (byId.isNotEmpty) linked.add(byId);
        if (task.roleName.trim().isNotEmpty) linked.add(task.roleName.trim());
      }
      for (final member in _companyMembers(companies)) {
        if (companies.memberAccessRole(member) != UserRole.employee) {
          continue;
        }
        if (!member.tasks.contains(_taskFilter)) continue;
        if (member.jobRole.trim().isNotEmpty) linked.add(member.jobRole.trim());
        final byId = companies.roleById(member.roleId)?.name.trim() ?? '';
        if (byId.isNotEmpty) linked.add(byId);
      }
      names.retainWhere(linked.contains);
    }

    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...sorted];
  }

  List<String> _taskFilterOptions(CompanyProvider companies) {
    final titles = <String>{
      for (final task in companies.tasks)
        if (task.title.trim().isNotEmpty) task.title.trim(),
      for (final member in _companyMembers(companies))
        if (companies.memberAccessRole(member) == UserRole.employee)
          ...member.tasks.where((task) => task.trim().isNotEmpty),
    };

    // Role → Task: only tasks that belong to the selected company role.
    if (_roleFilter != 'All') {
      final roleIds = <String>{
        for (final role in companies.roles)
          if (role.name == _roleFilter) role.id,
      };
      final linked = <String>{};
      for (final task in companies.tasks) {
        final matchesRole = task.roleName == _roleFilter ||
            (task.roleId.isNotEmpty && roleIds.contains(task.roleId));
        if (matchesRole && task.title.trim().isNotEmpty) {
          linked.add(task.title.trim());
        }
      }
      for (final member in _companyMembers(companies)) {
        if (companies.memberAccessRole(member) != UserRole.employee) {
          continue;
        }
        final memberRole = member.jobRole == _roleFilter ||
            companies.roleById(member.roleId)?.name == _roleFilter;
        if (!memberRole) continue;
        linked.addAll(member.tasks.where((task) => task.trim().isNotEmpty));
      }
      titles.retainWhere(linked.contains);
    }

    final sorted = titles.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['All', ...sorted];
  }

  Future<void> _assign(StaffAssignment member) async {
    final companies = context.read<CompanyProvider>();
    final company = companies.selectedCompany;
    if (company == null) return;

    final level = companies.memberAccessRole(member);
    if (level != UserRole.employee) {
      SnackBarHelper.showInfo(
        context,
        'Only employees can be assigned company roles and tasks.',
      );
      return;
    }

    if (companies.roles.isEmpty) {
      SnackBarHelper.showInfo(
        context,
        'No company roles yet. Ask Super Admin to add roles and tasks first.',
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
            : '${member.username} was assigned ${selected.roleName}'
                '${selected.tasks.isEmpty ? '' : ' • ${selected.tasks.join(', ')}'}.',
      );
    } else {
      SnackBarHelper.showError(
        context,
        companies.errorMessage ?? 'Could not save assignment.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final company = companies.selectedCompany;
    final density = CompactPageStyle.of(context);
    final allMembers = _companyMembers(companies);
    final roleOptions = _roleFilterOptions(companies);
    final taskOptions = _taskFilterOptions(companies);
    final roleFilter = _effectiveRoleFilter(companies);
    final taskFilter = _effectiveTaskFilter(companies);
    if (roleFilter != _roleFilter || taskFilter != _taskFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _roleFilter = roleFilter;
          _taskFilter = taskFilter;
        });
      });
    }
    final members = _filteredMembers(companies);
    final visible = _pager.takeVisible(members);
    final hasMore = _pager.hasMore(members.length);
    final assignedCount = allMembers.where((m) {
      return companies.memberAccessRole(m) == UserRole.employee &&
          (m.jobRole.isNotEmpty || m.tasks.isNotEmpty);
    }).length;
    final adminCount = allMembers
        .where((m) => companies.memberAccessRole(m) == UserRole.admin)
        .length;
    final employeeCount = allMembers
        .where((m) => companies.memberAccessRole(m) == UserRole.employee)
        .length;

    return DashboardScaffold(
      title: 'Staff',
      currentRoute: AppRoutes.adminDashboard,
      child: ListView(
        controller: _pager.scrollController,
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: company?.name ?? 'Staff',
            subtitle:
                'Filter staff and assign company roles and tasks to employees only. Admins are not given task assignments.',
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: companies.isLoading ? null : _reload,
              icon: Icon(
                Icons.refresh_rounded,
                size: density.compact ? 20 : 24,
              ),
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: density.sectionGap),
          if (company == null)
            const _MessageCard(
              icon: Icons.business_outlined,
              message: 'Select a company to manage staff.',
            )
          else ...[
            CompactSummaryStrip(
              items: [
                CompactSummaryItem(
                  label: 'Members',
                  value: '${allMembers.length}',
                ),
                CompactSummaryItem(label: 'Admins', value: '$adminCount'),
                CompactSummaryItem(
                  label: 'Employees',
                  value: '$employeeCount',
                ),
                CompactSummaryItem(
                  label: 'Assigned',
                  value: '$assignedCount',
                ),
              ],
            ),
            SizedBox(height: density.sectionGap),
            CompactSearchField(
              controller: _searchController,
              onChanged: (value) => setState(() {
                _search = value;
                _pager.reset();
              }),
              hintText: 'Search name, email, role, or task',
            ),
            SizedBox(height: density.cardGap),
            Row(
              children: [
                Expanded(
                  child: CompactFilterDropdown(
                    value: switch (_levelFilter) {
                      _LevelFilter.all => 'All',
                      _LevelFilter.admin => 'Admin',
                      _LevelFilter.employee => 'Employee',
                    },
                    items: const ['All', 'Admin', 'Employee'],
                    hint: 'Level',
                    onChanged: (value) {
                      setState(() {
                        _levelFilter = switch (value) {
                          'Admin' => _LevelFilter.admin,
                          'Employee' => _LevelFilter.employee,
                          _ => _LevelFilter.all,
                        };
                        _pager.reset();
                      });
                    },
                  ),
                ),
                SizedBox(width: density.cardGap),
                Expanded(
                  child: CompactFilterDropdown(
                    value: switch (_assignFilter) {
                      _AssignFilter.all => 'All',
                      _AssignFilter.assigned => 'Assigned',
                      _AssignFilter.unassigned => 'Unassigned',
                    },
                    items: const ['All', 'Assigned', 'Unassigned'],
                    hint: 'Status',
                    onChanged: (value) {
                      setState(() {
                        _assignFilter = switch (value) {
                          'Assigned' => _AssignFilter.assigned,
                          'Unassigned' => _AssignFilter.unassigned,
                          _ => _AssignFilter.all,
                        };
                        _pager.reset();
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: density.cardGap),
            Row(
              children: [
                Expanded(
                  child: CompactFilterDropdown(
                    value: roleFilter,
                    items: roleOptions,
                    hint: 'Role',
                    onChanged: (value) {
                      setState(() {
                        _roleFilter = value;
                        final nextTasks = _taskFilterOptions(
                          context.read<CompanyProvider>(),
                        );
                        if (!nextTasks.contains(_taskFilter)) {
                          _taskFilter = 'All';
                        }
                        _pager.reset();
                      });
                    },
                  ),
                ),
                SizedBox(width: density.cardGap),
                Expanded(
                  child: CompactFilterDropdown(
                    value: taskFilter,
                    items: taskOptions,
                    hint: 'Task',
                    onChanged: (value) {
                      setState(() {
                        _taskFilter = value;
                        final nextRoles = _roleFilterOptions(
                          context.read<CompanyProvider>(),
                        );
                        if (!nextRoles.contains(_roleFilter)) {
                          _roleFilter = 'All';
                        }
                        _pager.reset();
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: density.sectionGap),
            if (companies.isLoading)
              const AppLoadingView(
                title: 'Loading staff',
                message: 'Fetching members, roles, and tasks…',
              )
            else if (allMembers.isEmpty)
              const _MessageCard(
                icon: Icons.groups_outlined,
                message:
                    'No admins or employees in this company yet. Ask Super Admin to add members.',
              )
            else if (members.isEmpty)
              const _MessageCard(
                icon: Icons.filter_alt_off_outlined,
                message: 'No staff match the current filters.',
              )
            else ...[
              for (final member in visible) ...[
                _StaffMemberCard(
                  member: member,
                  accessRole: companies.memberAccessRole(member),
                  onAssign: () => _assign(member),
                ),
                SizedBox(height: density.cardGap),
              ],
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

class _StaffMemberCard extends StatelessWidget {
  const _StaffMemberCard({
    required this.member,
    required this.accessRole,
    required this.onAssign,
  });

  final StaffAssignment member;
  final UserRole accessRole;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final density = CompactPageStyle.of(context);
    final level = accessRole.label;
    final isEmployee = accessRole == UserRole.employee;
    final assigned = isEmployee &&
        (member.jobRole.isNotEmpty || member.tasks.isNotEmpty);

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(density.radius),
      child: InkWell(
        onTap: isEmployee ? onAssign : null,
        borderRadius: BorderRadius.circular(density.radius),
        child: Ink(
          padding: density.cardPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(density.radius),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            member.username.isEmpty
                                ? member.email
                                : member.username,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontSize: density.cardTitleSize,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: density.compact ? 8 : 10,
                            vertical: density.compact ? 3 : 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.chip,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            level,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontSize: density.chipLabelSize,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (member.email.isNotEmpty) ...[
                      SizedBox(height: density.compact ? 2 : 4),
                      Text(
                        member.email,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: density.captionSize,
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                    SizedBox(height: density.titleSubtitleGap),
                    Text(
                      isEmployee
                          ? (assigned
                              ? (member.jobRole.isEmpty
                                  ? 'No role'
                                  : member.jobRole)
                              : 'Not assigned yet')
                          : 'Admins are not assigned tasks',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: density.bodySize,
                            fontWeight: FontWeight.w700,
                            color: assigned
                                ? AppColors.primaryDark
                                : colors.textSecondary,
                          ),
                    ),
                    if (isEmployee && member.tasks.isNotEmpty) ...[
                      SizedBox(height: density.compact ? 4 : 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final task in member.tasks.take(4))
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: density.compact ? 8 : 10,
                                vertical: density.compact ? 3 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                task,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: density.chipLabelSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          if (member.tasks.length > 4)
                            Text(
                              '+${member.tasks.length - 4}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontSize: density.chipLabelSize,
                                    color: colors.textSecondary,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isEmployee)
                IconButton(
                  tooltip: 'Assign role & tasks',
                  onPressed: onAssign,
                  icon: const Icon(Icons.edit_outlined),
                  color: AppColors.primaryDark,
                ),
            ],
          ),
        ),
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
    final density = CompactPageStyle.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: density.compact ? 22 : 26,
        horizontal: density.compact ? 12 : 16,
      ),
      decoration: compactCardDecoration(context),
      child: Column(
        children: [
          Icon(
            icon,
            size: density.compact ? 26 : 30,
            color: colors.textSecondary,
          ),
          SizedBox(height: density.cardGap + 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: density.bodySize,
                  color: colors.textSecondary,
                ),
          ),
        ],
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
    final allowed = _tasksForRole(_roleId).map((task) => task.title).toSet();
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
    final density = CompactPageStyle.of(context);
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
            SizedBox(height: density.sectionGap),
            Text(
              name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: density.pageTitleSize,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            SizedBox(height: density.titleSubtitleGap),
            Text(
              'Pick a role, then select the tasks that belong to it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: density.bodySize,
                    color: colors.textSecondary,
                  ),
            ),
            SizedBox(height: density.sectionGap),
            DropdownButtonFormField<String>(
              isDense: density.compact,
              initialValue: widget.roles.any((item) => item.id == _roleId)
                  ? _roleId
                  : widget.roles.first.id,
              decoration: InputDecoration(
                labelText: 'Role',
                isDense: density.compact,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: density.compact ? 10 : 12,
                  vertical: density.compact ? 8 : 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(density.radius),
                ),
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: density.bodySize,
                  ),
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
            SizedBox(height: density.sectionGap),
            if (filtered.isEmpty)
              Container(
                padding: density.cardPadding,
                decoration: BoxDecoration(
                  color: colors.inputFill,
                  borderRadius: BorderRadius.circular(density.radius),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  'No tasks for this role yet. Ask Super Admin to add them under Task lists.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: density.bodySize,
                      ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      SizedBox(height: density.cardGap),
                  itemBuilder: (context, index) {
                    final task = filtered[index];
                    final selected = _selectedTasks.contains(task.title);
                    return Material(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : colors.inputFill,
                      borderRadius: BorderRadius.circular(density.radius),
                      child: ListTile(
                        dense: density.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(density.radius),
                          side: BorderSide(
                            color:
                                selected ? AppColors.primary : colors.border,
                          ),
                        ),
                        leading: Icon(
                          selected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          color: colors.textPrimary,
                          size: density.compact ? 20 : 22,
                        ),
                        title: Text(
                          task.title,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontSize: density.cardTitleSize,
                                  ),
                        ),
                        subtitle: task.description.isEmpty
                            ? null
                            : Text(
                                task.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontSize: density.captionSize,
                                    ),
                              ),
                        onTap: () => _toggleTask(task.title),
                      ),
                    );
                  },
                ),
              ),
            if (_selectedTasks.isNotEmpty) ...[
              SizedBox(height: density.sectionGap),
              Text(
                '${_selectedTasks.length} task${_selectedTasks.length == 1 ? '' : 's'} selected',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: density.captionSize,
                      color: colors.textSecondary,
                    ),
              ),
            ],
            SizedBox(height: density.sectionGap),
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
