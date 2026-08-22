import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../constants/app_routes.dart';

class SidebarDestination {
  const SidebarDestination({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

const _dashboard = SidebarDestination(
  label: 'Dashboard',
  icon: Icons.dashboard_rounded,
  route: AppRoutes.dashboard,
);

List<SidebarDestination> destinationsForRole(UserRole? role) {
  switch (role) {
    case UserRole.user:
      return const [_dashboard];
    case UserRole.employee:
      return const [
        _dashboard,
        SidebarDestination(
          label: 'Companies',
          icon: Icons.apartment_rounded,
          route: AppRoutes.selectCompany,
        ),
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
          label: 'Companies',
          icon: Icons.apartment_rounded,
          route: AppRoutes.selectCompany,
        ),
      ];
    case UserRole.superAdmin:
      return const [
        _dashboard,
        SidebarDestination(
          label: 'Companies',
          icon: Icons.business_rounded,
          route: AppRoutes.superAdmin,
        ),
        SidebarDestination(
          label: 'User levels',
          icon: Icons.manage_accounts_rounded,
          route: AppRoutes.superAdminUsers,
        ),
      ];
    case null:
      return const [];
  }
}
