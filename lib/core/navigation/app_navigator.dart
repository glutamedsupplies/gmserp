import 'package:flutter/material.dart';

import '../constants/app_routes.dart';

/// Session screens (login, company picker, dashboard) are owned by the auth
/// gate. Pushing them as named routes duplicates those widgets and their keys.
class AppNavigator {
  AppNavigator._();

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
}
