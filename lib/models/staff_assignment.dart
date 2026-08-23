class StaffAssignment {
  final String userId;
  final String username;
  final String email;
  final String? _roleId;
  final String jobRole;
  final List<String> tasks;

  String get roleId => _roleId ?? '';

  /// Legacy single-line summary for older screens and search.
  String get task => tasks.join(', ');

  const StaffAssignment({
    required this.userId,
    required this.username,
    required this.email,
    String roleId = '',
    required this.jobRole,
    this.tasks = const [],
  }) : _roleId = roleId;

  factory StaffAssignment.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return StaffAssignment(
      userId: id,
      username: data['username']?.toString().trim() ?? '',
      email: data['email']?.toString().trim() ?? '',
      roleId: data['roleId']?.toString().trim() ?? '',
      jobRole: data['jobRole']?.toString().trim() ?? '',
      tasks: _tasksFromFirestore(data),
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
}
