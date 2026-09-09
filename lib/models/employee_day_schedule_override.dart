import '../core/utils/firebase_data.dart';

/// One-off schedule override for a specific employee work date.
///
/// Does not change the employee weekly schedule in time card settings.
class EmployeeDayScheduleOverride {
  final String id;
  final String userId;
  final String companyId;
  final String companyDocumentId;
  final String workDate;
  final bool isDayOff;
  final String setById;
  final String setByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EmployeeDayScheduleOverride({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.companyDocumentId,
    required this.workDate,
    this.isDayOff = true,
    this.setById = '',
    this.setByName = '',
    this.createdAt,
    this.updatedAt,
  });

  factory EmployeeDayScheduleOverride.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return EmployeeDayScheduleOverride(
      id: id,
      userId: data['userId']?.toString() ?? '',
      companyId: data['companyId']?.toString() ?? '',
      companyDocumentId: data['companyDocumentId']?.toString() ?? '',
      workDate: data['workDate']?.toString() ?? '',
      isDayOff: parseFirebaseBool(data['isDayOff'], true),
      setById: data['setById']?.toString() ?? '',
      setByName: data['setByName']?.toString() ?? '',
      createdAt: parseFirebaseDate(data['createdAt']),
      updatedAt: parseFirebaseDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'workDate': workDate,
      'isDayOff': isDayOff,
      'setById': setById,
      'setByName': setByName,
      'createdAt': createdAt != null
          ? writeFirebaseDate(createdAt!)
          : serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };
  }
}

bool isForcedEmployeeDayOff({
  required List<EmployeeDayScheduleOverride> overrides,
  required String userId,
  required String workDate,
}) {
  for (final override in overrides) {
    if (override.userId == userId &&
        override.workDate == workDate &&
        override.isDayOff) {
      return true;
    }
  }
  return false;
}

List<EmployeeDayScheduleOverride> overridesForUser({
  required List<EmployeeDayScheduleOverride> overrides,
  required String userId,
}) {
  return overrides.where((item) => item.userId == userId).toList();
}
