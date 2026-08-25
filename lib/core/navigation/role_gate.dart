import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/app_loading_card.dart';
import 'app_navigator.dart';

class SuperAdminGate extends StatelessWidget {
  const SuperAdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user?.role == UserRole.superAdmin) {
      return child;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      if (context.read<AuthProvider>().user?.role == UserRole.superAdmin) {
        return;
      }
      AppNavigator.popToRoot(context);
    });

    return const Scaffold(
      body: AppLoadingView(
        title: 'Checking access',
        message: 'Verifying Super Admin permissions…',
      ),
    );
  }
}

class AdminOrSuperAdminGate extends StatelessWidget {
  const AdminOrSuperAdminGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AuthProvider>().user?.role;
    if (role == UserRole.admin || role == UserRole.superAdmin) {
      return child;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final current = context.read<AuthProvider>().user?.role;
      if (current == UserRole.admin || current == UserRole.superAdmin) {
        return;
      }
      AppNavigator.popToRoot(context);
    });

    return const Scaffold(
      body: AppLoadingView(
        title: 'Checking access',
        message: 'Verifying admin permissions…',
      ),
    );
  }
}
