import 'package:flutter/material.dart';

import '../../core/constants/app_routes.dart';
import '../../widgets/dashboard_scaffold.dart';
import '../../widgets/dashboard_announcements.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});
  @override
  Widget build(BuildContext context) => DashboardScaffold(
    title: 'Announcements',
    currentRoute: AppRoutes.announcements,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: const [DashboardAnnouncements()],
    ),
  );
}
