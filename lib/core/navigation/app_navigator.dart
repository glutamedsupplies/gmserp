import 'package:flutter/material.dart';

import '../constants/app_routes.dart';
import 'signed_in_nav_controller.dart';

/// Signed-in navigation helpers (shell + overlay routes).
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
    final shell = SignedInNavController.maybeOf(context) ??
        (signedInKey.currentContext != null
            ? SignedInNavController.maybeOf(signedInKey.currentContext!)
            : null);
    shell?.go(AppRoutes.dashboard);

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  static void _openShellRoute(
    String route, {
    Object? arguments,
    int tries = 0,
  }) {
    final context = signedInKey.currentContext;
    if (context == null) {
      if (tries < 30) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openShellRoute(route, arguments: arguments, tries: tries + 1);
        });
      }
      return;
    }

    SignedInNavController.goTo(context, route, arguments: arguments);
  }

  /// Opens Super Admin Requests, optionally focusing one leave/time request.
  static void openSuperAdminRequests({
    String? requestType,
    String? requestId,
  }) {
    final args = <String, String>{};
    if (requestType != null && requestType.isNotEmpty) {
      args['type'] = requestType;
    }
    if (requestId != null && requestId.isNotEmpty) {
      args['id'] = requestId;
    }

    _openShellRoute(
      AppRoutes.superAdminRequests,
      arguments: args.isEmpty ? null : args,
    );
  }

  static void openShellRoute(
    String route, {
    Object? arguments,
  }) {
    _openShellRoute(route, arguments: arguments);
  }
}
