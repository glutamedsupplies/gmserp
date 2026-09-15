import '../models/company_model.dart';
import '../models/employee_day_schedule_override.dart';
import '../models/user_model.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class EmployeeDayScheduleOverrideRepository {
  EmployeeDayScheduleOverrideRepository({RtdbService? rtdb})
    : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.timeCardDayOverrides;

  String _path(String id) => '${RtdbPaths.timeCardDayOverrides}/$id';

  Future<List<EmployeeDayScheduleOverride>> _loadAll() async {
    try {
      final children = await _rtdb.getChildren(RtdbPaths.timeCardDayOverrides);
      return children.entries
          .map(
            (entry) => EmployeeDayScheduleOverride.fromFirestore(
              id: entry.key,
              data: entry.value,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<EmployeeDayScheduleOverride>> listByCompanyId(
    String companyId, {
    String? companyDocumentId,
  }) async {
    final docId = companyDocumentId?.trim() ?? '';
    return (await _loadAll())
        .where(
          (item) =>
              item.companyId == companyId ||
              item.companyDocumentId == companyId ||
              (docId.isNotEmpty &&
                  (item.companyId == docId || item.companyDocumentId == docId)),
        )
        .toList();
  }

  Future<List<EmployeeDayScheduleOverride>> listForUserCompany({
    required String userId,
    required String companyId,
    String? companyDocumentId,
  }) async {
    final docId = companyDocumentId?.trim() ?? '';
    return (await _loadAll())
        .where(
          (item) =>
              item.userId == userId &&
              (item.companyId == companyId ||
                  item.companyDocumentId == companyId ||
                  (docId.isNotEmpty &&
                      (item.companyId == docId ||
                          item.companyDocumentId == docId))),
        )
        .toList();
  }

  Future<EmployeeDayScheduleOverride?> findForUserDate({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    required String workDate,
  }) async {
    final items = await listForUserCompany(
      userId: userId,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
    );
    for (final item in items) {
      if (item.workDate == workDate) return item;
    }
    return null;
  }

  Future<void> setDayOff({
    required UserModel actor,
    required CompanyModel company,
    required String employeeId,
    required String workDate,
    required bool dayOff,
    bool emergencyLeave = false,
    bool regularWorkDay = false,
    String note = '',
  }) async {
    if (regularWorkDay && (dayOff || emergencyLeave)) {
      throw StateError('Choose only one attendance status.');
    }
    if (emergencyLeave && note.trim().isEmpty) {
      throw StateError('A note is required for emergency leave.');
    }
    if (emergencyLeave && dayOff) {
      throw StateError('Choose either day off or emergency leave.');
    }
    final existing = await findForUserDate(
      userId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
    );

    if (!dayOff && !emergencyLeave && !regularWorkDay) {
      if (existing != null) {
        await _rtdb.remove(_path(existing.id));
      }
      return;
    }

    final id = existing?.id ?? _rtdb.newKey(RtdbPaths.timeCardDayOverrides);
    final actorName = actor.username.trim().isNotEmpty
        ? actor.username.trim()
        : actor.email;
    final data = EmployeeDayScheduleOverride(
      id: id,
      userId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
      isDayOff: dayOff,
      isRegularWorkDay: regularWorkDay,
      isEmergencyLeave: emergencyLeave,
      note: emergencyLeave ? note.trim() : '',
      setById: actor.id,
      setByName: actorName,
      createdAt: existing?.createdAt,
    ).toFirestore();

    await _rtdb.set(_path(id), data);
  }
}
