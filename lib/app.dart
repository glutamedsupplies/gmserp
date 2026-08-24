import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
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
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/company/select_company_screen.dart';
import 'screens/dashboard/admin_dashboard_screen.dart';
import 'screens/dashboard/admin_submitted_requests_screen.dart';
import 'screens/dashboard/employee_request_leave_screen.dart';
import 'screens/dashboard/employee_time_card_details_screen.dart';
import 'screens/dashboard/employee_time_in_out_screen.dart';
import 'screens/dashboard/profile_screen.dart';
import 'screens/dashboard/role_dashboard_screen.dart';
import 'screens/dashboard/settings_screen.dart';
import 'screens/dashboard/super_admin_company_users_screen.dart';
import 'screens/dashboard/super_admin_dashboard_screen.dart';
import 'screens/dashboard/super_admin_employee_lists_screen.dart';
import 'screens/dashboard/super_admin_role_details_screen.dart';
import 'screens/dashboard/super_admin_role_lists_screen.dart';
import 'screens/dashboard/super_admin_requests_screen.dart';
import 'screens/dashboard/super_admin_task_details_screen.dart';
import 'screens/dashboard/super_admin_task_lists_screen.dart';
import 'screens/dashboard/super_admin_time_card_details_screen.dart';
import 'screens/dashboard/super_admin_edit_time_card_screen.dart';
import 'screens/dashboard/super_admin_time_card_settings_screen.dart';
import 'screens/dashboard/super_admin_users_screen.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _timeEntries = TimeEntryProvider();
  final _timeCardSettings = TimeCardSettingsProvider();
  late final PendingRequestsProvider _pendingRequests;

  @override
  void dispose() {
    _timeEntries.dispose();
    _timeCardSettings.dispose();
    _pendingRequests.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pendingRequests = PendingRequestsProvider(
      notificationsEnabled: () =>
          context.read<SettingsProvider>().notificationsEnabled,
    );
    _timeCardSettings.load();
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
        }
      }
      if (!mounted) return;
      _pendingRequests.syncUser(auth.user);
    });
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
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 280),
        themeAnimationCurve: Curves.easeOutCubic,
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

    if (auth.isInitializing) {
      return Scaffold(
        backgroundColor: AppColors.of(context).background,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (auth.isAuthenticated && auth.user != null) {
      switch (PostLoginNavigation.routeFor(auth.user!)) {
        case AppRoutes.selectCompany:
          final companies = context.watch<CompanyProvider>();
          if (companies.selectedCompany != null && !companies.isPickingCompany) {
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
      return const AdminOrSuperAdminGate(
        child: AdminSubmittedRequestsScreen(),
      );
    case AppRoutes.employeeTimeInOut:
      return const EmployeeTimeInOutScreen();
    case AppRoutes.employeeTimeCardDetails:
      return const EmployeeTimeCardDetailsScreen();
    case AppRoutes.employeeRequestLeave:
      return const EmployeeRequestLeaveScreen();
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
      return const SuperAdminGate(
        child: SuperAdminRequestsScreen(),
      );
    case AppRoutes.superAdminTimeCardDetails:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardDetailsScreen(),
      );
    case AppRoutes.superAdminTimeCardSettings:
      return const AdminOrSuperAdminGate(
        child: SuperAdminTimeCardSettingsScreen(),
      );
    case AppRoutes.superAdminEditTimeCard:
      return const AdminOrSuperAdminGate(
        child: SuperAdminEditTimeCardScreen(),
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
