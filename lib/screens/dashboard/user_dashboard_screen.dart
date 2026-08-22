import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/dashboard_scaffold.dart';

class UserDashboardScreen extends StatelessWidget {
  const UserDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return DashboardScaffold(
      title: 'User Dashboard',
      currentRoute: AppRoutes.userDashboard,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Welcome, ${user?.username ?? 'User'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'You are signed in as a User. This dashboard is for standard account access.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _Info(label: 'Email', value: user?.email ?? ''),
          _Info(label: 'Phone', value: user?.phoneNumber ?? ''),
          _Info(label: 'Level', value: user?.role.label ?? 'User'),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text('$label: $value'),
    );
  }
}
