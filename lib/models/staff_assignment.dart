class StaffAssignment {
  final String userId;
  final String username;
  final String email;
  final String jobRole;
  final String task;

  const StaffAssignment({
    required this.userId,
    required this.username,
    required this.email,
    required this.jobRole,
    required this.task,
  });

  factory StaffAssignment.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return StaffAssignment(
      userId: id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      jobRole: data['jobRole'] as String? ?? '',
      task: data['task'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'email': email,
      'jobRole': jobRole,
      'task': task,
    };
  }
}
