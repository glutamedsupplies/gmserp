import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
import 'core/navigation/app_navigator.dart';
import 'core/navigation/app_page_routes.dart';
import 'core/navigation/notification_sync.dart';
import 'core/navigation/post_login.dart';
import 'core/navigation/signed_in_host.dart';
import 'core/navigation/signed_in_nav_controller.dart';
import 'core/navigation/signed_in_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/company_provider.dart';
import 'providers/pending_requests_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/time_card_settings_provider.dart';
import 'providers/time_entry_provider.dart';
import 'providers/user_outcome_notifications_provider.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/company/select_company_screen.dart';
import 'services/leave_reminder_service.dart';
import 'services/leave_request_repository.dart';
import 'services/notification_service.dart';
import 'widgets/app_loading_card.dart';
import 'models/user_role.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _timeEntries = TimeEntryProvider();
  final _timeCardSettings = TimeCardSettingsProvider();
  late final PendingRequestsProvider _pendingRequests;
  late final UserOutcomeNotificationsProvider _userOutcomes;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeEntries.dispose();
    _timeCardSettings.dispose();
    _pendingRequests.dispose();
    _userOutcomes.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingRequests = PendingRequestsProvider(
      notificationsEnabled: () =>
          context.read<SettingsProvider>().notificationsEnabled,
    );
    _userOutcomes = UserOutcomeNotificationsProvider();
    _timeCardSettings.load();
    NotificationService.instance.onNotificationTap = _handleNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final companies = context.read<CompanyProvider>();
      final auth = context.read<AuthProvider>();
      await companies.restoreSelection();
      if (!mounted) return;
      await auth.checkAuthentication();
      if (!mounted) return;
      final user = auth.user;
      final selected = companies.selectedCompany;
      if (user != null &&
          selected != null &&
          (user.role == UserRole.employee || user.role == UserRole.admin)) {
        final member = await companies.isCompanyMember(
          companyId: selected.id,
          userId: user.id,
          email: user.email,
        );
        if (!member && mounted) {
          companies.clearSelection();
        } else if (mounted) {
          await companies.ensureCompanySessionValid();
        }
      }
      if (!mounted) return;
      _syncNotifications();
      await _syncLeaveRemindersForUser();

      final launchPayload =
          await NotificationService.instance.consumeLaunchPayload();
      if (!mounted) return;
      if (launchPayload != null) {
        _handleNotificationTap(launchPayload);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final user = auth.user;
      if (user == null) return;
      if (user.role != UserRole.employee && user.role != UserRole.admin) {
        return;
      }
      final companies = context.read<CompanyProvider>();
      final stillValid = await companies.ensureCompanySessionValid();
      if (!mounted) return;
      _syncNotifications();
      if (!stillValid && companies.selectedCompany != null) {
        // AuthGate rebuilds to SelectCompanyScreen when unlock is cleared.
      }
    });
  }

  /// [App]'s [context] is above [PendingRequestsProvider] / outcomes — never
  /// [context.read] those from here; use the instances owned by this state.
  void _syncNotifications() {
    syncUserNotificationProvidersWith(
      auth: context.read<AuthProvider>(),
      companies: context.read<CompanyProvider>(),
      pendingRequests: _pendingRequests,
      userOutcomes: _userOutcomes,
    );
  }

  void _handleNotificationTap(String? payload) {
    final auth = context.read<AuthProvider>();
    if (payload == NotificationService.calendarRoutePayload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.openShellRoute(AppRoutes.timeCardCalendar);
      });
      return;
    }

    final outcomeEntryId = NotificationService.tryParseOutcomeEntryId(payload);
    if (payload == NotificationService.notificationsRoutePayload ||
        outcomeEntryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.openShellRoute(AppRoutes.notifications);
      });
      return;
    }

    if (auth.user?.role != UserRole.superAdmin &&
        auth.user?.role != UserRole.admin) {
      return;
    }

    final target = RequestNotificationPayload.tryParse(payload);
    // Defer until signed-in navigator exists (cold start from tray).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppNavigator.openSuperAdminRequests(
        requestType: target?.type,
        requestId: target?.id,
      );
    });
  }

  Future<void> _syncLeaveRemindersForUser() async {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final companies = context.read<CompanyProvider>();
    final company = companies.selectedCompany;
    if (user == null || company == null) return;
    if (!companies.notificationsAllowedFor(user.role)) return;
    if (user.role != UserRole.employee && user.role != UserRole.admin) {
      return;
    }
    try {
      final leaves = await LeaveRequestRepository().listForUserCompany(
        userId: user.id,
        companyId: company.id,
      );
      await LeaveReminderService.instance.syncUpcomingLeaveReminders(
        userId: user.id,
        leaves: leaves,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TimeEntryProvider>.value(value: _timeEntries),
        ChangeNotifierProvider<TimeCardSettingsProvider>.value(
          value: _timeCardSettings,
        ),
        ChangeNotifierProvider<PendingRequestsProvider>.value(
          value: _pendingRequests,
        ),
        ChangeNotifierProvider<UserOutcomeNotificationsProvider>.value(
          value: _userOutcomes,
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(compact: settings.isCompactMode),
        darkTheme: AppTheme.dark(compact: settings.isCompactMode),
        themeMode: settings.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 280),
        themeAnimationCurve: Curves.easeOutCubic,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(alwaysUse24HourFormat: false),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const _AuthGate(),
        routes: {
          AppRoutes.register: (_) => const RegisterScreen(),
          AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    context.watch<CompanyProvider>();

    // Keep notification listeners in sync with auth + company unlock.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      syncUserNotificationProviders(context);
    });

    if (auth.isInitializing) {
      return Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: const AppLoadingView(
          title: 'Starting GMSERP',
          message: 'Restoring your session…',
        ),
      );
    }

    if (auth.isAuthenticated && auth.user != null) {
      switch (PostLoginNavigation.routeFor(auth.user!)) {
        case AppRoutes.selectCompany:
          final companies = context.watch<CompanyProvider>();
          // Company-code unlock is required; expired/locked sessions return here.
          if (companies.hasActiveCompanySession) {
            return const _SignedInNavigator();
          }
          return const SelectCompanyScreen();
        default:
          return const _SignedInNavigator();
      }
    }

    return const LoginScreen();
  }
}

/// One navigator for signed-in pages so login/dashboard are not also
/// mounted from MaterialApp named routes (that reused GlobalKeys).
class _SignedInNavigator extends StatefulWidget {
  const _SignedInNavigator();

  @override
  State<_SignedInNavigator> createState() => _SignedInNavigatorState();
}

class _SignedInNavigatorState extends State<_SignedInNavigator> {
  late final SignedInNavController _shellNav;

  @override
  void initState() {
    super.initState();
    _shellNav = SignedInNavController();
  }

  @override
  void dispose() {
    _shellNav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SignedInNavController>.value(
      value: _shellNav,
      child: Navigator(
        key: AppNavigator.signedInKey,
        onGenerateInitialRoutes: (navigator, initialRoute) {
          return [
            signedInPageRoute<void>(
              settings: const RouteSettings(name: AppRoutes.dashboard),
              builder: (_) => const SignedInHost(),
            ),
          ];
        },
        onGenerateRoute: (settings) {
          return signedInPageRoute<void>(
            settings: settings,
            builder: (_) => buildSignedInPage(settings),
          );
        },
      ),
    );
  }
}
