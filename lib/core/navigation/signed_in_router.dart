import 'package:flutter/material.dart';

import '../constants/app_routes.dart';
import '../../models/company_job_role.dart';
import '../../models/company_model.dart';
import '../../models/company_task.dart';
import '../../screens/company/select_company_screen.dart';
import '../../screens/dashboard/admin_dashboard_screen.dart';
import '../../screens/dashboard/attendance_calendar_screen.dart';
import '../../screens/dashboard/employee_request_leave_screen.dart';
import '../../screens/dashboard/employee_requests_screen.dart';
import '../../screens/dashboard/employee_time_card_details_screen.dart';
import '../../screens/dashboard/employee_time_in_out_screen.dart';
import '../../screens/dashboard/notifications_screen.dart';
import '../../screens/dashboard/profile_screen.dart';
import '../../screens/dashboard/role_dashboard_screen.dart';
import '../../screens/dashboard/settings_screen.dart';
import '../../screens/dashboard/super_admin_announcements_screen.dart';
import '../../screens/dashboard/super_admin_company_users_screen.dart';
import '../../screens/dashboard/super_admin_dashboard_screen.dart';
import '../../screens/dashboard/super_admin_employee_lists_screen.dart';
import '../../screens/dashboard/super_admin_role_details_screen.dart';
import '../../screens/dashboard/super_admin_role_lists_screen.dart';
import '../../screens/dashboard/super_admin_requests_screen.dart';
import '../../screens/dashboard/super_admin_task_details_screen.dart';
import '../../screens/dashboard/super_admin_task_lists_screen.dart';
import '../../screens/dashboard/super_admin_time_card_details_screen.dart';
import '../../screens/dashboard/super_admin_time_card_settings_screen.dart';
import '../../screens/dashboard/super_admin_users_screen.dart';
import 'role_gate.dart';

/// Builds the signed-in shell page for [settings]. Unknown routes fall back to
/// the role dashboard instead of throwing.
Widget buildSignedInPage(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.adminDashboard:
      return const AdminDashboardScreen();
    case AppRoutes.adminSubmittedRequests:
      // Submitted requests is retired for Admin; keep route redirect via scaffold.
      return const RoleDashboardScreen();
    case AppRoutes.employeeTimeInOut:
      return const EmployeeGate(child: EmployeeTimeInOutScreen());
    case AppRoutes.employeeTimeCardDetails:
      return const EmployeeGate(child: EmployeeTimeCardDetailsScreen());
    case AppRoutes.employeeRequestLeave:
      return const EmployeeGate(child: EmployeeRequestLeaveScreen());
    case AppRoutes.employeeRequests:
      return const EmployeeGate(child: EmployeeRequestsScreen());
    case AppRoutes.timeCardCalendar:
      return const AttendanceCalendarScreen();
    case AppRoutes.notifications:
      return const NotificationsScreen();
    case AppRoutes.superAdmin:
    case AppRoutes.superAdminCreate:
      return const SuperAdminGate(
        child: SuperAdminDashboardScreen(
          section: SuperAdminCompanySection.create,
        ),
      );
    case AppRoutes.superAdminList:
      return const SuperAdminGate(
        child: SuperAdminDashboardScreen(
          section: SuperAdminCompanySection.list,
        ),
      );
    case AppRoutes.superAdminCompanyUsers:
      final company = settings.arguments;
      if (company is! CompanyModel) {
        return const SuperAdminGate(
          child: SuperAdminDashboardScreen(
            section: SuperAdminCompanySection.list,
          ),
        );
      }
      return SuperAdminGate(
        child: SuperAdminCompanyUsersScreen(company: company),
      );
    case AppRoutes.superAdminEmployees:
      return const SuperAdminGate(
        child: SuperAdminEmployeeListsScreen(),
      );
    case AppRoutes.superAdminRoles:
      return const SuperAdminGate(
        child: SuperAdminRoleListsScreen(),
      );
    case AppRoutes.superAdminRoleDetails:
      final listing = settings.arguments;
      if (listing is! CompanyRoleListing) {
        return const SuperAdminGate(
          child: SuperAdminRoleListsScreen(),
        );
      }
      return SuperAdminGate(
        child: SuperAdminRoleDetailsScreen(listing: listing),
      );
    case AppRoutes.superAdminTasks:
      return const SuperAdminGate(
        child: SuperAdminTaskListsScreen(),
      );
    case AppRoutes.superAdminTaskDetails:
      final listing = settings.arguments;
      if (listing is! CompanyTaskListing) {
        return const SuperAdminGate(
          child: SuperAdminTaskListsScreen(),
        );
      }
      return SuperAdminGate(
        child: SuperAdminTaskDetailsScreen(listing: listing),
      );
    case AppRoutes.superAdminUsers:
      return const SuperAdminGate(
        child: SuperAdminUsersScreen(),
      );
    case AppRoutes.superAdminRequests:
      final args = settings.arguments;
      String? focusType;
      String? focusId;
      if (args is Map) {
        focusType = args['type']?.toString();
        focusId = args['id']?.toString();
      }
      return AdminOrSuperAdminGate(
        child: SuperAdminRequestsScreen(
          focusRequestType: focusType,
          focusRequestId: focusId,
        ),
      );
    case AppRoutes.superAdminLogs:
      return const SuperAdminGate(
        child: NotificationsScreen(),
      );
    case AppRoutes.superAdminAnnouncements:
      return const SuperAdminGate(
        child: SuperAdminAnnouncementsScreen(),
      );
    case AppRoutes.superAdminTimeCardDetails:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardDetailsScreen(),
      );
    case AppRoutes.superAdminTimeCardSettings:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardSettingsScreen(),
      );
    case AppRoutes.selectCompany:
      return const SelectCompanyScreen();
    case AppRoutes.profile:
      return const ProfileScreen();
    case AppRoutes.settings:
      return const SettingsScreen();
    case AppRoutes.dashboard:
    case AppRoutes.home:
    case AppRoutes.userDashboard:
    case AppRoutes.employeeDashboard:
    default:
      return const RoleDashboardScreen();
  }
}
