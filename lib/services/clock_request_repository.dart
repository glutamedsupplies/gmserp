import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/clock_request.dart';
import '../models/company_model.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'time_entry_repository.dart';

class ClockRequestRepository {
  ClockRequestRepository({
    FirebaseFirestore? firestore,
    TimeEntryRepository? timeEntries,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _timeEntries = timeEntries ?? TimeEntryRepository();

  final FirebaseFirestore _firestore;
  final TimeEntryRepository _timeEntries;

  static const String collectionName = 'clockRequests';

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(collectionName);

  Future<List<ClockRequest>> listAll() async {
    final snapshot = await _requests.get();
    return _sorted(snapshot.docs);
  }

  Future<List<ClockRequest>> listPending() async {
    final snapshot =
        await _requests.where('status', isEqualTo: 'pending').get();
    return _sorted(snapshot.docs);
  }

  Future<List<ClockRequest>> listForUserCompany({
    required String userId,
    required String companyId,
    String? workDate,
  }) async {
    final snapshot = await _requests
        .where('userId', isEqualTo: userId)
        .where('companyId', isEqualTo: companyId)
        .get();
    var items = _sorted(snapshot.docs);
    if (workDate != null && workDate.isNotEmpty) {
      items = items.where((r) => r.workDate == workDate).toList();
    }
    return items;
  }

  Future<ClockRequest?> findPendingClockIn({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final items = await listForUserCompany(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    for (final item in items) {
      if (item.isPending && item.isClockIn) return item;
    }
    return null;
  }

  Future<ClockRequest?> findPendingClockOut({
    required String userId,
    required String companyId,
    required String workDate,
  }) async {
    final items = await listForUserCompany(
      userId: userId,
      companyId: companyId,
      workDate: workDate,
    );
    for (final item in items) {
      if (item.isPending && item.isClockOut) return item;
    }
    return null;
  }

  Future<ClockRequest> submitClockIn({
    required UserModel user,
    required CompanyModel company,
    DateTime? requestedAt,
  }) async {
    final at = requestedAt ?? DateTime.now();
    final workDate = formatWorkDate(at);

    final open = await _timeEntries.getOpenEntry(
      userId: user.id,
      companyId: company.id,
    );
    if (open != null) {
      throw StateError('You already have an open time entry.');
    }

    final today = await _timeEntries.getEntryForWorkDate(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
    );
    if (today != null) {
      throw StateError(
        'You already have a time card for today. '
        'Only one session is allowed per day.',
      );
    }

    final pendingIn = await findPendingClockIn(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
    );
    if (pendingIn != null) {
      throw StateError(
        'You already have a pending time-in request for today '
        '(${pendingIn.requestedAtLabel}).',
      );
    }

    final data = <String, dynamic>{
      'type': ClockRequest.typeClockIn,
      'status': 'pending',
      'userId': user.id,
      'username': user.username,
      'userEmail': user.email,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'requestedAt': Timestamp.fromDate(at),
      'entryId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final doc = await _requests.add(data);
    final snapshot = await doc.get();
    return ClockRequest.fromFirestore(
      id: snapshot.id,
      data: snapshot.data() ?? data,
    );
  }

  Future<ClockRequest> submitClockOut({
    required UserModel user,
    required CompanyModel company,
    required String entryId,
    DateTime? requestedAt,
  }) async {
    final at = requestedAt ?? DateTime.now();
    final workDate = formatWorkDate(at);

    final entry = await _timeEntries.getById(entryId);
    if (entry == null || !entry.isOpen) {
      throw StateError(
        'No open time entry to clock out. Wait for your time-in to be approved.',
      );
    }
    if (entry.userId != user.id) {
      throw StateError('This time entry does not belong to you.');
    }

    final pendingOut = await findPendingClockOut(
      userId: user.id,
      companyId: company.id,
      workDate: workDate,
    );
    if (pendingOut != null) {
      throw StateError(
        'You already have a pending time-out request '
        '(${pendingOut.requestedAtLabel}).',
      );
    }

    final data = <String, dynamic>{
      'type': ClockRequest.typeClockOut,
      'status': 'pending',
      'userId': user.id,
      'username': user.username,
      'userEmail': user.email,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'requestedAt': Timestamp.fromDate(at),
      'entryId': entryId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final doc = await _requests.add(data);
    final snapshot = await doc.get();
    return ClockRequest.fromFirestore(
      id: snapshot.id,
      data: snapshot.data() ?? data,
    );
  }

  Future<void> reject(String requestId) async {
    await _requests.doc(requestId).update({
      'status': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> approve(ClockRequest request) async {
    if (!request.isPending) {
      throw StateError('This request is no longer pending.');
    }

    if (request.isClockIn) {
      await _timeEntries.applyApprovedClockIn(
        userId: request.userId,
        userEmail: request.userEmail,
        username: request.username,
        companyId: request.companyId,
        companyDocumentId: request.companyDocumentId,
        companyName: request.companyName,
        workDate: request.workDate,
        timeIn: request.requestedAt,
      );
    } else {
      final entryId = request.entryId?.trim() ?? '';
      if (entryId.isEmpty) {
        throw StateError('Time-out request is missing the open entry id.');
      }
      await _timeEntries.applyApprovedClockOut(
        entryId: entryId,
        timeOut: request.requestedAt,
      );
    }

    await _requests.doc(request.id).update({
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<ClockRequest> _sorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs
        .map((doc) => ClockRequest.fromFirestore(id: doc.id, data: doc.data()))
        .toList();
    items.sort((a, b) {
      final byCreated = (b.createdAt ?? b.requestedAt)
          .compareTo(a.createdAt ?? a.requestedAt);
      if (byCreated != 0) return byCreated;
      return b.requestedAt.compareTo(a.requestedAt);
    });
    return items;
  }
}
