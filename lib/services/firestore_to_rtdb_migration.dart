import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/firebase_data.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

/// One-time copy of Firestore collections into Realtime Database.
/// Run while signed in as Super Admin (needs read on Firestore + write on RTDB).
class FirestoreToRtdbMigration {
  FirestoreToRtdbMigration({
    FirebaseFirestore? firestore,
    RtdbService? rtdb,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _rtdb = rtdb ?? RtdbService();

  final FirebaseFirestore _firestore;
  final RtdbService _rtdb;

  static const _flatCollections = [
    RtdbPaths.users,
    RtdbPaths.timeEntries,
    RtdbPaths.timeCardSettings,
    RtdbPaths.leaveRequests,
    RtdbPaths.clockRequests,
    RtdbPaths.timeCardChangeRequests,
    RtdbPaths.appConfig,
    RtdbPaths.salaryRateChanges,
    RtdbPaths.announcements,
  ];

  Future<String> run({void Function(String status)? onProgress}) async {
    final log = <String>[];
    var total = 0;

    void progress(String message) {
      log.add(message);
      onProgress?.call(message);
    }

    total += await _copyCompanies(progress);
    for (final name in _flatCollections) {
      total += await _copyCollection(name, progress);
    }

    final summary =
        'Migration finished. Copied $total top-level records (plus nested staff/tasks).';
    progress(summary);
    return summary;
  }

  Future<int> _copyCompanies(void Function(String) progress) async {
    final snapshot = await _firestore.collection(RtdbPaths.companies).get();
    if (snapshot.docs.isEmpty) {
      progress('companies: empty');
      return 0;
    }

    for (final doc in snapshot.docs) {
      final companyData = _convertDoc(doc.data());
      await _rtdb.set('${RtdbPaths.companies}/${doc.id}', companyData);

      final staffSnap = await doc.reference.collection('staff').get();
      for (final staffDoc in staffSnap.docs) {
        await _rtdb.set(
          '${RtdbPaths.companies}/${doc.id}/staff/${staffDoc.id}',
          _convertDoc(staffDoc.data()),
        );
      }

      final tasksSnap = await doc.reference.collection('tasks').get();
      for (final taskDoc in tasksSnap.docs) {
        await _rtdb.set(
          '${RtdbPaths.companies}/${doc.id}/tasks/${taskDoc.id}',
          _convertDoc(taskDoc.data()),
        );
      }

      progress(
        'company ${doc.id}: staff=${staffSnap.size}, tasks=${tasksSnap.size}',
      );
    }

    progress('companies: ${snapshot.size}');
    return snapshot.size;
  }

  Future<int> _copyCollection(
    String name,
    void Function(String) progress,
  ) async {
    final snapshot = await _firestore.collection(name).get();
    if (snapshot.docs.isEmpty) {
      progress('$name: empty');
      return 0;
    }

    for (final doc in snapshot.docs) {
      await _rtdb.set('$name/${doc.id}', _convertDoc(doc.data()));
    }
    progress('$name: ${snapshot.size}');
    return snapshot.size;
  }

  Map<String, dynamic> _convertDoc(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      final converted = _convertValue(entry.value);
      if (converted == null && entry.value != null) continue;
      out[entry.key] = converted;
    }

    final recipients = out['recipientIds'];
    if (recipients is List) {
      out['recipientIds'] = recipientIdsToMap(
        recipients.map((e) => e.toString()).toList(),
      );
    }

    final week = out['timeCardWeek'];
    if (week is Map) {
      out['timeCardWeek'] = _normalizeTimeCardWeek(week);
    }
    return out;
  }

  /// Avoid RTDB array coercion on weekday keys `1`…`7`.
  Map<String, dynamic> _normalizeTimeCardWeek(Map week) {
    const labels = {
      '1': 'd1',
      '2': 'd2',
      '3': 'd3',
      '4': 'd4',
      '5': 'd5',
      '6': 'd6',
      '7': 'd7',
      'd1': 'd1',
      'd2': 'd2',
      'd3': 'd3',
      'd4': 'd4',
      'd5': 'd5',
      'd6': 'd6',
      'd7': 'd7',
    };
    final out = <String, dynamic>{};
    for (final entry in week.entries) {
      final key = entry.key.toString();
      final mapped = labels[key];
      if (mapped == null) continue;
      out[mapped] = _convertValue(entry.value);
    }
    return out;
  }

  dynamic _convertValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return writeFirebaseDate(value);
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DocumentReference) return value.path;
    if (value is List) return value.map(_convertValue).toList();
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        map[entry.key.toString()] = _convertValue(entry.value);
      }
      return map;
    }
    return value;
  }
}
