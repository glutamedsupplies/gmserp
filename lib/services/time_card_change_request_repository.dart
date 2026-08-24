import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/company_model.dart';
import '../models/time_card_change_request.dart';
import '../models/time_entry.dart';
import '../models/user_model.dart';
import 'time_entry_repository.dart';

class TimeCardChangeRequestRepository {
  TimeCardChangeRequestRepository({
    FirebaseFirestore? firestore,
    TimeEntryRepository? timeEntries,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _timeEntries = timeEntries ?? TimeEntryRepository();

  final FirebaseFirestore _firestore;
  final TimeEntryRepository _timeEntries;

  static const String collectionName = 'timeCardChangeRequests';

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(collectionName);

  Future<List<TimeCardChangeRequest>> listAll() async {
    final snapshot = await _requests.get();
    return _hydrateCurrents(_sorted(snapshot.docs));
  }

  Future<List<TimeCardChangeRequest>> listByRequester(String requesterId) async {
    final snapshot =
        await _requests.where('requesterId', isEqualTo: requesterId).get();
    return _hydrateCurrents(_sorted(snapshot.docs));
  }

  /// Live pending count for Super Admin inbox (all time-change requests).
  Stream<int> watchPendingCount() {
    return _requests.snapshots().map((snapshot) {
      var count = 0;
      for (final doc in snapshot.docs) {
        final status = doc.data()['status']?.toString().toLowerCase() ?? '';
        if (status == 'pending') count += 1;
      }
      return count;
    });
  }

  /// Returns a pending request for this employee/company/day, if any.
  Future<TimeCardChangeRequest?> findPendingForWorkDate({
    required String employeeId,
    required String companyId,
    String? companyDocumentId,
    required String workDate,
  }) async {
    final snapshot = await _requests
        .where('employeeId', isEqualTo: employeeId)
        .where('status', isEqualTo: 'pending')
        .get();

    final docId = companyDocumentId?.trim() ?? '';
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['workDate']?.toString() != workDate) continue;
      final entryCompanyId = data['companyId']?.toString() ?? '';
      final entryDocId = data['companyDocumentId']?.toString() ?? '';
      if (entryCompanyId == companyId ||
          (docId.isNotEmpty && entryDocId == docId) ||
          entryCompanyId.isEmpty) {
        return TimeCardChangeRequest.fromFirestore(id: doc.id, data: data);
      }
    }
    return null;
  }

  List<TimeCardChangeRequest> _sorted(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs
        .map(
          (doc) => TimeCardChangeRequest.fromFirestore(
            id: doc.id,
            data: doc.data(),
          ),
        )
        .toList();
    items.sort((a, b) {
      final byCreated = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byCreated != 0) return byCreated;
      return b.workDate.compareTo(a.workDate);
    });
    return items;
  }

  /// Fills missing "current" times for pending requests from the live entry.
  Future<List<TimeCardChangeRequest>> _hydrateCurrents(
    List<TimeCardChangeRequest> items,
  ) async {
    final result = <TimeCardChangeRequest>[];
    for (final item in items) {
      if (item.hasPriorRecord || !item.isPending) {
        result.add(item);
        continue;
      }

      TimeEntry? entry;
      final entryId = item.existingEntryId;
      if (entryId != null && entryId.isNotEmpty) {
        entry = await _timeEntries.getById(entryId);
      }
      entry ??= await _timeEntries.findPriorEntry(
        userId: item.employeeId,
        companyId: item.companyId,
        companyDocumentId: item.companyDocumentId,
        workDate: item.workDate,
        entryId: item.existingEntryId,
      );

      if (entry == null) {
        result.add(item);
        continue;
      }

      result.add(
        item.copyWith(
          currentTimeIn: entry.timeIn,
          currentTimeOut: entry.timeOut,
          currentTimeInText: formatClockTime(entry.timeIn),
          currentTimeOutText: entry.timeOut == null
              ? 'Open'
              : formatClockTime(entry.timeOut!),
        ),
      );
    }
    return result;
  }

  Future<TimeCardChangeRequest> submit({
    required UserModel requester,
    required CompanyModel company,
    required String employeeId,
    required String employeeName,
    required String employeeEmail,
    required String workDate,
    required DateTime proposedTimeIn,
    DateTime? proposedTimeOut,
    DateTime? currentTimeIn,
    DateTime? currentTimeOut,
    String? existingEntryId,
  }) async {
    if (proposedTimeOut != null && !proposedTimeOut.isAfter(proposedTimeIn)) {
      throw StateError('Time out must be after time in.');
    }

    final existingPending = await findPendingForWorkDate(
      employeeId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
    );
    if (existingPending != null) {
      throw StateError(
        'A change request for this employee on $workDate is already pending. '
        'Wait until it is approved or rejected before submitting again.',
      );
    }

    // Always resolve the live time card so current* is never missed.
    final prior = await _timeEntries.findPriorEntry(
      userId: employeeId,
      companyId: company.id,
      companyDocumentId: company.firestoreId,
      workDate: workDate,
      entryId: existingEntryId,
    );

    final resolvedEntryId = prior?.id ?? existingEntryId;
    final resolvedTimeIn = prior?.timeIn ?? currentTimeIn;
    final resolvedTimeOut = prior != null ? prior.timeOut : currentTimeOut;

    final currentInLabel = resolvedTimeIn == null
        ? 'No prior record'
        : formatClockTime(resolvedTimeIn);
    final currentOutLabel = resolvedTimeOut == null
        ? (resolvedTimeIn == null ? 'No prior record' : 'Open')
        : formatClockTime(resolvedTimeOut);

    final data = <String, dynamic>{
      'type': 'timeEdit',
      'status': 'pending',
      'requesterId': requester.id,
      'requesterName': requester.username,
      'requesterEmail': requester.email,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'employeeEmail': employeeEmail,
      'companyId': company.id,
      'companyDocumentId': company.firestoreId,
      'companyName': company.name,
      'workDate': workDate,
      'proposedTimeIn': Timestamp.fromDate(proposedTimeIn),
      'proposedTimeOut':
          proposedTimeOut == null ? null : Timestamp.fromDate(proposedTimeOut),
      'currentTimeIn': resolvedTimeIn == null
          ? null
          : Timestamp.fromDate(resolvedTimeIn),
      'currentTimeOut': resolvedTimeOut == null
          ? null
          : Timestamp.fromDate(resolvedTimeOut),
      'currentTimeInLabel': currentInLabel,
      'currentTimeOutLabel': currentOutLabel,
      'existingEntryId': resolvedEntryId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final doc = await _requests.add(data);
    final snapshot = await doc.get();
    return TimeCardChangeRequest.fromFirestore(
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

  /// Applies the proposed time entry, then marks the request approved.
  Future<void> approve(TimeCardChangeRequest request) async {
    if (!request.isPending) {
      throw StateError('Only pending requests can be approved.');
    }

    final company = CompanyModel(
      id: request.companyId,
      documentId: request.companyDocumentId.isEmpty
          ? null
          : request.companyDocumentId,
      name: request.companyName,
      passwordHash: '',
      createdBy: '',
    );

    await _timeEntries.adminSaveEntry(
      entryId: request.existingEntryId,
      userId: request.employeeId,
      userEmail: request.employeeEmail,
      username: request.employeeName,
      company: company,
      timeIn: request.proposedTimeIn,
      timeOut: request.proposedTimeOut,
    );

    await _requests.doc(request.id).update({
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
