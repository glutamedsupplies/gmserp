import '../models/time_card_profile_change.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class TimeCardProfileChangeRepository {
  TimeCardProfileChangeRepository({RtdbService? rtdb})
      : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.timeCardProfileChanges;

  Future<TimeCardProfileChange> create({
    required String companyId,
    required String companyDocumentId,
    required String companyName,
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String actorId,
    required String actorName,
    required double previousRate,
    required double newRate,
    required String previousScheduleSummary,
    required String newScheduleSummary,
    required List<String> recipientIds,
  }) async {
    final recipients = recipientIds.toSet().where((id) => id.isNotEmpty).toList()
      ..sort();
    final id = _rtdb.newKey(RtdbPaths.timeCardProfileChanges);
    final change = TimeCardProfileChange(
      id: id,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
      companyName: companyName,
      employeeId: employeeId,
      employeeName: employeeName,
      employeeEmail: employeeEmail,
      actorId: actorId,
      actorName: actorName,
      previousRate: previousRate,
      newRate: newRate,
      previousScheduleSummary: previousScheduleSummary,
      newScheduleSummary: newScheduleSummary,
      recipientIds: recipients,
      createdAt: DateTime.now(),
    );
    await _rtdb.set(
      '${RtdbPaths.timeCardProfileChanges}/$id',
      change.toFirestore(),
    );
    return change;
  }

  Future<List<TimeCardProfileChange>> listAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.timeCardProfileChanges);
    final items = children.entries
        .map(
          (entry) => TimeCardProfileChange.fromFirestore(
            id: entry.key,
            data: entry.value,
          ),
        )
        .toList();
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  Future<List<TimeCardProfileChange>> listForRecipient(String userId) async {
    final items = await listAll();
    return items
        .where((item) => item.recipientIds.contains(userId))
        .toList();
  }
}
