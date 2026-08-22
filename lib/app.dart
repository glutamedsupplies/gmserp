import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/constants/app_routes.dart';
import 'core/navigation/post_login.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/company/select_company_screen.dart';
import 'screens/dashboard/admin_dashboard_screen.dart';
import 'screens/dashboard/profile_screen.dart';
import 'screens/dashboard/role_dashboard_screen.dart';
import 'screens/dashboard/super_admin_dashboard_screen.dart';
import 'screens/dashboard/super_admin_users_screen.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().checkAuthentication();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _AuthGate(),
      routes: {
        AppRoutes.login: (_) => const LoginScreen(),
        AppRoutes.register: (_) => const RegisterScreen(),
        AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
        AppRoutes.home: (_) => const RoleDashboardScreen(),
        AppRoutes.dashboard: (_) => const RoleDashboardScreen(),
        AppRoutes.userDashboard: (_) => const RoleDashboardScreen(),
        AppRoutes.selectCompany: (_) => const SelectCompanyScreen(),
        AppRoutes.employeeDashboard: (_) => const RoleDashboardScreen(),
        AppRoutes.adminDashboard: (_) => const AdminDashboardScreen(),
        AppRoutes.superAdmin: (_) => const SuperAdminDashboardScreen(),
        AppRoutes.superAdminUsers: (_) => const SuperAdminUsersScreen(),
        AppRoutes.profile: (_) => const ProfileScreen(),
      },
      onUnknownRoute: (_) => MaterialPageRoute(
        builder: (_) => const LoginScreen(),
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
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (auth.isAuthenticated && auth.user != null) {
      switch (PostLoginNavigation.routeFor(auth.user!)) {
        case AppRoutes.selectCompany:
          return const SelectCompanyScreen();
        default:
          return const RoleDashboardScreen();
      }
    }

    return const LoginScreen();
  }
}
