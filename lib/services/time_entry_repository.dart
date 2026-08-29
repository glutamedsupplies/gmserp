import '../core/utils/firebase_data.dart';
import '../models/company_model.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'rtdb/rtdb_paths.dart';
import 'rtdb/rtdb_service.dart';

class TimeEntryRepository {
  TimeEntryRepository({RtdbService? rtdb}) : _rtdb = rtdb ?? RtdbService();

  final RtdbService _rtdb;

  static const String collectionName = RtdbPaths.timeEntries;

  String _entryPath(String entryId) => '${RtdbPaths.timeEntries}/$entryId';

  Future<List<TimeEntry>> _loadAll() async {
    final children = await _rtdb.getChildren(RtdbPaths.timeEntries);
    return children.entries
        .map(
          (entry) =>
              TimeEntry.fromFirestore(id: entry.key, data: entry.value),
        )
        .toList();
  }

  Future<TimeEntry?> getById(String entryId) async {
    if (entryId.isEmpty) return null;
    final data = await _rtdb.getMap(_entryPath(entryId));
    if (data == null) return null;
    return TimeEntry.fromFirestore(id: entryId, data: data);
  }

  Future<TimeEntry?> findPriorEntry({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    required String workDate,
    String? entryId,
  }) async {
    if (entryId != null && entryId.trim().isNotEmpty) {
      final byId = await getById(entryId.trim());
      if (byId != null) return byId;
    }

    final byCompanyId = await getEntryForWorkDate(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    if (byCompanyId != null) return byCompanyId;

    final docId = companyDocumentId?.trim() ?? '';
    if (docId.isNotEmpty && docId != companyId) {
      final all = await _loadAll();
      for (final entry in all) {
        if (entry.userId == userId &&
            entry.companyDocumentId == docId &&
            entry.workDate == workDate) {
          return entry;
        }
      }
    }

    final loose = (await _loadAll())
        .where((entry) => entry.userId == userId && entry.workDate == workDate)
        .take(5)
        .toList();
    if (loose.isEmpty) return null;

    for (final entry in loose) {
      if (matchesCompanyRef(
        storedCompanyId: entry.companyId,
        storedDocumentId: entry.companyDocumentId,
        companyId: companyId,
        companyDocumentId: docId.isEmpty ? null : docId,
      )) {
        return entry;
      }
    }
    // Never fall back across companies for multi-company users.
    return null;
  }

  Future<TimeEntry?> getOpenEntry({
    required String userId,
    required String companyId,
    String? companyDocumentId,
  }) async {
    final all = await _loadAll();
    for (final entry in all) {
      if (entry.userId == userId &&
          entry.status == TimeEntryStatus.open &&
          matchesCompanyRef(
            storedCompanyId: entry.companyId,
            storedDocumentId: entry.companyDocumentId,
            companyId: companyId,
            companyDocumentId: companyDocumentId,
          )) {
        return entry;
      }
    }
    return null;
  }

  Future<TimeEntry?> getEntryForWorkDate({
    required String userId,
    required String companyId,
    required String workDate,
    String? companyDocumentId,
  }) async {
    final entries = await listForWorkDate(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
      companyDocumentId: companyDocumentId,
    );
    if (entries.isEmpty) return null;
    return entries.first;
  }

  Future<TimeEntry> clockIn({
    required UserModel user,
    required CompanyModel company,
  }) async {
    final existing = await getOpenEntry(
      userId: user.id,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
    );
    if (existing != null) {
      throw StateError('You are already clocked in for this company.');
    }

    final now = DateTime.now();
    final workDate = formatWorkDate(now);
    final todayEntry = await getEntryForWorkDate(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
      companyDocumentId: company.firestoreId,
    );
    if (todayEntry != null) {
      throw StateError(
        'You already recorded time in / time out for today. '
        'Only one session is allowed per day.',
      );
    }

    final id = _rtdb.newKey(RtdbPaths.timeEntries);
    final data = <String, dynamic>{
      'userId': user.id,
      'userEmail': user.email,
      'username': user.username,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'status': TimeEntryStatus.open.storageValue,
      'timeIn': writeFirebaseDate(now),
      'timeOut': null,
      'durationSeconds': null,
      'workDate': workDate,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };

    await _rtdb.set(_entryPath(id), data);
    return TimeEntry.fromFirestore(id: id, data: data);
  }

  Future<TimeEntry> clockOut({required String entryId}) async {
    final path = _entryPath(entryId);
    final data = await _rtdb.getMap(path);
    if (data == null) {
      throw StateError('Time entry not found.');
    }

    final entry = TimeEntry.fromFirestore(id: entryId, data: data);
    if (!entry.isOpen) {
      throw StateError('This time entry is already closed.');
    }

    final now = DateTime.now();
    final durationSeconds = now.difference(entry.timeIn).inSeconds;

    final update = <String, dynamic>{
      'status': TimeEntryStatus.closed.storageValue,
      'timeOut': writeFirebaseDate(now),
      'durationSeconds': durationSeconds,
      'updatedAt': serverTimestamp(),
    };
    await _rtdb.merge(path, update);

    return TimeEntry.fromFirestore(
      id: entryId,
      data: {...data, ...update},
    );
  }

  Future<List<TimeEntry>> listForWorkDate({
    required String userId,
    required String companyId,
    required String workDate,
    String? companyDocumentId,
  }) async {
    final entries = (await _loadAll())
        .where(
          (entry) =>
              entry.userId == userId &&
              entry.workDate == workDate &&
              matchesCompanyRef(
                storedCompanyId: entry.companyId,
                storedDocumentId: entry.companyDocumentId,
                companyId: companyId,
                companyDocumentId: companyDocumentId,
              ),
        )
        .toList();
    entries.sort((a, b) => b.timeIn.compareTo(a.timeIn));
    return entries;
  }

  Future<List<TimeEntry>> listRecent({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    int limit = 12,
  }) async {
    final entries = await listAllForCompany(
      userId: userId,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
    );
    if (entries.length <= limit) return entries;
    return entries.take(limit).toList();
  }

  Future<List<TimeEntry>> listAllForCompany({
    required String userId,
    required String companyId,
    String? companyDocumentId,
  }) async {
    final entries = (await _loadAll())
        .where(
          (entry) =>
              entry.userId == userId &&
              matchesCompanyRef(
                storedCompanyId: entry.companyId,
                storedDocumentId: entry.companyDocumentId,
                companyId: companyId,
                companyDocumentId: companyDocumentId,
              ),
        )
        .toList();
    entries.sort((a, b) {
      final aDate = a.timeOut ?? a.timeIn;
      final bDate = b.timeOut ?? b.timeIn;
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  Future<List<TimeEntry>> listByCompanyId(
    String companyId, {
    String? companyDocumentId,
  }) async {
    final entries = (await _loadAll())
        .where(
          (entry) => matchesCompanyRef(
            storedCompanyId: entry.companyId,
            storedDocumentId: entry.companyDocumentId,
            companyId: companyId,
            companyDocumentId: companyDocumentId,
          ),
        )
        .toList();

    entries.sort((a, b) {
      final byDate = b.workDate.compareTo(a.workDate);
      if (byDate != 0) return byDate;
      return b.timeIn.compareTo(a.timeIn);
    });
    return entries;
  }

  /// Closes an open session from another work date so a backdated clock-in
  /// approval can still be saved (e.g. Monday pending, Tuesday already open).
  Future<void> releaseConflictingOpenEntry({
    required String userId,
    required String companyId,
    String? companyDocumentId,
    required String targetWorkDate,
  }) async {
    final open = await getOpenEntry(
      userId: userId,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
    );
    if (open == null) return;
    if (open.workDate == targetWorkDate) {
      throw StateError(
        'Employee already has an open time entry for $targetWorkDate.',
      );
    }

    final closeAt = open.timeIn.add(const Duration(seconds: 1));
    await applyApprovedClockOut(entryId: open.id, timeOut: closeAt);
  }

  Future<TimeEntry> applyApprovedClockIn({
    required String userId,
    required String userEmail,
    required String username,
    required String companyId,
    required String companyDocumentId,
    required String companyName,
    required String workDate,
    required DateTime timeIn,
  }) async {
    await releaseConflictingOpenEntry(
      userId: userId,
      companyId: companyId,
      companyDocumentId: companyDocumentId,
      targetWorkDate: workDate,
    );
    final today = await getEntryForWorkDate(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
      companyDocumentId: companyDocumentId,
    );
    if (today != null) {
      throw StateError('Employee already has a time card for $workDate.');
    }

    final id = _rtdb.newKey(RtdbPaths.timeEntries);
    final data = <String, dynamic>{
      'userId': userId,
      'userEmail': userEmail,
      'username': username,
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'status': TimeEntryStatus.open.storageValue,
      'timeIn': writeFirebaseDate(timeIn),
      'timeOut': null,
      'durationSeconds': null,
      'workDate': workDate,
      'createdAt': serverTimestamp(),
      'updatedAt': serverTimestamp(),
    };
    await _rtdb.set(_entryPath(id), data);
    return TimeEntry.fromFirestore(id: id, data: data);
  }

  Future<TimeEntry> applyApprovedClockOut({
    required String entryId,
    required DateTime timeOut,
  }) async {
    final path = _entryPath(entryId);
    final data = await _rtdb.getMap(path);
    if (data == null) {
      throw StateError('Open time entry not found for clock-out.');
    }
    final entry = TimeEntry.fromFirestore(id: entryId, data: data);
    if (!entry.isOpen) {
      throw StateError('Time entry is already closed.');
    }
    if (!timeOut.isAfter(entry.timeIn)) {
      throw StateError('Time out must be after time in.');
    }

    final durationSeconds = timeOut.difference(entry.timeIn).inSeconds;
    final update = <String, dynamic>{
      'status': TimeEntryStatus.closed.storageValue,
      'timeOut': writeFirebaseDate(timeOut),
      'durationSeconds': durationSeconds,
      'updatedAt': serverTimestamp(),
    };
    await _rtdb.merge(path, update);
    return TimeEntry.fromFirestore(id: entryId, data: {...data, ...update});
  }

  Future<TimeEntry> adminSaveEntry({
    String? entryId,
    required String userId,
    required String userEmail,
    required String username,
    required CompanyModel company,
    required DateTime timeIn,
    DateTime? timeOut,
  }) async {
    if (timeOut != null && !timeOut.isAfter(timeIn)) {
      throw StateError('Time out must be after time in.');
    }

    final workDate = formatWorkDate(timeIn);
    final existingSameDay = await getEntryForWorkDate(
      userId: userId,
      companyId: company.id,
      workDate: workDate,
    );
    if (existingSameDay != null && existingSameDay.id != entryId) {
      throw StateError(
        'This employee already has a time card for $workDate. '
        'Edit the existing record instead.',
      );
    }

    final closed = timeOut != null;
    final durationSeconds = timeOut?.difference(timeIn).inSeconds;

    final data = <String, dynamic>{
      'userId': userId,
      'userEmail': userEmail,
      'username': username,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'status': closed
          ? TimeEntryStatus.closed.storageValue
          : TimeEntryStatus.open.storageValue,
      'timeIn': writeFirebaseDate(timeIn),
      'timeOut': closed ? writeFirebaseDate(timeOut) : null,
      'durationSeconds': durationSeconds,
      'workDate': workDate,
      'updatedAt': serverTimestamp(),
    };

    if (entryId == null || entryId.isEmpty) {
      final id = _rtdb.newKey(RtdbPaths.timeEntries);
      data['createdAt'] = serverTimestamp();
      await _rtdb.set(_entryPath(id), data);
      return TimeEntry.fromFirestore(id: id, data: data);
    }

    final path = _entryPath(entryId);
    final existing = await _rtdb.getMap(path);
    if (existing == null) {
      throw StateError('Time entry not found.');
    }
    await _rtdb.merge(path, data);
    return TimeEntry.fromFirestore(id: entryId, data: {...existing, ...data});
  }

  Future<void> adminDeleteEntry(String entryId) async {
    await _rtdb.remove(_entryPath(entryId));
  }
}
