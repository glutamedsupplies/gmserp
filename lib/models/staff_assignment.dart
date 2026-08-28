import '../core/utils/firebase_data.dart';
import 'company_model.dart';
import 'employee_time_card_profile.dart';
import 'user_role.dart';

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

  /// Company-only access: `admin` or `employee`. Independent of other companies.
  final String accessLevel;

  /// Declined time in/out requests for this company. Locked at 3 until admin resets.
  final int clockDeclineCount;

  static const int clockDeclineLimit = 3;

  bool get isClockRequestLocked => clockDeclineCount >= clockDeclineLimit;

  String get roleId => _roleId ?? '';

  /// Per-employee rate + schedule. Falls back to defaults after hot reload or
  /// when older staff records have no saved profile yet.
  EmployeeTimeCardProfile get timeCardProfile =>
      _timeCardProfile ?? EmployeeTimeCardProfile.defaults();

  /// Legacy single-line summary for older screens and search.
  String get task => tasks.join(', ');

  /// Access for this company only. [fallback] used for older records with no
  /// stored access level (typically the account's global role).
  UserRole accessRole({UserRole? fallback}) {
    final stored = UserRole.fromStorage(accessLevel);
    if (stored == UserRole.admin || stored == UserRole.employee) {
      return stored;
    }
    if (fallback == UserRole.admin) return UserRole.admin;
    if (fallback == UserRole.employee) return UserRole.employee;
    return UserRole.employee;
  }

  bool get isCompanyAdmin => accessRole() == UserRole.admin;

  StaffAssignment({
    required this.userId,
    required this.username,
    required this.email,
    String this._roleId = '',
    required this.jobRole,
    this.tasks = const [],
    this.accessLevel = 'employee',
    this.clockDeclineCount = 0,
    EmployeeTimeCardProfile? timeCardProfile,
  }) : _timeCardProfile = timeCardProfile; // ignore: prefer_initializing_formals

  factory StaffAssignment.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final storedUserId = data['userId']?.toString().trim() ?? '';
    final rawAccess = data['accessLevel']?.toString().trim() ??
        data['memberLevel']?.toString().trim() ??
        '';
    return StaffAssignment(
      userId: storedUserId.isNotEmpty ? storedUserId : id,
      username: data['username']?.toString().trim() ?? '',
      email: data['email']?.toString().trim() ?? '',
      roleId: data['roleId']?.toString().trim() ?? '',
      jobRole: data['jobRole']?.toString().trim() ?? '',
      tasks: _tasksFromFirestore(data),
      accessLevel: rawAccess,
      clockDeclineCount: _intField(data['clockDeclineCount']),
      timeCardProfile: EmployeeTimeCardProfile.fromStaffData(data),
    );
  }

  static int _intField(dynamic value) => parseFirebaseInt(value);

  static List<String> _tasksFromFirestore(Map<String, dynamic> data) {
    final raw = data['tasks'];
    if (raw is List) {
      return [
        for (final item in raw)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    }
    if (raw is Map) {
      final values = <String>[];
      for (final entry in raw.entries) {
        final text = entry.value?.toString().trim() ?? '';
        if (text.isNotEmpty && text != 'true') {
          values.add(text);
        } else {
          final key = entry.key.toString().trim();
          if (key.isNotEmpty) values.add(key);
        }
      }
      return values;
    }
    final single = data['task']?.toString().trim() ?? '';
    if (single.isEmpty) return [];
    return [single];
  }

  Map<String, dynamic> toFirestore() {
    final access = accessRole().storageValue;
    return {
      'username': username,
      'email': email,
      'roleId': roleId,
      'jobRole': jobRole,
      'tasks': tasks,
      'accessLevel': access,
      'clockDeclineCount': clockDeclineCount,
      if (tasks.length == 1) 'task': tasks.first,
    };
  }

  StaffAssignment copyWith({
    String? username,
    String? email,
    String? roleId,
    String? jobRole,
    List<String>? tasks,
    String? accessLevel,
    int? clockDeclineCount,
    EmployeeTimeCardProfile? timeCardProfile,
  }) {
    return StaffAssignment(
      userId: userId,
      username: username ?? this.username,
      email: email ?? this.email,
      roleId: roleId ?? this.roleId,
      jobRole: jobRole ?? this.jobRole,
      tasks: tasks ?? this.tasks,
      accessLevel: accessLevel ?? this.accessLevel,
      clockDeclineCount: clockDeclineCount ?? this.clockDeclineCount,
      timeCardProfile: timeCardProfile ?? this.timeCardProfile,
    );
  }
}
