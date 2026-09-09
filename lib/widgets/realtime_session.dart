import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/utils/realtime_page.dart';
import '../providers/auth_provider.dart';
import '../providers/company_provider.dart';
import '../providers/time_card_settings_provider.dart';

/// Shared profile, membership and schedule data also updates outside pages.
class RealtimeSession extends StatefulWidget {
  const RealtimeSession({super.key, required this.child});
  final Widget child;

  @override
  State<RealtimeSession> createState() => _RealtimeSessionState();
}

class _RealtimeSessionState extends State<RealtimeSession> with RealtimePage {
  @override
  List<String> get realtimePaths => [
    'users/${context.read<AuthProvider>().user!.id}',
    'companies',
    'timeCardSettings',
  ];

  @override
  Future<void> refreshRealtimeData() async {
    final auth = context.read<AuthProvider>();
    final companies = context.read<CompanyProvider>();
    final settings = context.read<TimeCardSettingsProvider>();
    if (!auth.isLoading) await auth.reloadUser();
    if (!mounted) return;
    await companies.refreshSelectedCompany();
    if (!mounted) return;
    final company = companies.selectedCompany;
    final user = auth.user;
    if (company != null && user != null && companies.hasActiveCompanySession) {
      await companies.loadMyAssignment(companyId: company.id, userId: user.id);
    }
    if (!mounted) return;
    if (!settings.isSaving) await settings.load();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
