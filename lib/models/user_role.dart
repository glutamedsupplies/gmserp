enum UserRole {
  user,
  employee,
  admin,
  superAdmin;

  String get storageValue => name;

  String get label {
    switch (this) {
      case UserRole.user:
        return 'User';
      case UserRole.employee:
        return 'Employee';
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Super Admin';
    }
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
}
