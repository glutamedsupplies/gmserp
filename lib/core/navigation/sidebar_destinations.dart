import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../constants/app_routes.dart';

class SidebarDestination {
  const SidebarDestination({
    required this.label,
    required this.icon,
    this.route,
    this.children = const [],
  });

  final String label;
  final IconData icon;
  final String? route;
  final List<SidebarDestination> children;

  bool get hasChildren => children.isNotEmpty;

  bool containsRoute(String currentRoute) {
    if (route == currentRoute) return true;
    if (route != null && currentRoute.startsWith('$route/')) return true;
    return children.any((child) => child.containsRoute(currentRoute));
  }
}

const _dashboard = SidebarDestination(
  label: 'Dashboard',
  icon: Icons.dashboard_rounded,
  route: AppRoutes.dashboard,
);

const _settings = SidebarDestination(
  label: 'Settings',
  icon: Icons.settings_rounded,
  route: AppRoutes.settings,
);

List<SidebarDestination> destinationsForRole(UserRole? role) {
  switch (role) {
    case UserRole.user:
      return const [_dashboard, _settings];
    case UserRole.employee:
      return const [
        _dashboard,
        SidebarDestination(
          label: 'Time Card',
          icon: Icons.schedule_rounded,
          children: [
            SidebarDestination(
              label: 'Time in / Time out',
              icon: Icons.login_rounded,
              route: AppRoutes.employeeTimeInOut,
            ),
            SidebarDestination(
              label: 'Time card details',
              icon: Icons.description_outlined,
              route: AppRoutes.employeeTimeCardDetails,
            ),
            SidebarDestination(
              label: 'Calendar',
              icon: Icons.calendar_month_rounded,
              route: AppRoutes.timeCardCalendar,
            ),
          ],
        ),
        SidebarDestination(
          label: 'Request leave',
          icon: Icons.event_busy_outlined,
          route: AppRoutes.employeeRequestLeave,
        ),
        SidebarDestination(
          label: 'Switch company',
          icon: Icons.swap_horiz_rounded,
          route: AppRoutes.selectCompany,
        ),
        _settings,
      ];
    case UserRole.admin:
      return const [
        _dashboard,
        SidebarDestination(
          label: 'Staff',
          icon: Icons.groups_rounded,
          route: AppRoutes.adminDashboard,
        ),
        SidebarDestination(
          label: 'Time Card',
          icon: Icons.schedule_rounded,
          children: [
            SidebarDestination(
              label: 'Time card details',
              icon: Icons.description_outlined,
              route: AppRoutes.superAdminTimeCardDetails,
            ),
            SidebarDestination(
              label: 'Time card settings',
              icon: Icons.tune_rounded,
              route: AppRoutes.superAdminTimeCardSettings,
            ),
            SidebarDestination(
              label: 'Calendar',
              icon: Icons.calendar_month_rounded,
              route: AppRoutes.timeCardCalendar,
            ),
          ],
        ),
        SidebarDestination(
          label: 'Submitted requests',
          icon: Icons.outbox_outlined,
          route: AppRoutes.adminSubmittedRequests,
        ),
        SidebarDestination(
          label: 'Requests',
          icon: Icons.inbox_outlined,
          route: AppRoutes.superAdminRequests,
        ),
        SidebarDestination(
          label: 'Request leave',
          icon: Icons.event_busy_outlined,
          route: AppRoutes.employeeRequestLeave,
        ),
        SidebarDestination(
          label: 'Switch company',
          icon: Icons.swap_horiz_rounded,
          route: AppRoutes.selectCompany,
        ),
        _settings,
      ];
    case UserRole.superAdmin:
      return const [
        _dashboard,
        SidebarDestination(
          label: 'Companies',
          icon: Icons.business_rounded,
          children: [
            SidebarDestination(
              label: 'Create company',
              icon: Icons.add_business_rounded,
              route: AppRoutes.superAdminCreate,
            ),
            SidebarDestination(
              label: 'Company lists',
              icon: Icons.list_alt_rounded,
              route: AppRoutes.superAdminList,
            ),
            SidebarDestination(
              label: 'Employee lists',
              icon: Icons.badge_outlined,
              route: AppRoutes.superAdminEmployees,
            ),
            SidebarDestination(
              label: 'Role lists',
              icon: Icons.workspace_premium_outlined,
              route: AppRoutes.superAdminRoles,
            ),
            SidebarDestination(
              label: 'Task lists',
              icon: Icons.task_alt_rounded,
              route: AppRoutes.superAdminTasks,
            ),
          ],
        ),
        SidebarDestination(
          label: 'Time Card',
          icon: Icons.schedule_rounded,
          children: [
            SidebarDestination(
              label: 'Time card details',
              icon: Icons.description_outlined,
              route: AppRoutes.superAdminTimeCardDetails,
            ),
            SidebarDestination(
              label: 'Time card settings',
              icon: Icons.tune_rounded,
              route: AppRoutes.superAdminTimeCardSettings,
            ),
          ],
        ),
        SidebarDestination(
          label: 'User levels',
          icon: Icons.manage_accounts_rounded,
          route: AppRoutes.superAdminUsers,
        ),
        SidebarDestination(
          label: 'Requests',
          icon: Icons.inbox_outlined,
          route: AppRoutes.superAdminRequests,
        ),
        _settings,
      ];
    case null:
      return const [];
  }
}
