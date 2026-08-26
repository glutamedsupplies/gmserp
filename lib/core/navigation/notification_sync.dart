import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/pending_requests_provider.dart';
import '../../providers/user_outcome_notifications_provider.dart';

/// Keeps inbox/tray listeners aligned with auth and company code unlock.
void syncUserNotificationProviders(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final companies = context.read<CompanyProvider>();
  final user = auth.user;
  final allowed = companies.notificationsAllowedFor(user?.role);
  final company = allowed ? companies.selectedCompany : null;

  context.read<PendingRequestsProvider>().syncUser(
        user,
        companyUnlocked: allowed,
      );
  context.read<UserOutcomeNotificationsProvider>().syncUser(
        user,
        activeCompany: company,
        companyUnlocked: allowed,
      );
}
