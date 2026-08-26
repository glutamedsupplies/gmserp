import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
import 'core/navigation/app_navigator.dart';
import 'core/navigation/notification_sync.dart';
import 'core/navigation/post_login.dart';
import 'core/navigation/role_gate.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'models/company_job_role.dart';
import 'models/company_model.dart';
import 'models/company_task.dart';
import 'models/user_role.dart';
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
import 'screens/dashboard/admin_dashboard_screen.dart';
import 'screens/dashboard/attendance_calendar_screen.dart';
import 'screens/dashboard/employee_request_leave_screen.dart';
import 'screens/dashboard/employee_time_card_details_screen.dart';
import 'screens/dashboard/employee_time_in_out_screen.dart';
import 'screens/dashboard/notifications_screen.dart';
import 'screens/dashboard/profile_screen.dart';
import 'screens/dashboard/role_dashboard_screen.dart';
import 'screens/dashboard/settings_screen.dart';
import 'screens/dashboard/super_admin_announcements_screen.dart';
import 'screens/dashboard/super_admin_company_users_screen.dart';
import 'screens/dashboard/super_admin_dashboard_screen.dart';
import 'screens/dashboard/super_admin_employee_lists_screen.dart';
import 'screens/dashboard/super_admin_role_details_screen.dart';
import 'screens/dashboard/super_admin_role_lists_screen.dart';
import 'screens/dashboard/super_admin_requests_screen.dart';
import 'screens/dashboard/super_admin_task_details_screen.dart';
import 'screens/dashboard/super_admin_task_lists_screen.dart';
import 'screens/dashboard/super_admin_time_card_details_screen.dart';
import 'screens/dashboard/super_admin_time_card_settings_screen.dart';
import 'screens/dashboard/super_admin_users_screen.dart';
import 'services/leave_reminder_service.dart';
import 'services/leave_request_repository.dart';
import 'services/notification_service.dart';
import 'widgets/app_loading_card.dart';

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
      syncUserNotificationProviders(context);
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
      syncUserNotificationProviders(context);
      if (!stillValid && companies.selectedCompany != null) {
        // AuthGate rebuilds to SelectCompanyScreen when unlock is cleared.
      }
    });
  }

  void _handleNotificationTap(String? payload) {
    final auth = context.read<AuthProvider>();
    if (payload == NotificationService.calendarRoutePayload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.signedInKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.timeCardCalendar,
          (route) => route.isFirst,
        );
      });
      return;
    }

    final outcomeEntryId = NotificationService.tryParseOutcomeEntryId(payload);
    if (payload == NotificationService.notificationsRoutePayload ||
        outcomeEntryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppNavigator.signedInKey.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.notifications,
          (route) => route.isFirst,
        );
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
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: AppNavigator.signedInKey,
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return [
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: AppRoutes.dashboard),
            builder: (_) => const RoleDashboardScreen(),
          ),
        ];
      },
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _signedInPage(settings),
        );
      },
    );
  }
}

Widget _signedInPage(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.adminDashboard:
      return const AdminDashboardScreen();
    case AppRoutes.adminSubmittedRequests:
      // Submitted requests is retired for Admin; keep route redirect via scaffold.
      return const RoleDashboardScreen();
    case AppRoutes.employeeTimeInOut:
      return const EmployeeGate(child: EmployeeTimeInOutScreen());
    case AppRoutes.employeeTimeCardDetails:
      return const EmployeeGate(child: EmployeeTimeCardDetailsScreen());
    case AppRoutes.employeeRequestLeave:
      return const EmployeeGate(child: EmployeeRequestLeaveScreen());
    case AppRoutes.timeCardCalendar:
      return const AttendanceCalendarScreen();
    case AppRoutes.notifications:
      return const NotificationsScreen();
    case AppRoutes.superAdmin:
    case AppRoutes.superAdminCreate:
      return const SuperAdminGate(
        child: SuperAdminDashboardScreen(
          section: SuperAdminCompanySection.create,
        ),
      );
    case AppRoutes.superAdminList:
      return const SuperAdminGate(
        child: SuperAdminDashboardScreen(
          section: SuperAdminCompanySection.list,
        ),
      );
    case AppRoutes.superAdminCompanyUsers:
      final company = settings.arguments;
      if (company is! CompanyModel) {
        return const SuperAdminGate(
          child: SuperAdminDashboardScreen(
            section: SuperAdminCompanySection.list,
          ),
        );
      }
      return SuperAdminGate(
        child: SuperAdminCompanyUsersScreen(company: company),
      );
    case AppRoutes.superAdminEmployees:
      return const SuperAdminGate(
        child: SuperAdminEmployeeListsScreen(),
      );
    case AppRoutes.superAdminRoles:
      return const SuperAdminGate(
        child: SuperAdminRoleListsScreen(),
      );
    case AppRoutes.superAdminRoleDetails:
      final listing = settings.arguments;
      if (listing is! CompanyRoleListing) {
        return const SuperAdminGate(
          child: SuperAdminRoleListsScreen(),
        );
      }
      return SuperAdminGate(
        child: SuperAdminRoleDetailsScreen(listing: listing),
      );
    case AppRoutes.superAdminTasks:
      return const SuperAdminGate(
        child: SuperAdminTaskListsScreen(),
      );
    case AppRoutes.superAdminTaskDetails:
      final listing = settings.arguments;
      if (listing is! CompanyTaskListing) {
        return const SuperAdminGate(
          child: SuperAdminTaskListsScreen(),
        );
      }
      return SuperAdminGate(
        child: SuperAdminTaskDetailsScreen(listing: listing),
      );
    case AppRoutes.superAdminUsers:
      return const SuperAdminGate(
        child: SuperAdminUsersScreen(),
      );
    case AppRoutes.superAdminRequests:
      final args = settings.arguments;
      String? focusType;
      String? focusId;
      if (args is Map) {
        focusType = args['type']?.toString();
        focusId = args['id']?.toString();
      }
      return AdminOrSuperAdminGate(
        child: SuperAdminRequestsScreen(
          focusRequestType: focusType,
          focusRequestId: focusId,
        ),
      );
    case AppRoutes.superAdminLogs:
      return const SuperAdminGate(
        child: NotificationsScreen(),
      );
    case AppRoutes.superAdminAnnouncements:
      return const SuperAdminGate(
        child: SuperAdminAnnouncementsScreen(),
      );
    case AppRoutes.superAdminTimeCardDetails:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardDetailsScreen(),
      );
    case AppRoutes.superAdminTimeCardSettings:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardSettingsScreen(),
      );
    case AppRoutes.profile:
      return const ProfileScreen();
    case AppRoutes.settings:
      return const SettingsScreen();
    case AppRoutes.dashboard:
    case AppRoutes.home:
    case AppRoutes.userDashboard:
    case AppRoutes.employeeDashboard:
    default:
      return const RoleDashboardScreen();
  }
}
