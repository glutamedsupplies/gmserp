import '../../models/user_model.dart';
import '../../models/user_role.dart';
import '../constants/app_routes.dart';

class PostLoginNavigation {
  PostLoginNavigation._();

  /// First screen after account login.
  static String routeFor(UserModel user) {
    switch (user.role) {
      case UserRole.superAdmin:
      case UserRole.user:
        return AppRoutes.dashboard;
      case UserRole.employee:
      case UserRole.admin:
        return AppRoutes.selectCompany;
    }
  }

  /// Dashboard after a company is unlocked.
  static String dashboardFor(UserRole role) {
    return AppRoutes.dashboard;
  }
}
