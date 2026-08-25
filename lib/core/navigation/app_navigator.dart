import 'package:flutter/material.dart';

import '../constants/app_routes.dart';

/// Session screens (login, company picker, dashboard) are owned by the auth
/// gate. Pushing them as named routes duplicates those widgets and their keys.
class AppNavigator {
  AppNavigator._();

  /// Navigator for signed-in Super Admin / employee / admin shell.
  static final GlobalKey<NavigatorState> signedInKey =
      GlobalKey<NavigatorState>();

  static const sessionRoutes = {
    AppRoutes.login,
    AppRoutes.home,
    AppRoutes.dashboard,
    AppRoutes.userDashboard,
    AppRoutes.employeeDashboard,
    AppRoutes.selectCompany,
  };

  static bool isSessionRoute(String route) => sessionRoutes.contains(route);

  static void popToRoot(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  /// Opens Super Admin Requests, optionally focusing one leave/time request.
  static void openSuperAdminRequests({
    String? requestType,
    String? requestId,
  }) {
    void attempt([int tries = 0]) {
      final navigator = signedInKey.currentState;
      if (navigator == null) {
        if (tries < 30) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            attempt(tries + 1);
          });
        }
        return;
      }

      final args = <String, String>{};
      if (requestType != null && requestType.isNotEmpty) {
        args['type'] = requestType;
      }
      if (requestId != null && requestId.isNotEmpty) {
        args['id'] = requestId;
      }

      navigator.pushNamedAndRemoveUntil(
        AppRoutes.superAdminRequests,
        (route) => route.isFirst,
        arguments: args.isEmpty ? null : args,
      );
    }

    attempt();
  }
}