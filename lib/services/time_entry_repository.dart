import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_model.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';

class TimeEntryRepository {
  TimeEntryRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collectionName = 'timeEntries';

  CollectionReference<Map<String, dynamic>> get _entries =>
      _firestore.collection(collectionName);

  Future<TimeEntry?> getById(String entryId) async {
    if (entryId.isEmpty) return null;
    final snapshot = await _entries.doc(entryId).get();
    if (!snapshot.exists || snapshot.data() == null) return null;
    return TimeEntry.fromFirestore(id: snapshot.id, data: snapshot.data()!);
  }

  /// Finds the existing time card for an employee on a work date.
  /// Tries entry id, then companyId, then companyDocumentId, then user+date only.
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
      final snapshot = await _entries
          .where('userId', isEqualTo: userId)
          .where('companyDocumentId', isEqualTo: docId)
          .where('workDate', isEqualTo: workDate)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return TimeEntry.fromFirestore(id: doc.id, data: doc.data());
      }
    }

    final loose = await _entries
        .where('userId', isEqualTo: userId)
        .where('workDate', isEqualTo: workDate)
        .limit(5)
        .get();
    if (loose.docs.isEmpty) return null;

    for (final doc in loose.docs) {
      final data = doc.data();
      final entryCompanyId = data['companyId']?.toString() ?? '';
      final entryDocId = data['companyDocumentId']?.toString() ?? '';
      if (entryCompanyId == companyId ||
          (docId.isNotEmpty && entryDocId == docId)) {
        return TimeEntry.fromFirestore(id: doc.id, data: data);
      }
    }
    final fallback = loose.docs.first;
    return TimeEntry.fromFirestore(id: fallback.id, data: fallback.data());
  }

  Future<TimeEntry?> getOpenEntry({
    required String userId,
    required String companyId,
  }) async {
    final snapshot = await _entries
        .where('userId', isEqualTo: userId)
        .where('companyId', isEqualTo: companyId)
        .where('status', isEqualTo: TimeEntryStatus.open.storageValue)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return TimeEntry.fromFirestore(id: doc.id, data: doc.data());
  }

  Future<TimeEntry?> getEntryForWorkDate({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final entries = await listForWorkDate(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
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
    );
    if (todayEntry != null) {
      throw StateError(
        'You already recorded time in / time out for today. '
        'Only one session is allowed per day.',
      );
    }

    final data = <String, dynamic>{
      'userId': user.id,
      'userEmail': user.email,
      'username': user.username,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'status': TimeEntryStatus.open.storageValue,
      'timeIn': Timestamp.fromDate(now),
      'timeOut': null,
      'durationSeconds': null,
      'workDate': workDate,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final doc = await _entries.add(data);
    final snapshot = await doc.get();
    return TimeEntry.fromFirestore(
      id: snapshot.id,
      data: snapshot.data() ?? data,
    );
  }

  Future<TimeEntry> clockOut({required String entryId}) async {
    final ref = _entries.doc(entryId);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Time entry not found.');
    }

    final entry = TimeEntry.fromFirestore(
      id: snapshot.id,
      data: snapshot.data()!,
    );
    if (!entry.isOpen) {
      throw StateError('This time entry is already closed.');
    }

    final now = DateTime.now();
    final durationSeconds = now.difference(entry.timeIn).inSeconds;

    await ref.update({
      'status': TimeEntryStatus.closed.storageValue,
      'timeOut': Timestamp.fromDate(now),
      'durationSeconds': durationSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final updated = await ref.get();
    return TimeEntry.fromFirestore(
      id: updated.id,
      data: updated.data()!,
    );
  }

  Future<List<TimeEntry>> listForWorkDate({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final snapshot = await _entries
        .where('userId', isEqualTo: userId)
        .where('companyId', isEqualTo: companyId)
        .where('workDate', isEqualTo: workDate)
        .get();

    final entries = snapshot.docs
        .map((doc) => TimeEntry.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    entries.sort((a, b) => b.timeIn.compareTo(a.timeIn));
    return entries;
  }

  Future<List<TimeEntry>> listRecent({
    required String userId,
    required String companyId,
    int limit = 12,
  }) async {
    final entries = await listAllForCompany(
      userId: userId,
      companyId: companyId,
    );
    if (entries.length <= limit) return entries;
    return entries.take(limit).toList();
  }

  Future<List<TimeEntry>> listAllForCompany({
    required String userId,
    required String companyId,
  }) async {
    final snapshot = await _entries
        .where('userId', isEqualTo: userId)
        .where('companyId', isEqualTo: companyId)
        .get();

    final entries = snapshot.docs
        .map((doc) => TimeEntry.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    entries.sort((a, b) {
      final aDate = a.timeOut ?? a.timeIn;
      final bDate = b.timeOut ?? b.timeIn;
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  /// All time entries for every staff member in a company.
  /// Prefer [companyDocumentId] when available; falls back to business [companyId].
  Future<List<TimeEntry>> listByCompanyId(
    String companyId, {
    String? companyDocumentId,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    final docId = companyDocumentId?.trim() ?? '';
    if (docId.isNotEmpty) {
      snapshot =
          await _entries.where('companyDocumentId', isEqualTo: docId).get();
      if (snapshot.docs.isEmpty && docId != companyId) {
        snapshot =
            await _entries.where('companyId', isEqualTo: companyId).get();
      }
    } else {
      snapshot =
          await _entries.where('companyId', isEqualTo: companyId).get();
    }

    final entries = snapshot.docs
        .map((doc) => TimeEntry.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    entries.sort((a, b) {
      final byDate = b.workDate.compareTo(a.workDate);
      if (byDate != 0) return byDate;
      return b.timeIn.compareTo(a.timeIn);
    });
    return entries;
  }

  /// Apply an approved employee clock-in request (writes open time entry).
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
    final open = await getOpenEntry(userId: userId, companyId: companyId);
    if (open != null) {
      throw StateError('Employee already has an open time entry.');
    }
    final today = await getEntryForWorkDate(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    if (today != null) {
      throw StateError('Employee already has a time card for $workDate.');
    }

    final data = <String, dynamic>{
      'userId': userId,
      'userEmail': userEmail,
      'username': username,
      'companyId': companyId,
      'companyDocumentId': companyDocumentId,
      'companyName': companyName,
      'status': TimeEntryStatus.open.storageValue,
      'timeIn': Timestamp.fromDate(timeIn),
      'timeOut': null,
      'durationSeconds': null,
      'workDate': workDate,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final doc = await _entries.add(data);
    final snapshot = await doc.get();
    return TimeEntry.fromFirestore(
      id: snapshot.id,
      data: snapshot.data() ?? data,
    );
  }

  /// Apply an approved employee clock-out request.
  Future<TimeEntry> applyApprovedClockOut({
    required String entryId,
    required DateTime timeOut,
  }) async {
    final ref = _entries.doc(entryId);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Open time entry not found for clock-out.');
    }
    final entry = TimeEntry.fromFirestore(
      id: snapshot.id,
      data: snapshot.data()!,
    );
    if (!entry.isOpen) {
      throw StateError('Time entry is already closed.');
    }
    if (!timeOut.isAfter(entry.timeIn)) {
      throw StateError('Time out must be after time in.');
    }

    final durationSeconds = timeOut.difference(entry.timeIn).inSeconds;
    await ref.update({
      'status': TimeEntryStatus.closed.storageValue,
      'timeOut': Timestamp.fromDate(timeOut),
      'durationSeconds': durationSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await ref.get();
    return TimeEntry.fromFirestore(id: updated.id, data: updated.data()!);
  }

  /// Admin/super admin: create or update an employee's time in / time out.
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
      'timeIn': Timestamp.fromDate(timeIn),
      'timeOut': closed ? Timestamp.fromDate(timeOut) : null,
      'durationSeconds': durationSeconds,
      'workDate': workDate,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (entryId == null || entryId.isEmpty) {
      data['createdAt'] = FieldValue.serverTimestamp();
      final doc = await _entries.add(data);
      final snapshot = await doc.get();
      return TimeEntry.fromFirestore(
        id: snapshot.id,
        data: snapshot.data() ?? data,
      );
    }

    final ref = _entries.doc(entryId);
    final existing = await ref.get();
    if (!existing.exists) {
      throw StateError('Time entry not found.');
    }
    await ref.update(data);
    final updated = await ref.get();
    return TimeEntry.fromFirestore(
      id: updated.id,
      data: updated.data()!,
    );
  }

  Future<void> adminDeleteEntry(String entryId) async {
    await _entries.doc(entryId).delete();
  }
}
