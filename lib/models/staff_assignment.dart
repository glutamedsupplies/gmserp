import 'company_model.dart';
import 'employee_time_card_profile.dart';

class StaffMembershipListing {
  final String? companyDocumentId;
  final CompanyModel company;
  final StaffAssignment assignment;

  const StaffMembershipListing({
    this.companyDocumentId,
    required this.company,
    required this.assignment,
  });

  String get firestoreCompanyId {
    try {
      final doc = companyDocumentId;
      if (doc != null && doc.isNotEmpty) return doc;
    } catch (_) {}
    return company.firestoreId;
  }
}

class StaffAssignment {
  final String userId;
  final String username;
  final String email;
  final String? _roleId;
  final String jobRole;
  final List<String> tasks;
  final EmployeeTimeCardProfile? _timeCardProfile;

  String get roleId => _roleId ?? '';

  /// Per-employee rate + schedule. Falls back to defaults after hot reload or
  /// when older staff records have no saved profile yet.
  EmployeeTimeCardProfile get timeCardProfile =>
      _timeCardProfile ?? EmployeeTimeCardProfile.defaults();

  /// Legacy single-line summary for older screens and search.
  String get task => tasks.join(', ');

  StaffAssignment({
    required this.userId,
    required this.username,
    required this.email,
    String roleId = '',
    required this.jobRole,
    this.tasks = const [],
    EmployeeTimeCardProfile? timeCardProfile,
  }) : _roleId = roleId,
       _timeCardProfile = timeCardProfile;

  factory StaffAssignment.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final storedUserId = data['userId']?.toString().trim() ?? '';
    return StaffAssignment(
      userId: storedUserId.isNotEmpty ? storedUserId : id,
      username: data['username']?.toString().trim() ?? '',
      email: data['email']?.toString().trim() ?? '',
      roleId: data['roleId']?.toString().trim() ?? '',
      jobRole: data['jobRole']?.toString().trim() ?? '',
      tasks: _tasksFromFirestore(data),
      timeCardProfile: EmployeeTimeCardProfile.fromStaffData(data),
    );
  }

  static List<String> _tasksFromFirestore(Map<String, dynamic> data) {
    final raw = data['tasks'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    }
    final single = data['task']?.toString().trim() ?? '';
    if (single.isEmpty) return [];
    return [single];
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'email': email,
      'roleId': roleId,
      'jobRole': jobRole,
      'tasks': tasks,
      if (tasks.length == 1) 'task': tasks.first,
    };
  }

  StaffAssignment copyWith({
    String? username,
    String? email,
    String? roleId,
    String? jobRole,
    List<String>? tasks,
    EmployeeTimeCardProfile? timeCardProfile,
  }) {
    return StaffAssignment(
      userId: userId,
      username: username ?? this.username,
      email: email ?? this.email,
      roleId: roleId ?? this.roleId,
      jobRole: jobRole ?? this.jobRole,
      tasks: tasks ?? this.tasks,
      timeCardProfile: timeCardProfile ?? this.timeCardProfile,
    );
  }
}
