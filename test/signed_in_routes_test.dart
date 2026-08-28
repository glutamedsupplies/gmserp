import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:new_gmserp/core/constants/app_routes.dart';
import 'package:new_gmserp/core/navigation/signed_in_router.dart';
import 'package:new_gmserp/models/company_job_role.dart';
import 'package:new_gmserp/models/company_model.dart';
import 'package:new_gmserp/models/company_task.dart';

void main() {
  const signedInRoutes = <String>[
    AppRoutes.dashboard,
    AppRoutes.adminDashboard,
    AppRoutes.adminSubmittedRequests,
    AppRoutes.employeeTimeInOut,
    AppRoutes.employeeTimeCardDetails,
    AppRoutes.employeeRequestLeave,
    AppRoutes.timeCardCalendar,
    AppRoutes.notifications,
    AppRoutes.superAdmin,
    AppRoutes.superAdminCreate,
    AppRoutes.superAdminList,
    AppRoutes.superAdminCompanyUsers,
    AppRoutes.superAdminEmployees,
    AppRoutes.superAdminRoles,
    AppRoutes.superAdminRoleDetails,
    AppRoutes.superAdminTasks,
    AppRoutes.superAdminTaskDetails,
    AppRoutes.superAdminUsers,
    AppRoutes.superAdminRequests,
    AppRoutes.superAdminLogs,
    AppRoutes.superAdminAnnouncements,
    AppRoutes.superAdminTimeCardDetails,
    AppRoutes.superAdminTimeCardSettings,
    AppRoutes.selectCompany,
    AppRoutes.profile,
    AppRoutes.settings,
    '/unknown-route-should-fallback',
  ];

  final sampleCompany = CompanyModel(
    id: 'c1',
    name: 'Acme',
    passwordHash: 'hash',
    createdBy: 'u1',
  );

  group('buildSignedInPage', () {
    for (final route in signedInRoutes) {
      test('builds widget for $route', () {
        Object? arguments;
        if (route == AppRoutes.superAdminCompanyUsers) {
          arguments = sampleCompany;
        } else if (route == AppRoutes.superAdminRoleDetails) {
          arguments = CompanyRoleListing(
            company: sampleCompany,
            role: const CompanyJobRole(id: 'r1', name: 'Cashier'),
          );
        } else if (route == AppRoutes.superAdminTaskDetails) {
          arguments = CompanyTaskListing(
            company: sampleCompany,
            task: const CompanyTask(
              id: 't1',
              title: 'Stock',
              roleId: 'r1',
              roleName: 'Cashier',
            ),
          );
        } else if (route == AppRoutes.superAdminRequests) {
          arguments = {'type': 'leave', 'id': 'req1'};
        }

        final widget = buildSignedInPage(
          RouteSettings(name: route, arguments: arguments),
        );

        expect(widget, isA<Widget>());
      });
    }

    test('invalid company-users args fall back safely', () {
      final widget = buildSignedInPage(
        const RouteSettings(
          name: AppRoutes.superAdminCompanyUsers,
          arguments: 'not-a-company',
        ),
      );

      expect(widget, isA<Widget>());
    });

    test('invalid role-details args fall back safely', () {
      final widget = buildSignedInPage(
        const RouteSettings(
          name: AppRoutes.superAdminRoleDetails,
          arguments: 42,
        ),
      );

      expect(widget, isA<Widget>());
    });
  });
}
