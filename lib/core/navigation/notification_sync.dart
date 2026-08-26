import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/company_provider.dart';
import '../../providers/pending_requests_provider.dart';
import '../../providers/user_outcome_notifications_provider.dart';

/// Keeps inbox/tray listeners aligned with auth and company code unlock.
///
/// Prefer [syncUserNotificationProvidersWith] when the caller already holds the
/// notification providers (e.g. [App] sits *above* those providers in the tree).
void syncUserNotificationProviders(BuildContext context) {
  syncUserNotificationProvidersWith(
    auth: context.read<AuthProvider>(),
    companies: context.read<CompanyProvider>(),
    pendingRequests: context.read<PendingRequestsProvider>(),
    userOutcomes: context.read<UserOutcomeNotificationsProvider>(),
  );
}

void syncUserNotificationProvidersWith({
  required AuthProvider auth,
  required CompanyProvider companies,
  required PendingRequestsProvider pendingRequests,
  required UserOutcomeNotificationsProvider userOutcomes,
}) {
  final user = auth.user;
  final allowed = companies.notificationsAllowedFor(user?.role);
  final company = allowed ? companies.selectedCompany : null;

  pendingRequests.syncUser(
    user,
    companyUnlocked: allowed,
  );
  userOutcomes.syncUser(
    user,
    activeCompany: company,
    companyUnlocked: allowed,
  );
}
