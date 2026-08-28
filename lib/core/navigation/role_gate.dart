import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_loading_card.dart';
import 'app_navigator.dart';

/// Redirects unauthorized users back to the dashboard once per visit.
mixin _RoleRedirectMixin<T extends StatefulWidget> on State<T> {
  bool _redirectScheduled = false;

  void scheduleRoleRedirect(bool Function(UserRole? role) isAllowed) {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = context.read<AuthProvider>().user?.role;
      if (isAllowed(role)) return;
      AppNavigator.popToRoot(context);
    });
  }
}

class SuperAdminGate extends StatefulWidget {
  const SuperAdminGate({super.key, required this.child});

  final Widget child;

  @override
  State<SuperAdminGate> createState() => _SuperAdminGateState();
}

class _SuperAdminGateState extends State<SuperAdminGate>
    with _RoleRedirectMixin {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user?.role == UserRole.superAdmin) {
      return widget.child;
    }

    scheduleRoleRedirect((role) => role == UserRole.superAdmin);

    return const Scaffold(
      body: AppLoadingView(
        title: 'Checking access',
        message: 'Verifying Super Admin permissions…',
      ),
    );
  }
}

class AdminOrSuperAdminGate extends StatefulWidget {
  const AdminOrSuperAdminGate({super.key, required this.child});

  final Widget child;

  @override
  State<AdminOrSuperAdminGate> createState() => _AdminOrSuperAdminGateState();
}

class _AdminOrSuperAdminGateState extends State<AdminOrSuperAdminGate>
    with _RoleRedirectMixin {
  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    if (role == UserRole.admin || role == UserRole.superAdmin) {
      return widget.child;
    }

    scheduleRoleRedirect(
      (current) => current == UserRole.admin || current == UserRole.superAdmin,
    );

    return const Scaffold(
      body: AppLoadingView(
        title: 'Checking access',
        message: 'Verifying admin permissions…',
      ),
    );
  }
}

class EmployeeGate extends StatefulWidget {
  const EmployeeGate({super.key, required this.child});

  final Widget child;

  @override
  State<EmployeeGate> createState() => _EmployeeGateState();
}

class _EmployeeGateState extends State<EmployeeGate> with _RoleRedirectMixin {
  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    if (role == UserRole.employee) {
      return widget.child;
    }

    scheduleRoleRedirect((current) => current == UserRole.employee);

    return const Scaffold(
      body: AppLoadingView(
        title: 'Checking access',
        message: 'Verifying employee permissions…',
      ),
    );
  }
}
