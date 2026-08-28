import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/navigation/signed_in_nav_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../models/time_entry.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/pending_requests_provider.dart';
import '../../providers/time_entry_provider.dart';
import '../../providers/user_outcome_notifications_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class RoleDashboardScreen extends StatefulWidget {
  const RoleDashboardScreen({super.key});

  @override
  State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    final companies = context.read<CompanyProvider>();
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    final role = companies.effectiveRoleFor(user);
    final time = context.read<TimeEntryProvider>();

    try {
      switch (role) {
        case UserRole.employee:
          final company = companies.selectedCompany;
          if (company != null) {
            await companies.loadMyAssignment(
              companyId: company.id,
              userId: user.id,
            );
            if (!mounted) return;
            await time.loadDetailsForCompany(user: user, company: company);
          }
          break;
        case UserRole.admin:
          final company = companies.selectedCompany;
          if (company != null) {
            await companies.loadMyAssignment(
              companyId: company.id,
              userId: user.id,
            );
            await companies.loadStaff(company.id);
            await companies.loadCompanyUsers(company.id);
          }
          break;
        case UserRole.superAdmin:
          await companies.loadCompanies();
          await companies.loadUsers();
          break;
        case UserRole.user:
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(String route, {Object? arguments}) {
    if (route == AppRoutes.dashboard) return;
    if (route == AppRoutes.selectCompany) {
      context.read<CompanyProvider>().beginCompanyPick();
      return;
    }
    SignedInNavController.goTo(context, route, arguments: arguments);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final companies = context.watch<CompanyProvider>();
    final role = companies.effectiveRoleFor(user);
    final density = CompactPageStyle.of(context);
    final pending = context.watch<PendingRequestsProvider>();
    final outcomes = context.watch<UserOutcomeNotificationsProvider>();
    final time = context.watch<TimeEntryProvider>();

    return DashboardScaffold(
      title: 'Dashboard',
      currentRoute: AppRoutes.dashboard,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: density.pagePadding,
          children: [
            CompactPageHeader(
              title: 'Welcome, ${user?.username ?? 'Guest'}',
              subtitle: _subtitle(role, companies.selectedCompany?.name),
            ),
            SizedBox(height: density.sectionGap),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (role == UserRole.employee)
                ..._employeeBody(
                  context,
                  companies: companies,
                  time: time,
                  unseen: outcomes.unseenCount,
                )
              else if (role == UserRole.admin)
                ..._adminBody(
                  context,
                  companies: companies,
                  pending: pending.pendingCount,
                  unseen: outcomes.unseenCount,
                )
              else if (role == UserRole.superAdmin)
                ..._superAdminBody(
                  context,
                  companies: companies,
                  pending: pending.pendingCount,
                  unseen: outcomes.unseenCount,
                )
              else
                ..._userBody(context, user?.email, user?.phoneNumber),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _employeeBody(
    BuildContext context, {
    required CompanyProvider companies,
    required TimeEntryProvider time,
    required int unseen,
  }) {
    final density = CompactPageStyle.of(context);
    final assignment = companies.myAssignment;
    final roleLabel = assignment?.jobRole.trim().isNotEmpty == true
        ? assignment!.jobRole
        : 'Role not assigned yet';
    final tasks = assignment?.tasks ?? const <String>[];
    final status = _employeeStatus(time);

    return [
      _HeroPanel(
        accent: status.color,
        icon: status.icon,
        eyebrow: 'Attendance today',
        title: status.title,
        body: status.detail,
        metrics: [
          _Metric('Today', formatDurationShort(time.todayWorked)),
          _Metric('This week', formatDurationShort(time.weekWorked)),
          _Metric('This month', formatDurationShort(time.monthWorked)),
        ],
        cta: 'Open time in / out',
        onTap: () => _go(AppRoutes.employeeTimeInOut),
      ),
      SizedBox(height: density.sectionGap),
      _FeatureStory(
        icon: Icons.workspace_premium_outlined,
        title: 'Your place in the team',
        body: tasks.isEmpty
            ? '$roleLabel · No tasks assigned yet. Ask your admin to map your role.'
            : '$roleLabel · You’re covering ${tasks.length} '
                'task${tasks.length == 1 ? '' : 's'} for this company.',
        chips: [
          roleLabel,
          if (tasks.isNotEmpty) ...tasks.take(4),
          if (tasks.length > 4) '+${tasks.length - 4} more',
        ],
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.event_busy_outlined,
            title: 'Leave & time off',
            body: 'Request leave and track outcomes in Notifications.',
            onTap: () => _go(AppRoutes.employeeRequestLeave),
          ),
          _FeatureTile(
            icon: Icons.calendar_month_rounded,
            title: 'Attendance calendar',
            body: 'See worked days, leave, and schedule at a glance.',
            onTap: () => _go(AppRoutes.timeCardCalendar),
          ),
        ],
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.description_outlined,
            title: 'Time card story',
            body:
                'Review sessions, hours, and history for ${companies.selectedCompany?.name ?? 'this company'}.',
            onTap: () => _go(AppRoutes.employeeTimeCardDetails),
          ),
          _FeatureTile(
            icon: Icons.notifications_outlined,
            title: unseen > 0 ? '$unseen new updates' : 'Your inbox',
            body: unseen > 0
                ? 'Leave, time changes, salary, and announcements waiting.'
                : 'Approvals and company updates show up here.',
            highlight: unseen > 0,
            onTap: () => _go(AppRoutes.notifications),
          ),
        ],
      ),
    ];
  }

  List<Widget> _adminBody(
    BuildContext context, {
    required CompanyProvider companies,
    required int pending,
    required int unseen,
  }) {
    final density = CompactPageStyle.of(context);
    final staff = companies.staff;
    final employees = staff
        .where((m) => companies.memberAccessRole(m) == UserRole.employee)
        .length;
    final admins = staff
        .where((m) => companies.memberAccessRole(m) == UserRole.admin)
        .length;
    final unassigned = staff
        .where(
          (m) =>
              companies.memberAccessRole(m) == UserRole.employee &&
              (m.jobRole.trim().isEmpty || m.tasks.isEmpty),
        )
        .length;
    final covered = employees - unassigned;
    final companyName = companies.selectedCompany?.name ?? 'this company';

    return [
      _HeroPanel(
        accent: pending > 0 ? AppColors.primaryDark : Colors.teal,
        icon: pending > 0
            ? Icons.inbox_outlined
            : Icons.verified_outlined,
        eyebrow: 'Company pulse · $companyName',
        title: pending > 0
            ? '$pending item${pending == 1 ? '' : 's'} need your decision'
            : 'Inbox is clear',
        body: pending > 0
            ? 'Leave, clock, and time-card changes are waiting for review.'
            : 'No pending requests right now. Keep staffing and time cards tidy.',
        metrics: [
          _Metric('Staff', '${staff.length}'),
          _Metric('Employees', '$employees'),
          _Metric('Admins', '$admins'),
        ],
        cta: pending > 0 ? 'Review requests' : 'Open requests',
        onTap: () => _go(AppRoutes.superAdminRequests),
      ),
      SizedBox(height: density.sectionGap),
      _FeatureStory(
        icon: Icons.groups_rounded,
        title: 'Workforce coverage',
        body: unassigned > 0
            ? '$covered of $employees employees have role & tasks. '
                '$unassigned still need assignment on Staff.'
            : employees == 0
                ? 'No employees in this company yet. Add people from Staff.'
                : 'Every employee has a role and tasks mapped. Nice coverage.',
        chips: [
          '$employees employees',
          '$admins admins',
          if (unassigned > 0) '$unassigned unassigned',
          if (unseen > 0) '$unseen alerts',
        ],
        onTap: () => _go(AppRoutes.adminDashboard),
        cta: 'Manage staff',
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.description_outlined,
            title: 'Team time cards',
            body: 'Inspect attendance sessions and edit records for the company.',
            onTap: () => _go(AppRoutes.superAdminTimeCardDetails),
          ),
          _FeatureTile(
            icon: Icons.payments_outlined,
            title: 'Rates & schedules',
            body: 'Set daily salary rates and time-card rules for staff.',
            onTap: () => _go(AppRoutes.superAdminTimeCardSettings),
          ),
        ],
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.calendar_month_rounded,
            title: 'Company calendar',
            body: 'Spot who worked, who’s on leave, and busy days.',
            onTap: () => _go(AppRoutes.timeCardCalendar),
          ),
          _FeatureTile(
            icon: Icons.notifications_outlined,
            title: unseen > 0 ? '$unseen updates waiting' : 'Outcomes inbox',
            body: 'Salary changes, announcements, and request results.',
            highlight: unseen > 0,
            onTap: () => _go(AppRoutes.notifications),
          ),
        ],
      ),
    ];
  }

  List<Widget> _superAdminBody(
    BuildContext context, {
    required CompanyProvider companies,
    required int pending,
    required int unseen,
  }) {
    final density = CompactPageStyle.of(context);
    final users = companies.users;
    final employees =
        users.where((u) => u.role == UserRole.employee).length;
    final admins = users.where((u) => u.role == UserRole.admin).length;
    final companyCount = companies.companies.length;

    return [
      _HeroPanel(
        accent: AppColors.primaryDark,
        icon: Icons.hub_outlined,
        eyebrow: 'System overview',
        title: companyCount == 0
            ? 'No companies yet'
            : '$companyCount compan${companyCount == 1 ? 'y' : 'ies'} on the network',
        body: pending > 0
            ? '$pending pending request${pending == 1 ? '' : 's'} across the system need attention.'
            : 'Users, catalogs, and company access are ready to manage.',
        metrics: [
          _Metric('Companies', '$companyCount'),
          _Metric('Users', '${users.length}'),
          _Metric('Pending', '$pending'),
        ],
        cta: pending > 0 ? 'Review requests' : 'Browse companies',
        onTap: () => _go(
          pending > 0
              ? AppRoutes.superAdminRequests
              : AppRoutes.superAdminList,
        ),
      ),
      SizedBox(height: density.sectionGap),
      _FeatureStory(
        icon: Icons.people_alt_rounded,
        title: 'People across GMSERP',
        body:
            '$employees employees · $admins admins · '
            '${users.where((u) => u.role == UserRole.superAdmin).length} super admins. '
            'Promote levels and sync company memberships from User levels.',
        chips: [
          '$employees employees',
          '$admins admins',
          if (unseen > 0) '$unseen alerts',
        ],
        onTap: () => _go(AppRoutes.superAdminUsers),
        cta: 'Open user levels',
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.add_business_rounded,
            title: 'Launch a company',
            body: 'Create a workspace with founder password and staff code.',
            onTap: () => _go(AppRoutes.superAdminCreate),
          ),
          _FeatureTile(
            icon: Icons.campaign_outlined,
            title: 'Broadcast updates',
            body: 'Send announcements to admins, everyone, or selected members.',
            onTap: () => _go(AppRoutes.superAdminAnnouncements),
          ),
        ],
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.workspace_premium_outlined,
            title: 'Roles & tasks catalog',
            body: 'Define job roles and reusable tasks companies can assign.',
            onTap: () => _go(AppRoutes.superAdminRoles),
          ),
          _FeatureTile(
            icon: Icons.history_rounded,
            title: 'Activity trail',
            body: 'Audit leave, time edits, salary changes, and announcements.',
            onTap: () => _go(AppRoutes.notifications),
          ),
        ],
      ),
      SizedBox(height: density.cardGap),
      _FeatureRow(
        items: [
          _FeatureTile(
            icon: Icons.badge_outlined,
            title: 'Employee memberships',
            body: 'See who belongs where and adjust company access.',
            onTap: () => _go(AppRoutes.superAdminEmployees),
          ),
          _FeatureTile(
            icon: Icons.schedule_rounded,
            title: 'Time card control',
            body: 'Company attendance details, rates, and calendar.',
            onTap: () => _go(AppRoutes.superAdminTimeCardDetails),
          ),
        ],
      ),
    ];
  }

  List<Widget> _userBody(
    BuildContext context,
    String? email,
    String? phone,
  ) {
    final density = CompactPageStyle.of(context);
    return [
      _HeroPanel(
        accent: AppColors.primaryDark,
        icon: Icons.person_outline_rounded,
        eyebrow: 'Your account',
        title: 'Signed in as a User',
        body:
            'This level is for standard access. Keep your profile current and tune how the app looks.',
        metrics: const [
          _Metric('Level', 'User'),
        ],
        cta: 'Open profile',
        onTap: () => _go(AppRoutes.profile),
      ),
      SizedBox(height: density.sectionGap),
      _FeatureStory(
        icon: Icons.info_outline_rounded,
        title: 'Account details',
        body:
            'Email: ${email?.isNotEmpty == true ? email : '—'}\n'
            'Phone: ${phone?.isNotEmpty == true ? phone : '—'}',
      ),
      SizedBox(height: density.cardGap),
      _FeatureTile(
        icon: Icons.settings_rounded,
        title: 'Appearance & notifications',
        body: 'Theme, compact mode, and notification preferences.',
        onTap: () => _go(AppRoutes.settings),
      ),
    ];
  }

  _EmployeeStatus _employeeStatus(TimeEntryProvider time) {
    if (time.pendingClockIn != null) {
      return const _EmployeeStatus(
        icon: Icons.hourglass_top_rounded,
        title: 'Time in is waiting for approval',
        detail: 'An admin still needs to clear your clock-in request.',
        color: Colors.orange,
      );
    }
    if (time.pendingClockOut != null) {
      return const _EmployeeStatus(
        icon: Icons.hourglass_bottom_rounded,
        title: 'Time out is waiting for approval',
        detail: 'Your clock-out request is in the review queue.',
        color: Colors.orange,
      );
    }
    if (time.activeEntry != null) {
      return _EmployeeStatus(
        icon: Icons.play_circle_outline_rounded,
        title: 'You’re on the clock',
        detail:
            'Session open · ${formatDurationShort(time.todayWorked)} logged today.',
        color: Colors.green,
      );
    }
    if (time.hasCompletedToday) {
      return _EmployeeStatus(
        icon: Icons.check_circle_outline_rounded,
        title: 'Day wrapped up',
        detail:
            'You logged ${formatDurationShort(time.todayWorked)} today. Review details anytime.',
        color: AppColors.primaryDark,
      );
    }
    return const _EmployeeStatus(
      icon: Icons.login_rounded,
      title: 'Ready when you are',
      detail: 'Start your day with Time in when you arrive.',
      color: AppColors.primaryDark,
    );
  }

  String _subtitle(UserRole? role, String? companyName) {
    switch (role) {
      case UserRole.user:
        return 'Account overview for your User level.';
      case UserRole.employee:
        return companyName == null
            ? 'Your workday at a glance.'
            : 'Your workday at $companyName.';
      case UserRole.admin:
        return companyName == null
            ? 'People, time, and approvals for your company.'
            : 'People, time, and approvals at $companyName.';
      case UserRole.superAdmin:
        return 'Companies, people, and system-wide activity.';
      case null:
        return '';
    }
  }
}

class _EmployeeStatus {
  const _EmployeeStatus({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.accent,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.metrics,
    required this.cta,
    required this.onTap,
  });

  final Color accent;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final List<_Metric> metrics;
  final String cta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    return Material(
      color: accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(density.settingsCardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(density.settingsCardRadius),
        child: Container(
          width: double.infinity,
          padding: density.cardPadding.add(const EdgeInsets.all(6)),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(density.settingsCardRadius),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: density.settingsIconSize,
                    height: density.settingsIconSize,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(density.radius),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  SizedBox(width: density.compact ? 10 : 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow.toUpperCase(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    fontSize: density.chipLabelSize,
                                  ),
                        ),
                        SizedBox(height: density.compact ? 2 : 4),
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: density.sectionTitleSize,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: density.cardGap),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.bodySize,
                    ),
              ),
              if (metrics.isNotEmpty) ...[
                SizedBox(height: density.sectionGap),
                Row(
                  children: [
                    for (var i = 0; i < metrics.length; i++) ...[
                      if (i > 0) SizedBox(width: density.cardGap),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            vertical: density.compact ? 8 : 10,
                            horizontal: density.compact ? 8 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.card.withValues(alpha: 0.85),
                            borderRadius:
                                BorderRadius.circular(density.radius),
                          ),
                          child: Column(
                            children: [
                              Text(
                                metrics[i].value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              SizedBox(height: density.compact ? 2 : 4),
                              Text(
                                metrics[i].label,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: colors.textSecondary,
                                      fontSize: density.chipLabelSize,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              SizedBox(height: density.cardGap),
              Row(
                children: [
                  Text(
                    cta,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: density.bodySize,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureStory extends StatelessWidget {
  const _FeatureStory({
    required this.icon,
    required this.title,
    required this.body,
    this.chips = const [],
    this.onTap,
    this.cta,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> chips;
  final VoidCallback? onTap;
  final String? cta;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    final child = Container(
      width: double.infinity,
      padding: density.cardPadding.add(const EdgeInsets.all(4)),
      decoration: BoxDecoration(
        color: colors.inputFill,
        borderRadius: BorderRadius.circular(density.settingsCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryDark),
              SizedBox(width: density.compact ? 8 : 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: density.cardTitleSize,
                      ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
            ],
          ),
          SizedBox(height: density.cardGap),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontSize: density.bodySize,
                  height: 1.35,
                ),
          ),
          if (chips.isNotEmpty) ...[
            SizedBox(height: density.cardGap),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in chips)
                  Chip(
                    label: Text(chip),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (cta != null) ...[
            SizedBox(height: density.cardGap),
            Text(
              cta!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(density.settingsCardRadius),
        child: child,
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.items});

  final List<_FeatureTile> items;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 560 && items.length > 1;
        if (!sideBySide) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: density.cardGap),
                items[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: density.cardGap),
              Expanded(child: items[i]),
            ],
          ],
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final density = CompactPageStyle.of(context);
    final colors = AppColors.of(context);
    return Material(
      color: highlight
          ? AppColors.primary.withValues(alpha: 0.14)
          : colors.card,
      borderRadius: BorderRadius.circular(density.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(density.radius),
        child: Container(
          width: double.infinity,
          padding: density.cardPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(density.radius),
            border: Border.all(
              color: highlight
                  ? AppColors.primaryDark.withValues(alpha: 0.35)
                  : colors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.primaryDark),
              SizedBox(height: density.cardGap),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: density.cardTitleSize,
                    ),
              ),
              SizedBox(height: density.titleSubtitleGap),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: density.captionSize,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
