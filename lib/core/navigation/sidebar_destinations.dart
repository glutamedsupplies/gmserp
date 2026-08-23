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
          label: 'User levels',
          icon: Icons.manage_accounts_rounded,
          route: AppRoutes.superAdminUsers,
        ),
        _settings,
      ];
    case null:
      return const [];
  }
}
