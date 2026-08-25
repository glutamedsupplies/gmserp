import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/compact_page.dart';
import '../../widgets/dashboard_scaffold.dart';

class UserDashboardScreen extends StatelessWidget {
  const UserDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final density = CompactPageStyle.of(context);

    return DashboardScaffold(
      title: 'User Dashboard',
      currentRoute: AppRoutes.userDashboard,
      child: ListView(
        padding: density.pagePadding,
        children: [
          CompactPageHeader(
            title: 'Welcome, ${user?.username ?? 'User'}',
            subtitle:
                'You are signed in as a User. This dashboard is for standard account access.',
          ),
          SizedBox(height: density.sectionGap + 8),
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
