import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/company_id.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/snackbar_helper.dart';
import '../../models/company_model.dart';
import '../../models/staff_assignment.dart';
import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../widgets/app_loading_card.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/lazy_list_pager.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/user_avatar.dart';

class SuperAdminUsersScreen extends StatefulWidget {
  const SuperAdminUsersScreen({super.key});

  @override
  State<SuperAdminUsersScreen> createState() => _SuperAdminUsersScreenState();
}

class _SuperAdminUsersScreenState extends State<SuperAdminUsersScreen> {
  final _search = TextEditingController();
  late final LazyListPager _pager;
  /// Selected company key — matches [CompanyModel.id] (same as other list screens).
  String? _companyFilter;
  UserRole? _levelFilter;
  List<StaffAssignment> _companyStaff = [];
  bool _loadingCompanyStaff = false;

  @override
  void initState() {
    super.initState();
    _pager = LazyListPager(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CompanyProvider>().loadUsersPage();
      if (!mounted || _companyFilter == null) return;
      await _reloadStaffForFilter();
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    _search.dispose();
    super.dispose();
  }

  bool _isSuperAdmin(UserModel user) {
    return RolePolicy.isSuperAdminEmail(user.email) ||
        user.role == UserRole.superAdmin;
  }

  List<UserModel> _superAdmins(List<UserModel> users) {
    return users.where(_isSuperAdmin).toList()
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
  }

  String _companyKey(String value) {
    final normalized = CompanyId.normalize(value);
    if (normalized.isNotEmpty) return normalized;
    return value.trim().toLowerCase();
  }

  bool _staffMatchesUser(StaffAssignment assignment, UserModel user) {
    final userId = assignment.userId.trim();
    if (userId.isNotEmpty && userId == user.id) return true;
    final email = assignment.email.trim().toLowerCase();
    if (email.isNotEmpty && email == user.email.trim().toLowerCase()) {
      return true;
    }
    return false;
  }

  CompanyModel? _findCompany(CompanyProvider companies, String key) {
    for (final company in companies.companies) {
      if (company.id == key ||
          company.firestoreId == key ||
          _companyKey(company.id) == _companyKey(key) ||
          _companyKey(company.firestoreId) == _companyKey(key)) {
        return company;
      }
    }
    return null;
  }

  CompanyModel? _selectedCompany(CompanyProvider companies) {
    final filter = _companyFilter;
    if (filter == null) return null;
    return _findCompany(companies, filter);
  }

  List<StaffAssignment> _staffForSelectedCompany(CompanyProvider companies) {
    final filter = _companyFilter;
    if (filter == null) return [];
    if (_companyStaff.isNotEmpty) return _companyStaff;

    final selected = _selectedCompany(companies);
    if (selected != null) {
      final cached = companies.cachedStaffForCompany(selected.firestoreId);
      if (cached.isNotEmpty) return cached;
    }

    final cachedByFilter = companies.cachedStaffForCompany(filter);
    if (cachedByFilter.isNotEmpty) return cachedByFilter;

    return companies.allStaffMemberships
        .where(
          (item) =>
              item.company.id == filter ||
              item.firestoreCompanyId == filter ||
              _companyKey(item.company.id) == _companyKey(filter) ||
              _companyKey(item.firestoreCompanyId) == _companyKey(filter) ||
              (selected != null &&
                  (item.firestoreCompanyId == selected.firestoreId ||
                      _companyKey(item.company.id) ==
                          _companyKey(selected.id) ||
                      item.company.name.trim().toLowerCase() ==
                          selected.name.trim().toLowerCase())),
        )
        .map((item) => item.assignment)
        .toList();
  }

  Future<void> _reloadStaffForFilter() async {
    final filter = _companyFilter;
    if (filter == null) return;

    setState(() => _loadingCompanyStaff = true);
    final provider = context.read<CompanyProvider>();
    final company = _findCompany(provider, filter);
    final loadKey = company?.id ?? filter;

    try {
      final loaded =
          await provider.fetchStaffForCompany(loadKey);
      if (!mounted || _companyFilter != filter) return;
      setState(() {
        _companyStaff = loaded;
        _loadingCompanyStaff = false;
      });
    } catch (_) {
      if (!mounted || _companyFilter != filter) return;
      setState(() => _loadingCompanyStaff = false);
    }
  }

  Future<void> _onCompanyFilterSelected(String? companyId) async {
    setState(() {
      _companyFilter = companyId;
      _companyStaff = [];
      _loadingCompanyStaff = companyId != null;
      _pager.reset();
    });
    if (companyId == null) return;
    await _reloadStaffForFilter();
  }

  UserModel? _resolveUser(
    CompanyProvider companies,
    StaffAssignment assignment,
  ) {
    final userId = assignment.userId.trim();
    final email = assignment.email.trim().toLowerCase();

    for (final user in companies.users) {
      if (userId.isNotEmpty && user.id == userId) return user;
      if (email.isNotEmpty &&
          user.email.trim().toLowerCase() == email) {
        return user;
      }
    }

    if (userId.isEmpty && email.isEmpty) return null;

    return UserModel(
      id: userId.isNotEmpty ? userId : email,
      username:
          assignment.username.isNotEmpty ? assignment.username : email,
      email: assignment.email,
      phoneNumber: '',
      role: UserRole.user,
    );
  }

  bool _matchesLevel(UserModel user) {
    return _levelFilter == null || user.role == _levelFilter;
  }

  bool _matchesSearch(UserModel user, String query) {
    if (query.isEmpty) return true;
    return user.username.toLowerCase().contains(query) ||
        user.email.toLowerCase().contains(query) ||
        user.role.label.toLowerCase().contains(query);
  }

  List<UserModel> _filteredUsers(CompanyProvider companies) {
    final query = _search.text.trim().toLowerCase();
    final results = <UserModel>[];
    final seen = <String>{};

    void addUser(UserModel user) {
      if (_isSuperAdmin(user)) return;
      final key = user.email.trim().toLowerCase().isNotEmpty
          ? user.email.trim().toLowerCase()
          : user.id;
      if (!seen.add(key)) return;
      if (!_matchesLevel(user)) return;
      if (!_matchesSearch(user, query)) return;
      results.add(user);
    }

    if (_companyFilter != null) {
      final assignments = _staffForSelectedCompany(companies);
      for (final assignment in assignments) {
        final user = _resolveUser(companies, assignment);
        if (user != null) addUser(user);
      }
      for (final user in companies.users) {
        if (assignments.any((assignment) => _staffMatchesUser(assignment, user))) {
          addUser(user);
        }
      }
    } else {
      for (final user in companies.users) {
        addUser(user);
      }
      for (final item in companies.allStaffMemberships) {
        final user = _resolveUser(companies, item.assignment);
        if (user != null) addUser(user);
      }
    }

    results.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );
    return results;
  }

  int _regularUserTotal(CompanyProvider companies) {
    if (_companyFilter != null) {
      final assignments = _staffForSelectedCompany(companies);
      final seen = <String>{};
      var count = 0;

      void countUser(UserModel user) {
        if (_isSuperAdmin(user)) return;
        final key = user.email.trim().toLowerCase().isNotEmpty
            ? user.email.trim().toLowerCase()
            : user.id;
        if (seen.add(key)) count++;
      }

      for (final assignment in assignments) {
        final user = _resolveUser(companies, assignment);
        if (user != null) countUser(user);
      }
      for (final user in companies.users) {
        if (assignments.any((assignment) => _staffMatchesUser(assignment, user))) {
          countUser(user);
        }
      }
      return count;
    }
    final seen = <String>{};
    var count = 0;
    for (final user in companies.users) {
      if (_isSuperAdmin(user)) continue;
      final key = user.email.trim().toLowerCase().isNotEmpty
          ? user.email.trim().toLowerCase()
          : user.id;
      if (seen.add(key)) count++;
    }
    for (final item in companies.allStaffMemberships) {
      final user = _resolveUser(companies, item.assignment);
      if (user == null || _isSuperAdmin(user)) continue;
      final key = user.email.trim().toLowerCase().isNotEmpty
          ? user.email.trim().toLowerCase()
          : user.id;
      if (seen.add(key)) count++;
    }
    return count;
  }

  void _clearFilters() {
    setState(() {
      _companyFilter = null;
      _companyStaff = [];
      _loadingCompanyStaff = false;
      _levelFilter = null;
      _search.clear();
      _pager.reset();
    });
  }

  Set<String> _companyIdsForUser(CompanyProvider companies, String userId) {
    final ids = <String>{};
    for (final item in companies.allStaffMemberships) {
      if (item.assignment.userId == userId) {
        ids.add(item.company.id);
      }
    }
    return ids;
  }

  Future<List<String>?> _pickCompaniesForRole({
    required UserModel user,
    required UserRole role,
    required List<CompanyModel> companies,
    required Uint8List? Function(String companyId) logoFor,
    required Set<String> initialSelected,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CompanyMultiSelectSheet(
        user: user,
        role: role,
        companies: companies,
        logoFor: logoFor,
        initialSelected: initialSelected,
      ),
    );
  }

  Future<void> _changeRole(UserModel user) async {
    if (RolePolicy.isSuperAdminEmail(user.email)) return;

    final selected = await showDialog<UserRole>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Set user level'),
          children: [
            for (final role in [UserRole.user, UserRole.employee, UserRole.admin])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, role),
                child: Text(
                  role.label + (role == user.role ? ' (current)' : ''),
                ),
              ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    if (selected == user.role &&
        !RolePolicy.hasCompanyAccess(selected)) {
      return;
    }

    final provider = context.read<CompanyProvider>();
    List<String>? companyIds;

    if (RolePolicy.hasCompanyAccess(selected)) {
      if (provider.companies.isEmpty) {
        SnackBarHelper.showInfo(
          context,
          'Create a company first, then assign this user.',
        );
        return;
      }

      final initial = _companyIdsForUser(provider, user.id);
      companyIds = await _pickCompaniesForRole(
        user: user,
        role: selected,
        companies: provider.companies,
        logoFor: provider.logoFor,
        initialSelected: initial,
      );
      if (!mounted || companyIds == null) return;
      if (companyIds.isEmpty) {
        SnackBarHelper.showInfo(context, 'Select at least one company.');
        return;
      }
    }

    final ok = await provider.updateUserRole(
      userId: user.id,
      role: selected,
      previousRole: user.role,
    );
    if (!mounted) return;
    if (!ok) {
      SnackBarHelper.showError(
        context,
        provider.errorMessage ?? 'Could not update user level.',
      );
      return;
    }

    if (RolePolicy.hasCompanyAccess(selected) && companyIds != null) {
      UserModel updated = user.copyWith(role: selected);
      for (final item in provider.users) {
        if (item.id == user.id) {
          updated = item;
          break;
        }
      }

      final synced = await provider.syncUserCompanyMemberships(
        user: updated,
        companyIds: companyIds,
      );
      if (!mounted) return;
      if (!synced) {
        SnackBarHelper.showError(
          context,
          provider.errorMessage ?? 'Level updated but company assignment failed.',
        );
        return;
      }

      if (_companyFilter != null) {
        await _reloadStaffForFilter();
      }
    }

    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    final companies = context.read<CompanyProvider>();
    if (auth.user?.id == user.id) {
      await auth.reloadUser();
      if (RolePolicy.clearsCompanyMembership(
        previous: user.role,
        next: selected,
      )) {
        companies.clearSelection();
      }
    }

    if (!mounted) return;

    String message;
    if (RolePolicy.clearsCompanyMembership(previous: user.role, next: selected)) {
      message =
          '${selected.label} level applied. Company tasks and assignments were removed.';
    } else if (RolePolicy.hasCompanyAccess(selected) && companyIds != null) {
      final count = companyIds.length;
      message =
          '${selected.label} level applied for $count ${count == 1 ? 'company' : 'companies'}.';
    } else if (selected == UserRole.admin) {
      message = 'Admin level applied. This account now has admin access.';
    } else {
      message = 'User level updated to ${selected.label}.';
    }
    SnackBarHelper.showSuccess(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<CompanyProvider>();
    final superAdmins = _superAdmins(companies.users);
    final filteredUsers = _filteredUsers(companies);
    final visible = _pager.takeVisible(filteredUsers);
    final hasMore = _pager.hasMore(filteredUsers.length);
    final regularTotal = _regularUserTotal(companies);
    final hasSearch = _search.text.trim().isNotEmpty;
    final hasFilters =
        _companyFilter != null || _levelFilter != null || hasSearch;
    final companyFilterName = _selectedCompany(companies)?.name;
    final levelFilterName = _levelFilter?.label;

    return DashboardScaffold(
      title: 'User levels',
      currentRoute: AppRoutes.superAdminUsers,
      child: CustomScrollView(
        controller: _pager.scrollController,
        slivers: [
          SliverPadding(
            padding: CompactPageStyle.of(context).pagePaddingTopOnly,
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CompactPageHeader(
                    title: 'User levels',
                    subtitle:
                        'Set account levels and filter by company or account level.',
                  ),
                  if (superAdmins.isNotEmpty) ...[
                    SizedBox(height: CompactPageStyle.of(context).sectionGap),
                    _SectionLabel(title: 'Super Admin'),
                    SizedBox(height: CompactPageStyle.of(context).cardGap),
                    ...superAdmins.map(
                      (user) => _UserLevelTile(
                        user: user,
                        subtitle: '${user.email} • ${user.role.label}',
                        locked: true,
                        onTap: null,
                      ),
                    ),
                  ],
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                  _SummaryCard(
                    total: regularTotal,
                    showing: filteredUsers.length,
                    companyFilter: companyFilterName,
                    levelFilter: levelFilterName,
                    hasFilters: hasFilters,
                  ),
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: companies.companies.isEmpty
                            ? _FilterDropdownShell(
                                label: 'Company',
                                icon: Icons.business_rounded,
                                value: 'No companies yet',
                                enabled: false,
                                muted: true,
                                onTap: () {},
                              )
                            : _CompanyFilterDropdown(
                                companies: companies.companies,
                                selectedId: _companyFilter,
                                logoFor: companies.logoFor,
                                onSelected: _onCompanyFilterSelected,
                              ),
                      ),
                      SizedBox(width: CompactPageStyle.of(context).cardGap),
                      Expanded(
                        child: _AccountLevelFilterDropdown(
                          selected: _levelFilter,
                          onSelected: (level) => setState(() {
                            _levelFilter = level;
                            _pager.reset();
                          }),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: CompactPageStyle.of(context).cardGap),
                  CompactSearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {
                      _pager.reset();
                    }),
                    hintText: 'Search name, email, or level',
                  ),
                  SizedBox(height: CompactPageStyle.of(context).sectionGap),
                  _SectionLabel(
                    title: hasFilters ? 'Filtered users' : 'All users',
                  ),
                  SizedBox(height: CompactPageStyle.of(context).cardGap),
                ],
              ),
            ),
          ),
          if (companies.isLoading)
            const SliverPadding(
              padding: EdgeInsets.only(top: 28, bottom: 20),
              sliver: SliverToBoxAdapter(
                child: AppLoadingView(
                  title: 'Loading users',
                  message: 'Fetching all accounts…',
                ),
              ),
            )
          else if (companies.errorMessage != null && companies.users.isEmpty)
            SliverPadding(
              padding: CompactPageStyle.of(context).listPadding,
              sliver: SliverToBoxAdapter(
                child: Text(companies.errorMessage!),
              ),
            )
          else if (regularTotal == 0 && superAdmins.isEmpty)
            SliverPadding(
              padding: CompactPageStyle.of(context).listPadding,
              sliver: SliverToBoxAdapter(
                child: Text('No users found.'),
              ),
            )
          else if (_loadingCompanyStaff)
            SliverPadding(
              padding: CompactPageStyle.of(context).listPadding,
              sliver: const SliverToBoxAdapter(
                child: AppLoadingView(
                  title: 'Loading company staff',
                  message: 'Filtering users for this company…',
                ),
              ),
            )
          else if (filteredUsers.isEmpty)
            SliverPadding(
              padding: CompactPageStyle.of(context).listPadding,
              sliver: SliverToBoxAdapter(
                child: _EmptyState(
                  message:
                      'No users match these filters. Try another company, level, or search.',
                  actionLabel: 'Clear filters',
                  onAction: _clearFilters,
                ),
              ),
            )
          else
            SliverPadding(
              padding: CompactPageStyle.of(context).listPadding,
              sliver: SliverList.builder(
                itemCount: visible.length + (hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= visible.length) {
                    return LazyListFooter(
                      hasMore: hasMore,
                      remaining: filteredUsers.length - visible.length,
                      loadingMore: _pager.loadingMore,
                      onLoadMore: () => _pager.loadMore(filteredUsers.length),
                    );
                  }
                  final user = visible[index];
                  return _UserLevelTile(
                    user: user,
                    subtitle: '${user.email} • ${user.role.label}',
                    locked: false,
                    onTap: () => _changeRole(user),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.of(context).textSecondary,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.showing,
    required this.companyFilter,
    required this.levelFilter,
    required this.hasFilters,
  });

  final int total;
  final int showing;
  final String? companyFilter;
  final String? levelFilter;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final countLabel =
        hasFilters ? 'Showing $showing of $total' : '$total users';
    final filterParts = [
      ?companyFilter,
      ?levelFilter,
    ];

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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
            ),
            child: const Icon(
              Icons.manage_accounts_outlined,
              color: AppColors.primaryDark,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countLabel,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (filterParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    filterParts.join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserLevelTile extends StatelessWidget {
  const _UserLevelTile({
    required this.user,
    required this.subtitle,
    required this.locked,
    required this.onTap,
  });

  final UserModel user;
  final String subtitle;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: CompactPageStyle.of(context).cardGap),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
          onTap: onTap,
          child: Padding(
            padding: CompactPageStyle.of(context).cardPadding,
            child: Row(
              children: [
                UserAvatar(name: user.username, bytes: null, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  locked
                      ? Icons.verified_rounded
                      : Icons.manage_accounts_outlined,
                  color: locked ? AppColors.primary : colors.textSecondary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: CompactPageStyle.of(context).cardPadding,
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_rounded,
              size: 28, color: colors.textSecondary),
          SizedBox(height: CompactPageStyle.of(context).cardGap),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(height: CompactPageStyle.of(context).cardGap),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _FilterDropdownShell extends StatelessWidget {
  const _FilterDropdownShell({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.muted = false,
    this.leading,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final bool enabled;
  final bool muted;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: colors.inputFill,
      borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
        onTap: enabled ? onTap : null,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            filled: true,
            fillColor: colors.inputFill,
            contentPadding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              borderSide: BorderSide(color: colors.border),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
              borderSide: BorderSide(color: colors.border),
            ),
            suffixIcon: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: enabled ? colors.textSecondary : colors.textHint,
            ),
          ),
          child: Row(
            children: [
              if (leading != null)
                leading!
              else
                Icon(icon, size: 18, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: muted || !enabled
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

class _CompanyFilterDropdown extends StatelessWidget {
  const _CompanyFilterDropdown({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
    required this.onSelected,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;
  final ValueChanged<String?> onSelected;

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _CompanyFilterPickerSheet(
        companies: companies,
        selectedId: selectedId,
        logoFor: logoFor,
      ),
    );
    if (picked == null) return;
    onSelected(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    CompanyModel? selected;
    for (final company in companies) {
      if (company.firestoreId == selectedId || company.id == selectedId) {
        selected = company;
        break;
      }
    }

    return _FilterDropdownShell(
      label: 'Company',
      icon: Icons.business_rounded,
      muted: selected == null,
      leading: selected == null
          ? null
          : UserAvatar(
              bytes: logoFor(selected.id),
              name: selected.name,
              size: 24,
            ),
      value: selected == null
          ? 'All companies'
          : '${selected.name}  •  ${selected.companyId}',
      onTap: () => _openPicker(context),
    );
  }
}

class _CompanyFilterPickerSheet extends StatefulWidget {
  const _CompanyFilterPickerSheet({
    required this.companies,
    required this.selectedId,
    required this.logoFor,
  });

  final List<CompanyModel> companies;
  final String? selectedId;
  final Uint8List? Function(String companyId) logoFor;

  @override
  State<_CompanyFilterPickerSheet> createState() =>
      _CompanyFilterPickerSheetState();
}

class _CompanyFilterPickerSheetState extends State<_CompanyFilterPickerSheet> {
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
          company.id.toLowerCase().contains(needle) ||
          company.firestoreId.toLowerCase().contains(needle);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;
    final allSelected = widget.selectedId == null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
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
            const SizedBox(height: 14),
            Text(
              'Filter by company',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Search by company name or ID.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search companies...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
              ),
            ),
            const SizedBox(height: 10),
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
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length + 1,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _PickerTile(
                            selected: allSelected,
                            leading: Icon(
                              Icons.business_rounded,
                              color: colors.textSecondary,
                              size: 22,
                            ),
                            title: 'All companies',
                            onTap: () => Navigator.pop(context, ''),
                          );
                        }
                        final company = items[index - 1];
                        final selected = company.firestoreId == widget.selectedId ||
                            company.id == widget.selectedId;
                        return _PickerTile(
                          selected: selected,
                          leading: UserAvatar(
                            bytes: widget.logoFor(company.id),
                            name: company.name,
                            size: 32,
                          ),
                          title: company.name,
                          subtitle: 'ID: ${company.companyId}',
                          onTap: () => Navigator.pop(context, company.id),
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

class _AccountLevelFilterDropdown extends StatelessWidget {
  const _AccountLevelFilterDropdown({
    required this.selected,
    required this.onSelected,
  });

  final UserRole? selected;
  final ValueChanged<UserRole?> onSelected;

  static const _levels = [
    UserRole.user,
    UserRole.employee,
    UserRole.admin,
  ];

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.of(context).background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _AccountLevelFilterPickerSheet(selected: selected),
    );
    if (picked == null) return;
    onSelected(picked.isEmpty ? null : UserRole.fromStorage(picked));
  }

  static IconData iconFor(UserRole? level) {
    switch (level) {
      case UserRole.user:
        return Icons.person_outline_rounded;
      case UserRole.employee:
        return Icons.badge_outlined;
      case UserRole.admin:
        return Icons.admin_panel_settings_outlined;
      case UserRole.superAdmin:
      case null:
        return Icons.layers_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FilterDropdownShell(
      label: 'Level',
      icon: iconFor(selected),
      muted: selected == null,
      value: selected?.label ?? 'All levels',
      onTap: () => _openPicker(context),
    );
  }
}

class _AccountLevelFilterPickerSheet extends StatelessWidget {
  const _AccountLevelFilterPickerSheet({required this.selected});

  final UserRole? selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
            const SizedBox(height: 14),
            Text(
              'Filter by level',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'User, Employee, or Admin account status.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _PickerTile(
              selected: selected == null,
              leading: Icon(
                Icons.layers_outlined,
                color: colors.textSecondary,
                size: 22,
              ),
              title: 'All levels',
              onTap: () => Navigator.pop(context, ''),
            ),
            const SizedBox(height: 6),
            for (final level in _AccountLevelFilterDropdown._levels) ...[
              _PickerTile(
                selected: selected == level,
                leading: Icon(
                  _AccountLevelFilterDropdown.iconFor(level),
                  color: colors.textSecondary,
                  size: 22,
                ),
                title: level.label,
                onTap: () => Navigator.pop(context, level.storageValue),
              ),
              if (level != UserRole.admin) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyMultiSelectSheet extends StatefulWidget {
  const _CompanyMultiSelectSheet({
    required this.user,
    required this.role,
    required this.companies,
    required this.logoFor,
    required this.initialSelected,
  });

  final UserModel user;
  final UserRole role;
  final List<CompanyModel> companies;
  final Uint8List? Function(String companyId) logoFor;
  final Set<String> initialSelected;

  @override
  State<_CompanyMultiSelectSheet> createState() =>
      _CompanyMultiSelectSheetState();
}

class _CompanyMultiSelectSheetState extends State<_CompanyMultiSelectSheet> {
  final _query = TextEditingController();
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

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
          company.id.toLowerCase().contains(needle) ||
          company.firestoreId.toLowerCase().contains(needle);
    }).toList();
  }

  void _toggle(CompanyModel company) {
    setState(() {
      if (_selected.contains(company.id)) {
        _selected.remove(company.id);
      } else {
        _selected.add(company.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
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
            const SizedBox(height: 14),
            Text(
              'Assign companies',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Choose where ${widget.user.username} is added as ${widget.role.label}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search companies...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () {
                          _query.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
              ),
            ),
            const SizedBox(height: 10),
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
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final company = items[index];
                        final selected = _selected.contains(company.id);
                        return _PickerTile(
                          selected: selected,
                          leading: UserAvatar(
                            bytes: widget.logoFor(company.id),
                            name: company.name,
                            size: 32,
                          ),
                          title: company.name,
                          subtitle: 'ID: ${company.companyId}',
                          onTap: () => _toggle(company),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_selected.length} selected',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Save companies',
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected.toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.selected,
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.16)
          : colors.inputFill,
      borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CompactPageStyle.of(context).radius),
          side: BorderSide(
            color: selected ? AppColors.primary : colors.border,
          ),
        ),
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: selected
            ? const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primaryDark,
                size: 20,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
