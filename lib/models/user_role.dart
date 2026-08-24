enum UserRole {
  user,
  employee,
  admin,
  superAdmin;

  String get storageValue => name;

  String get label {
    if (this == UserRole.employee) return 'Employee';
    if (this == UserRole.admin) return 'Admin';
    if (this == UserRole.superAdmin) return 'Super Admin';
    return 'User';
  }

  static UserRole fromStorage(String? value) {
    switch (value) {
      case 'employee':
        return UserRole.employee;
      case 'admin':
        return UserRole.admin;
      case 'superAdmin':
        return UserRole.superAdmin;
      default:
        return UserRole.user;
    }
  }
}

class RolePolicy {
  RolePolicy._();

  static const String superAdminEmail = 'kianmaximo17@gmail.com';

  static UserRole resolve({
    required String email,
    UserRole? existing,
  }) {
    if (email.trim().toLowerCase() == superAdminEmail) {
      return UserRole.superAdmin;
    }
    return existing ?? UserRole.user;
  }

  static bool isSuperAdminEmail(String email) =>
      email.trim().toLowerCase() == superAdminEmail;

  /// Employee and admin accounts use company staff, tasks, and elevated navigation.
  static bool hasCompanyAccess(UserRole role) =>
      role == UserRole.employee || role == UserRole.admin;

  /// Demoting to user removes company tasks and staff membership.
  static bool clearsCompanyMembership({
    required UserRole previous,
    required UserRole next,
  }) {
    return hasCompanyAccess(previous) && next == UserRole.user;
  }
}
